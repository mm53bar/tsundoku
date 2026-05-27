class BookIdentifier < ApplicationRecord
  belongs_to :book

  validates :kind, :value, presence: true
  validates :kind, uniqueness: { scope: [ :book_id, :value ] }

  ISBN_KINDS = %w[isbn isbn10 isbn13].freeze

  scope :isbn, -> { where(kind: ISBN_KINDS) }
end
