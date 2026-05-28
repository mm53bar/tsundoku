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


  validates :calibre_id, uniqueness: true, allow_nil: true
  validates :title, :path, :imported_at, presence: true

  scope :by_title, -> { order(Arel.sql("COALESCE(NULLIF(sort_title, ''), title) COLLATE NOCASE ASC")) }
  scope :recently_added, -> { order(added_at: :desc) }

  def author_names
    authors.map(&:name).join(", ")
  end

  def isbn
    book_identifiers.isbn.order(Arel.sql("CASE kind WHEN 'isbn13' THEN 0 WHEN 'isbn' THEN 1 WHEN 'isbn10' THEN 2 END")).first&.value
  end

  def cover_full_path
    if enriched_cover_path.present?
      enriched = Rails.root.join("storage", enriched_cover_path).to_s
      return enriched if File.exist?(enriched)
    end
    return nil unless cover_path.present?
    File.join(Rails.configuration.x.library_path, cover_path)
  end

  def cover_available?
    cover_full_path.present? && File.exist?(cover_full_path)
  end

  def enriched?
    last_enriched_at.present?
  end

  def epub_full_path
    return nil unless file_name.present? && file_format.present?
    File.join(Rails.configuration.x.library_path, path, "#{file_name}.#{file_format.downcase}")
  end

  def epub_downloadable?
    path = epub_full_path
    path.present? && File.exist?(path)
  end

  # Shelves owned by the given user that contain this book. has_many :shelves
  # is global (any user); this is the per-user filter we want in views.
  def shelves_for(user)
    return Shelf.none unless user
    shelves.where(user: user)
  end

  KOBO_UUID_NAMESPACE = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "tsundoku-kobo-books").freeze

  # Deterministic v5 UUID derived from the integer id. Used as the Kobo
  # entitlement/revision/work id across the sync payload.
  def kobo_uuid
    Digest::UUID.uuid_v5(KOBO_UUID_NAMESPACE, id.to_s)
  end
end
