module BookIdentifiersHelper
  IDENTIFIER_LABELS = {
    "hardcover_book"    => "Hardcover Book",
    "hardcover_edition" => "Hardcover Edition",
    "isbn"              => "ISBN",
    "isbn13"            => "ISBN-13",
    "isbn10"            => "ISBN-10",
    "asin"              => "ASIN",
    "openlibrary"       => "Open Library",
    "goodreads"         => "Goodreads",
    "google_books"      => "Google Books"
  }.freeze

  def book_identifier_label(kind)
    IDENTIFIER_LABELS[kind] || kind.humanize
  end

  def book_identifier_url(book_identifier)
    kind  = book_identifier.kind
    value = book_identifier.value
    return nil if value.blank?

    case kind
    when "hardcover_book"    then "https://hardcover.app/books/#{value}"
    when "hardcover_edition" then "https://hardcover.app/editions/#{value}"
    when "asin"              then "https://www.amazon.com/dp/#{value}"
    when "openlibrary"       then "https://openlibrary.org/works/#{value}"
    when "goodreads"         then "https://www.goodreads.com/book/show/#{value}"
    when "google_books"      then "https://books.google.com/books?id=#{value}"
    end
  end

  IDENTIFIER_DISPLAY_ORDER = %w[isbn13 isbn isbn10 asin hardcover_book hardcover_edition openlibrary goodreads google_books].freeze

  def sorted_book_identifiers(book)
    book.book_identifiers.sort_by do |bi|
      [ IDENTIFIER_DISPLAY_ORDER.index(bi.kind) || 99, bi.kind, bi.value ]
    end
  end
end
