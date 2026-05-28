class ListEntry < ApplicationRecord
  belongs_to :list, inverse_of: :list_entries
  belongs_to :book, optional: true

  validates :title, presence: true

  def matched?
    book_id.present?
  end

  def display_author
    return author_name if author_name.present?
    book&.author_names
  end
end
