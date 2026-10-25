require "cgi"

# Match a single { title:, author: } entry against the local Book table.
# Used by Lists when building entries from a pasted source.
#
# Matching strategy (first hit wins):
#   0. Stored `hardcover_book` identifier, when the entry carries one
#   1. Exact title (case-insensitive) + exact normalized author match
#   2. Exact title (case-insensitive) — single candidate only (no ambiguity)
#   3. Subtitle-tolerant title prefix + normalized author
#   4. Steps 1–3 again with the entry's resolved title/author, if any
#   5. nil (no match — list entry stays "not in library")
#
# Author normalization uses Author.normalize_name so the same
# "James S.A. Corey" ↔ "James S. A. Corey" tolerance applies as in
# enrichment slug-stamping.
class BookMatcher
  def self.match(entry)
    by_hardcover_id(entry[:hardcover_book_id]) ||
      new(entry).match ||
      (new(title: entry[:resolved_title], author: entry[:resolved_author]).match if entry[:resolved_title].present?)
  end

  def self.by_hardcover_id(hardcover_book_id)
    return nil if hardcover_book_id.blank?

    Book.joins(:book_identifiers)
        .find_by(book_identifiers: { kind: "hardcover_book", value: hardcover_book_id.to_s })
  end

  def initialize(entry)
    @title  = entry[:title].to_s.strip
    @author = entry[:author].to_s.strip
  end

  def match
    return nil if @title.empty?

    candidates = Book.where("LOWER(title) = ?", @title.downcase).includes(:authors)

    case candidates.size
    when 0
      match_by_title_prefix
    when 1
      candidates.first
    else
      # Multiple exact-title candidates: only match if the author hint
      # picks one out. Without an author, refuse rather than guess —
      # listing "Common Title" with no further info shouldn't silently
      # pin the entry to whichever Book happened to be inserted first.
      # (The prior code fell through to the title-prefix path here,
      # which "took the first match" and contradicted the documented
      # strategy.)
      narrow_by_author(candidates)
    end
  end

  private

  def match_by_title_prefix
    return nil if @title.length < 4

    # Take the part of the title before any colon — books with subtitles
    # sometimes have the subtitle on one side but not the other ("Accelerate"
    # in Calibre vs "Accelerate: Building..." on a list).
    base = @title.split(/[:\-—]/).first.to_s.strip
    return nil if base.length < 4

    candidates = Book.where("LOWER(title) LIKE ?", "#{base.downcase}%").limit(5).includes(:authors)
    return nil if candidates.empty?
    return candidates.first if candidates.size == 1 && @author.empty?

    narrow_by_author(candidates) || (@author.empty? ? candidates.first : nil)
  end

  def narrow_by_author(candidates)
    return nil if @author.empty?
    needle = Author.normalize_name(@author)

    candidates.find do |book|
      book.authors.any? { |a| Author.normalize_name(a.name) == needle }
    end
  end
end
