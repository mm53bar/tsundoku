class Book < ApplicationRecord
  belongs_to :series, optional: true

  has_many :book_authors, -> { order(:position) }, dependent: :destroy, inverse_of: :book
  has_many :authors, through: :book_authors

  has_many :book_tags, dependent: :destroy, inverse_of: :book
  has_many :tags, through: :book_tags

  validates :calibre_id, presence: true, uniqueness: true
  validates :title, :path, :imported_at, presence: true

  scope :by_title, -> { order(Arel.sql("COALESCE(NULLIF(sort_title, ''), title) COLLATE NOCASE ASC")) }

  def author_names
    authors.map(&:name).join(", ")
  end

  def cover_full_path
    return nil unless cover_path.present?
    File.join(Rails.configuration.x.library_path, cover_path)
  end

  def cover_available?
    cover_full_path.present? && File.exist?(cover_full_path)
  end

  def epub_full_path
    return nil unless file_name.present? && file_format.present?
    File.join(Rails.configuration.x.library_path, path, "#{file_name}.#{file_format.downcase}")
  end
end
