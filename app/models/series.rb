class Series < ApplicationRecord
  has_many :books, dependent: :nullify

  validates :name, presence: true
  validates :calibre_id, uniqueness: true, allow_nil: true

  scope :by_name, -> { order(Arel.sql("COALESCE(NULLIF(sort_name, ''), name) COLLATE NOCASE ASC")) }

  def to_param
    "#{id}-#{name.parameterize}"
  end

  def hardcover_url
    return nil if hardcover_slug.blank?
    "https://hardcover.app/series/#{ERB::Util.url_encode(hardcover_slug)}"
  end
end
