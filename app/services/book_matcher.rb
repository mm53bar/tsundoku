require "cgi"

# Match a single { title:, author: } entry against the local Book table.
# Used by Lists when building entries from a pasted source.
#
# Matching strategy (first hit wins):
#   1. Exact title (case-insensitive) + exact normalized author match
#   2. Exact title (case-insensitive) — single candidate only (no ambiguity)
#   3. Subtitle-tolerant title prefix + normalized author
#   4. nil (no match — list entry stays "not in library")
#
# Author normalization mirrors BookEnricher#normalized_author_name so the
# same "James S.A. Corey" ↔ "James S. A. Corey" tolerance applies.
class BookMatcher
  HONORIFIC_TRAILING = BookEnricher::HONORIFIC_TRAILING

  def self.match(entry)
    new(entry).match
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
      narrow_by_author(candidates) || match_by_title_prefix
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
    needle = normalize_author(@author)

    candidates.find do |book|
      book.authors.any? { |a| normalize_author(a.name) == needle }
    end
  end

  def normalize_author(name)
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
end
