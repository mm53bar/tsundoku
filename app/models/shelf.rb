class Shelf < ApplicationRecord
  belongs_to :user
  has_many :shelf_entries, -> { order(:position) }, dependent: :destroy, inverse_of: :shelf
  has_many :books, through: :shelf_entries

  # NB: NOT dependent: :destroy — when a Shelf is destroyed we want the
  # kobo_synced_shelves row to survive as an orphan so the next sync
  # can emit a DeletedTag using its cached kobo_uuid.
  has_many :kobo_synced_shelves, primary_key: :id, foreign_key: :shelf_id

  before_validation :set_kobo_uuid, on: :create

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :kobo_uuid, presence: true, uniqueness: true

  scope :by_name, -> { order(Arel.sql("name COLLATE NOCASE ASC")) }
  scope :syncing, -> { where(sync_to_kobo: true) }

  def to_param
    "#{id}-#{name.parameterize}"
  end

  private

  def set_kobo_uuid
    self.kobo_uuid ||= SecureRandom.uuid
  end
end
