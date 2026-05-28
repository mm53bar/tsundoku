module BooksHelper
  # Combined searchable text for a book card — used by the library typeahead
  # filter Stimulus controller. Includes title, author names, and series
  # name; everything lowercased and space-joined for substring matching.
  def book_searchable_text(book)
    parts = [ book.title ]
    parts.concat(book.authors.map(&:name))
    parts << book.series.name if book.series
    parts.compact.map(&:to_s).join(" ").downcase
  end
end
