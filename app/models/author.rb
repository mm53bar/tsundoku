class Author < ApplicationRecord
  has_many :book_authors, dependent: :destroy
  has_many :books, through: :book_authors

  validates :name, presence: true
  validates :calibre_id, uniqueness: true, allow_nil: true

  scope :by_name, -> { order(Arel.sql("COALESCE(NULLIF(sort_name, ''), name) COLLATE NOCASE ASC")) }
end
