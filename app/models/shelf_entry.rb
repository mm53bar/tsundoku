class ShelfEntry < ApplicationRecord
  belongs_to :shelf, inverse_of: :shelf_entries
  belongs_to :book
end
