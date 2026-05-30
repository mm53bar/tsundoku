module BooksHelper
  # Combined searchable text for a book card — used by the library typeahead
  # filter Stimulus controller. Includes title, author names, and series
  # name; everything lowercased and space-joined for substring matching.
  def book_searchable_text(book)
    parts = [ book.title ]
    parts.concat(book.authors.map(&:name))
    parts << book.series.name if book.series
    parts.concat(book.lists.map(&:name))
    parts.compact.map(&:to_s).join(" ").downcase
  end

  # Format an integer-minutes duration as "3h 16m", "45m", or "1h" for
  # the reading-progress UI. Returns nil for nil/zero input so callers
  # can chain `&.presence` and skip the surrounding markup.
  def format_reading_time(minutes)
    return nil if minutes.nil? || minutes.to_i <= 0
    h, m = minutes.to_i.divmod(60)
    return "#{m}m" if h.zero?
    return "#{h}h" if m.zero?
    "#{h}h #{m}m"
  end
end
