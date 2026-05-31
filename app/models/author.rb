class Author < ApplicationRecord
  has_many :book_authors, dependent: :destroy
  has_many :books, through: :book_authors

  validates :name, presence: true
  validates :calibre_id, uniqueness: true, allow_nil: true

  # Plain display-name sort. Surname-first sorting was dropped in
  # favor of search-driven find — both the library and authors
  # indexes carry a substring filter, so scanning by surname stopped
  # being load-bearing. Matches Hardcover's flat-name convention.
  scope :by_name, -> { order(Arel.sql("name COLLATE NOCASE ASC")) }

  # Allows an optional comma before the honorific so "Jane Goodall, Ph.D."
  # strips to "Jane Goodall" (the old regex left the comma stranded).
  HONORIFIC_TRAILING = /,?\s+(Ph\.?D\.?|M\.?D\.?|D\.?D\.?S\.?|Esq\.?|Jr\.?|Sr\.?|II|III|IV)\.?\s*\z/i

  # Canonical form for cross-source matching. Lowercases, strips trailing
  # academic / generational honorifics, drops dots, and merges consecutive
  # single-letter tokens so "James S.A. Corey", "James S. A. Corey", and
  # "James S A Corey" all hash to "james sa corey". Used by:
  #   - BookEnricher when stamping Hardcover slugs onto local authors
  #   - BookMatcher when matching list entries to library books
  #   - BooksController#update when finding-or-creating authors from the
  #     edit form's comma-separated names field
  def self.normalize_name(name)
    cleaned = name.to_s.strip.gsub(HONORIFIC_TRAILING, "").downcase.tr(".", " ").gsub(/\s+/, " ").strip
    tokens = cleaned.split(" ")

    merged = []
    initials = +""
    tokens.each do |t|
      if t.length == 1
        initials << t
      else
        merged << initials unless initials.empty?
        initials = +""
        merged << t
      end
    end
    merged << initials unless initials.empty?
    merged.join(" ")
  end

  def normalized_name
    self.class.normalize_name(name)
  end

  def to_param
    "#{id}-#{name.parameterize}"
  end

  def hardcover_url
    return nil if hardcover_slug.blank?
    "https://hardcover.app/authors/#{ERB::Util.url_encode(hardcover_slug)}"
  end
end
