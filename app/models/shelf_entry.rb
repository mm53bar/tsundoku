class ShelfEntry < ApplicationRecord
  # touch: true so adding/removing entries bumps shelf.updated_at, which is
  # how the Kobo sync delta detects shelf membership changes.
  belongs_to :shelf, inverse_of: :shelf_entries, touch: true
  belongs_to :book
end
