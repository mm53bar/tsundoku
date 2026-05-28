require "json"

# Turns user-pasted text into a canonical array of { title:, author: } entry
# hashes that the controller can hand to BookMatcher and persist as
# ListEntry records.
#
# Accepted shapes (auto-detected):
#
#   1. JSON array of objects:
#        [{"title":"1984","author":"George Orwell"}, ...]
#      keys may be either "title"/"author" or :title/:author.
#
#   2. JSON array of strings (each treated as a title with no author):
#        ["1984","Animal Farm", ...]
#
#   3. Line-delimited free text; one book per line. Recognized separators
#      (in order):
#        "Title — Author"   (em dash)
#        "Title – Author"   (en dash)
#        "Title - Author"   (hyphen)
#        "Title by Author"  (case-insensitive)
#      Lines starting with # or // are treated as comments and skipped.
#      Numeric prefixes like "1. " or "12) " are stripped from the start.
#
# Returns an array; never raises. Unparseable lines become { title: line,
# author: nil } as a best effort.
class ListEntryParser
  COMMENT_PREFIXES = %w[# // --].freeze
  NUMERIC_PREFIX   = /\A\s*\d+[.)]\s+/

  def self.parse(input)
    new(input).parse
  end

  def initialize(input)
    @input = input.to_s
  end

  def parse
    stripped = @input.strip
    return [] if stripped.empty?

    parsed = try_json(stripped)
    return parsed if parsed

    parse_lines(stripped)
  end

  private

  def try_json(stripped)
    return nil unless stripped.start_with?("[", "{")

    data = JSON.parse(stripped)
    data = [ data ] if data.is_a?(Hash)
    return nil unless data.is_a?(Array)

    data.map { |item| extract_entry(item) }.compact
  rescue JSON::ParserError
    nil
  end

  def extract_entry(item)
    case item
    when Hash
      h = item.with_indifferent_access
      title  = h["title"].to_s.strip
      author = h["author"].to_s.strip
      title.empty? ? nil : { title: title, author: author.empty? ? nil : author }
    when String
      title = item.strip
      title.empty? ? nil : { title: title, author: nil }
    end
  end

  def parse_lines(text)
    text.lines.map do |raw|
      line = raw.strip
      next nil if line.empty?
      next nil if COMMENT_PREFIXES.any? { |prefix| line.start_with?(prefix) }
      line = line.sub(NUMERIC_PREFIX, "")

      split_line(line)
    end.compact
  end

  # In order of specificity:
  #   1. "Title by Author" (case-insensitive, only at word boundary)
  #   2. "Title — Author" / "Title – Author" / "Title - Author"
  # Both separators are common in copy-pasted lists; "by" wins because it's
  # unambiguous when present.
  def split_line(line)
    if (m = line.match(/\A(.+?)\s+by\s+(.+)\z/i))
      { title: m[1].strip, author: m[2].strip }
    elsif (m = line.match(/\A(.+?)\s+[—–-]\s+(.+)\z/))
      { title: m[1].strip, author: m[2].strip }
    else
      { title: line, author: nil }
    end
  end
end
