class Shelf < ApplicationRecord
  belongs_to :user
  has_many :shelf_entries, -> { order(:position) }, dependent: :destroy, inverse_of: :shelf
  has_many :books, through: :shelf_entries

  # NB: NOT dependent: :destroy — when a Shelf is destroyed we want the
  # kobo_synced_shelves row to survive as an orphan so the next sync
  # can emit a DeletedTag using its cached kobo_uuid.
  has_many :kobo_synced_shelves, primary_key: :id, foreign_key: :shelf_id

  before_validation :set_kobo_uuid, on: :create
  # The per-user Starred shelf is the target of the star icon — flipping
  # its sync_to_kobo to false would silently break that affordance. Force
  # it back to true on every save so a UI edit can't land us in a broken
  # state.
  before_save    :force_sync_when_default_for_star
  before_destroy :prevent_destroy_when_default_for_star

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :kobo_uuid, presence: true, uniqueness: true

  scope :by_name,         -> { order(Arel.sql("name COLLATE NOCASE ASC")) }
  scope :syncing,         -> { where(sync_to_kobo: true) }
  # Tags-on-Kobo are emitted for syncing shelves that aren't the user's
  # default Starred shelf. Starred intentionally doesn't appear as a
  # collection on the device — the Kobo's "My Books" view already
  # covers "everything on the device" so a duplicate collection is
  # busywork. See Kobo::SyncController#sync.
  scope :emitting_as_tag, -> { syncing.where(default_for_star: false) }

  def to_param
    "#{id}-#{name.parameterize}"
  end

  private

  def set_kobo_uuid
    self.kobo_uuid ||= SecureRandom.uuid
  end

  def force_sync_when_default_for_star
    self.sync_to_kobo = true if default_for_star?
  end

  def prevent_destroy_when_default_for_star
    return unless default_for_star?
    errors.add(:base, "the Starred shelf can't be deleted")
    throw :abort
  end
end
