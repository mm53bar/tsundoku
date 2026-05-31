class Book < ApplicationRecord
  belongs_to :series, optional: true
  belongs_to :publisher, optional: true

  has_many :book_authors, -> { order(:position) }, dependent: :destroy, inverse_of: :book
  has_many :authors, through: :book_authors

  has_many :book_tags, dependent: :destroy, inverse_of: :book
  has_many :tags, through: :book_tags

  has_many :book_identifiers, dependent: :destroy, inverse_of: :book

  has_many :list_entries, dependent: :nullify, inverse_of: :book
  has_many :lists, -> { distinct }, through: :list_entries

  has_many :readings, dependent: :destroy

  has_many :shelf_entries, dependent: :destroy
  has_many :shelves, -> { distinct }, through: :shelf_entries

  # Nullify rather than destroy: when a book is deleted we want the
  # kobo_synced_books rows to *survive* so the next sync per user can
  # emit a tombstone using their snapshot kobo_uuid. The sync controller
  # destroys those rows after the tombstone is delivered, completing the
  # cleanup.
  has_many :kobo_synced_books, dependent: :nullify

  # Both hooks are required: before_validation handles normal saves, and
  # before_save covers the BookIngester path that does
  # Book.new(...).save!(validate: false) to persist a placeholder before
  # move_file knows the final path. The body is idempotent (||=), so
  # running on every save is a no-op after the UUID lands.
  before_validation :set_kobo_uuid
  before_save       :set_kobo_uuid
  before_destroy    :broadcast_tombstone_to_kobo_users
  before_destroy    -> { assets.delete_all! }

  # After a newly-ingested book commits, re-run BookMatcher against any
  # ListEntry rows that didn't have a library match at list-import time.
  # Auto-ingest from Shelfmark is the motivating case: a list shows the
  # book as "Not in library", Shelfmark drops the file, the next scan
  # creates the Book — this hook closes the loop without the user having
  # to click "Re-import".
  after_commit :match_pending_list_entries, on: :create

  validates :calibre_id, uniqueness: true, allow_nil: true
  validates :title, :imported_at, presence: true
  # Path is required on create (Calibre importer's contract), not on
  # update. BookIngester saves a placeholder with `validate: false` and
  # then runs move_file to backfill path/file_name; if move_file fails
  # for any reason the row is left with path: "". A presence check on
  # update would then block every subsequent edit (enrichment, manual
  # metadata changes) on that row. BookAssets handles blank path
  # gracefully — downloads return 404, sync skips — so the row stays
  # editable without surfacing a misleading validation error.
  validates :path, presence: true, on: :create
  validates :kobo_uuid, presence: true, uniqueness: true

  scope :by_title, -> { order(Arel.sql("COALESCE(NULLIF(sort_title, ''), title) COLLATE NOCASE ASC")) }
  scope :recently_added, -> { order(added_at: :desc) }

  def author_names
    authors.map(&:name).join(", ")
  end

  def isbn
    book_identifiers.isbn.order(Arel.sql("CASE kind WHEN 'isbn13' THEN 0 WHEN 'isbn' THEN 1 WHEN 'isbn10' THEN 2 END")).first&.value
  end

  # All file/path concerns route through this PORO so the safe-resolution
  # rules live in one place. Callers should use `book.assets.epub_full_path`
  # (etc.) rather than reaching for paths directly. See app/models/book_assets.rb.
  def assets
    @assets ||= BookAssets.new(self)
  end

  def enriched?
    last_enriched_at.present?
  end

  # Shelves owned by the given user that contain this book. has_many :shelves
  # is global (any user); this is the per-user filter we want in views.
  def shelves_for(user)
    return Shelf.none unless user
    shelves.where(user: user)
  end

  private

  # Make sure every Kobo-connected user gets a tombstone on their next
  # sync — even if Tsundoku never told them about this book (CWA might
  # have, or the user might have side-loaded by some other means).
  #
  # Tombstones for entitlements the device doesn't have are silently
  # ignored, so over-broadcasting is harmless. The alternative — only
  # tombstoning users with an existing kobo_synced_books row — leaves
  # orphans on devices whose state Tsundoku never tracked.
  #
  # Skips users who already have a row for this book; `dependent: :nullify`
  # turns those into tombstones in the same destroy pass.
  def broadcast_tombstone_to_kobo_users
    return if kobo_uuid.blank?

    User.where.not(kobo_handle: [ nil, "" ]).find_each do |user|
      next if user.kobo_synced_books.where(book_id: id).exists?
      user.kobo_synced_books.create!(book_id: nil, kobo_uuid: kobo_uuid)
    end
  end

  # Books imported from Calibre carry their original Calibre UUID in
  # `uuid` — calibre-web (and the CWA fork) use that same value as the
  # Kobo entitlement Id, so adopting it here means a device that was
  # previously syncing via CWA sees Tsundoku's entitlements as already
  # known. Books created any other way (manual ingest, no metadata.db)
  # get a fresh random UUID.
  def set_kobo_uuid
    self.kobo_uuid ||= uuid.presence || SecureRandom.uuid
  end

  # Pre-filter unmatched ListEntry rows by title (exact or
  # subtitle-tolerant prefix), then defer to BookMatcher for the actual
  # match — same logic that ran at list-import time, just re-run against
  # the new book. The pre-filter keeps the cost bounded by entries that
  # *could plausibly* match this title; for entries that survive it we
  # call BookMatcher exactly once each.
  def match_pending_list_entries
    return if title.blank?

    base = title.split(/[:\-—]/).first.to_s.strip
    patterns = [ title.downcase ]
    patterns << "#{base.downcase}%" if base.length >= 4

    sql = patterns.map { "LOWER(title) LIKE ?" }.join(" OR ")
    candidates = ListEntry.where(book_id: nil).where(sql, *patterns)

    candidates.find_each do |entry|
      next unless BookMatcher.match(title: entry.title, author: entry.author_name)&.id == id
      entry.update_column(:book_id, id)
    end
  end
end
