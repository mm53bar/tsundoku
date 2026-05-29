class KoboSyncedBook < ApplicationRecord
  belongs_to :user
  # Look through Book's soft-delete default_scope: after a user deletes a
  # book, this row needs to keep resolving to the (now-deleted) Book so
  # the next sync can emit a tombstone with its kobo_uuid.
  belongs_to :book, -> { with_deleted }

  validates :user_id, uniqueness: { scope: :book_id }
end
