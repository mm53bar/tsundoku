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
  # checks, used by controllers and views. Today every gated action
  # collapses to `admin?` (single-role homelab), but naming the
  # capability at the callsite makes the intent explicit and gives
  # us a single place to refine if a role ever sits between
  # reader and admin.
  #
  # Pattern (per docs/reviews/rails-code-review.md §2):
  #   - controllers call `current_user&.can_X?` before destructive or
  #     admin-only actions
  #   - views use the same predicate to decide whether to render the
  #     action's button/link
  #   - ownership-scoped lookups (`current_user.shelves.find(...)`)
  #     stay as-is — they're already the right Rails idiom
  def can_import_library?
    admin?
  end

  def can_ingest?
    admin?
  end

  def can_edit_book?(_book = nil)
    admin?
  end

  def can_destroy_book?(_book = nil)
    admin?
  end

  def can_enrich_book?(_book = nil)
    admin?
  end

  def can_manage_lists?
    admin?
  end

  def can_edit_list?(_list = nil)
    admin?
  end
end
