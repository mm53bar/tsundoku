class Tag < ApplicationRecord
  has_many :book_tags, dependent: :destroy
  has_many :books, through: :book_tags

  validates :name, presence: true, uniqueness: true
  validates :calibre_id, uniqueness: true, allow_nil: true
end
