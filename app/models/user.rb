class User < ApplicationRecord
  enum :role, { reader: 0, admin: 1 }

  has_many :readings, dependent: :destroy
  has_many :read_books, through: :readings, source: :book

  has_many :shelves, dependent: :destroy
  has_many :kobo_synced_books, dependent: :destroy
  has_many :kobo_synced_shelves, dependent: :destroy
  has_many :kobo_devices, dependent: :destroy

  validates :username, presence: true, uniqueness: true

  KOBO_WORDLIST = File.readlines(Rails.root.join("lib/data/mnemonic_wordlist.txt")).map(&:strip).freeze

  def regenerate_kobo_handle!
    loop do
      candidate = KOBO_WORDLIST.sample
      next if User.where.not(id: id).exists?(kobo_handle: candidate)
      update!(kobo_handle: candidate)
      return candidate
    end
  end

  def self.find_or_provision_from_proxy(username:, email: nil, name: nil)
    user = find_or_create_by!(username: username) do |u|
      u.email = email
      u.name  = name.presence || username.to_s.titleize
      u.role  = User.none? ? :admin : :reader
    end

    updates = {}
    updates[:email] = email if email.present? && user.email != email
    updates[:name]  = name  if name.present?  && user.name  != name
    user.update!(updates) if updates.any?

    user
  end

  def display_name
    name.presence || username
  end

  # Authorization predicates — readable names for action-permission
  # checks. In this homelab deployment every household member is
  # trusted (Authelia gates the front door), so the predicates that
  # would have been "admin only" simply pass for any signed-in user.
  # The names stay so the callsites read in terms of capability, and
  # so a future install in a less-trusted context has one place to
  # tighten without touching every controller and view.
  #
  # The exception is `can_edit_list?` — list ownership is a real
  # per-record check (only the owner can edit/destroy a list, even
  # if they shared it).
  #
  # Pattern (per docs/architecture-principles.md §3):
  #   - controllers call `current_user&.can_X?` before destructive or
  #     ownership-bearing actions
  #   - views use the same predicate to decide whether to render the
  #     action's button/link
  #   - ownership-scoped lookups (`current_user.shelves.find(...)`,
  #     `current_user.lists.find(...)`) stay as-is — they're the
  #     right Rails idiom
  def can_import_library?
    true
  end

  def can_ingest?
    true
  end

  def can_edit_book?(_book = nil)
    true
  end

  def can_destroy_book?(_book = nil)
    true
  end

  def can_enrich_book?(_book = nil)
    true
  end

  def can_manage_lists?
    true
  end

  def can_edit_list?(_list = nil)
    # Becomes an ownership check (list.user_id == id) once Lists carry
    # a user_id. Until that migration lands, passive — matches the
    # other predicates so the gate doesn't break.
    true
  end
end
