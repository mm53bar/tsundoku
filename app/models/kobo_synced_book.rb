class KoboSyncedBook < ApplicationRecord
  belongs_to :user
  # Optional because Book#destroy nullifies book_id on these rows so the
  # snapshot below can still drive a tombstone in the next sync.
  belongs_to :book, optional: true

  # Snapshot of the book's kobo_uuid taken when this sync record was
  # created. Lets us emit a tombstone (ChangedEntitlement IsRemoved=true)
  # for the next sync after the book has been destroyed — same approach
  # KoboSyncedShelf uses for shelves.
  before_validation :snapshot_kobo_uuid, on: :create

  validates :kobo_uuid, presence: true
  validates :user_id, uniqueness: { scope: :book_id }, if: :book_id?

  private

  def snapshot_kobo_uuid
    self.kobo_uuid ||= book&.kobo_uuid
  end
end
