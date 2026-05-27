class Book < ApplicationRecord
  belongs_to :series, optional: true
  belongs_to :publisher, optional: true

  has_many :book_authors, -> { order(:position) }, dependent: :destroy, inverse_of: :book
  has_many :authors, through: :book_authors

  has_many :book_tags, dependent: :destroy, inverse_of: :book
  has_many :tags, through: :book_tags

  has_many :book_identifiers, dependent: :destroy, inverse_of: :book

  validates :calibre_id, presence: true, uniqueness: true
  validates :title, :path, :imported_at, presence: true

  scope :by_title, -> { order(Arel.sql("COALESCE(NULLIF(sort_title, ''), title) COLLATE NOCASE ASC")) }
  scope :recently_added, -> { order(added_at: :desc) }

  def author_names
    authors.map(&:name).join(", ")
  end

  def isbn
    book_identifiers.isbn.order(Arel.sql("CASE kind WHEN 'isbn13' THEN 0 WHEN 'isbn' THEN 1 WHEN 'isbn10' THEN 2 END")).first&.value
  end

  def cover_full_path
    if enriched_cover_path.present?
      enriched = Rails.root.join("storage", enriched_cover_path).to_s
      return enriched if File.exist?(enriched)
    end
    return nil unless cover_path.present?
    File.join(Rails.configuration.x.library_path, cover_path)
  end

  def cover_available?
    cover_full_path.present? && File.exist?(cover_full_path)
  end

  def enriched?
    last_enriched_at.present?
  end

  def epub_full_path
    return nil unless file_name.present? && file_format.present?
    File.join(Rails.configuration.x.library_path, path, "#{file_name}.#{file_format.downcase}")
  end
end
