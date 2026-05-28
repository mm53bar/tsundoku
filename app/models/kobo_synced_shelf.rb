class KoboSyncedShelf < ApplicationRecord
  belongs_to :user
  # shelf_id is intentionally without a foreign-key constraint and the
  # association is optional — when a Shelf is destroyed in Tsundoku we
  # want this row to survive so the next sync emits a DeletedTag using
  # the cached kobo_uuid.
  belongs_to :shelf, optional: true

  validates :kobo_uuid, presence: true
  validates :shelf_id, uniqueness: { scope: :user_id }
end
