# Picks the one Hardcover hit a typed (title, author) clearly refers to, or
# declines. Declining is the point: a wrong confident match is worse than
# asking the user to pick.
#
# A hit is a candidate when its title matches and, if an author was typed,
# one of its authors matches. A title matches exactly (main or alternative
# title) or with subtitles stripped — the latter on the main title only,
# because alternative titles are full of "Dune: Book 2"-style prefixes. Compilations never qualify. The winner is the only
# candidate, or the most-read one when it has POPULARITY_MARGIN times the
# runner-up's readers (duplicate Hardcover records of one book look like
# this).
class ClearWinner
  POPULARITY_MARGIN = 5
  SUGGESTION_LIMIT = 3

  def initialize(hits, title:, author: nil)
    @hits = hits.reject(&:compilation?)
    @title = title.to_s
    @author = author.to_s.strip
  end

  def hit
    return candidates.first if candidates.size == 1
    return nil if candidates.size < 2

    top, runner_up = candidates.first(2)
    top if top.users_count >= POPULARITY_MARGIN * [ runner_up.users_count, 1 ].max
  end

  # What to offer the user when there's no winner: the tied candidates if
  # any, otherwise the search's best guesses.
  def suggestions
    (candidates.presence || @hits).first(SUGGESTION_LIMIT)
  end

  def self.normalize_title(title)
    title.to_s.downcase.delete("'’").gsub(/[^\p{Alnum}\s]/, " ").squish
  end

  def self.base_title(title)
    normalize_title(title.to_s.split(/[:—–]|\s-\s/).first)
  end

  private

  def candidates
    @candidates ||= @hits
      .select { |h| (exact_title_match?(h) || base_title_match?(h)) && author_matches?(h) }
      .sort_by { |h| -h.users_count }
  end

  def exact_title_match?(hit)
    wanted = self.class.normalize_title(@title)
    wanted.present? && [ hit.title, *hit.alternative_titles ].any? { |t| self.class.normalize_title(t) == wanted }
  end

  def base_title_match?(hit)
    wanted = [ self.class.normalize_title(@title), self.class.base_title(@title) ]
    offered = [ self.class.normalize_title(hit.title), self.class.base_title(hit.title) ]
    (wanted & offered).any?(&:present?)
  end

  def author_matches?(hit)
    return true if @author.empty?

    typed = Author.normalize_name(@author)
    hit.author_names.any? do |name|
      normalized = Author.normalize_name(name)
      normalized == typed || normalized.split(" ").last == typed
    end
  end
end
