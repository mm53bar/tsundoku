class Publisher < ApplicationRecord
  has_many :books, dependent: :nullify

  validates :name, presence: true
  validates :calibre_id, uniqueness: true, allow_nil: true
end
