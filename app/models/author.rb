class Author < ApplicationRecord
  has_many :book_authors, dependent: :destroy
  has_many :books, through: :book_authors

  validates :name, presence: true
  validates :calibre_id, uniqueness: true, allow_nil: true

  scope :by_name, -> { order(Arel.sql("COALESCE(NULLIF(sort_name, ''), name) COLLATE NOCASE ASC")) }

  def to_param
    "#{id}-#{name.parameterize}"
  end

  def hardcover_url
    return nil if hardcover_slug.blank?
    "https://hardcover.app/authors/#{ERB::Util.url_encode(hardcover_slug)}"
  end
end
