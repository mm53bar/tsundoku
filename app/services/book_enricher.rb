require "uri"
require "cgi"

# Builds a proposal hash from Hardcover for a single Book.
#
# This service is non-mutating by design — it queries Hardcover and packages
# the result into a structured proposal that the user can review on the
# edit form. The form's submit applies (or skips) each piece. That keeps
# the user in control and unifies "no Hardcover token" / "manual edit" /
# "enrich-then-review" into a single edit-form flow.
class BookEnricher
  HARDCOVER_RESIZE_HOST = "production-img.hardcover.app".freeze

  def initialize(book)
    @book = book
  end

  # Returns:
  #   {
  #     "source"     => "hardcover",
  #     "matched"    => true|false,
  #     "fields"     => { "description" => ..., "pubdate" => ..., ... },  # only entries where value differs from current
  #     "identifiers"=> [ { "kind" => "...", "value" => "..." }, ... ],   # only ones not already present
  #     "cover"      => { "url" => ..., "width" => ..., "height" => ... } # only if different from existing
  #   }
  def build_proposal
    return base_proposal(matched: false) unless HardcoverClient.available? && @book.isbn.present?

    client = HardcoverClient.new
    edition = client.find_edition_by_isbn(@book.isbn)
    return base_proposal(matched: false) unless edition

    book_data = edition["book"] || {}

    # Search for sibling book records (different ISBNs of the same title) so
    # we can harvest cover candidates from them too. The ISBN-matched book
    # is sometimes a thumbnail-only "pending" record while the canonical
    # title-matched record has the publisher's full cover.
    #
    # Filter search hits to ones whose title actually matches our book —
    # Typesense returns fuzzy matches and will include other books by the
    # same author. Without this filter we'd happily pull a higher-res cover
    # from the wrong book.
    raw_hits = client.search_books(search_query_string)
    search_hits = matching_search_hits(raw_hits)
    Rails.logger.info("BookEnricher: book ##{@book.id} title-matched #{search_hits.size} of #{raw_hits.size} search hits")

    # Side effect: opportunistically stamp Hardcover slugs onto our local
    # Author and Series records when we find them. These aren't user-facing
    # review data, they're stable infrastructure handles (used to render
    # "View on Hardcover" links and, later, to live-fetch other works by
    # the same author/series).
    stamp_hardcover_slugs(book_data)

    fields = {}
    fields["description"] = book_data["description"] if differs?(@book.description, book_data["description"])
    fields["headline"]    = book_data["headline"]    if book_data["headline"].present?
    fields["rating"]      = book_data["rating"]      if book_data["rating"].present?
    fields["subtitle"]    = book_data["subtitle"]    if book_data["subtitle"].present?
    fields["pubdate"]     = book_data["release_date"] || edition["release_date"] if pubdate_differs?(edition, book_data)
    fields["publisher_name"] = edition.dig("publisher", "name") if edition.dig("publisher", "name").present? && @book.publisher&.name != edition.dig("publisher", "name")

    {
      "source"      => "hardcover",
      "matched"     => true,
      "fields"      => fields,
      "identifiers" => proposed_identifiers(edition),
      "cover"       => proposed_cover(edition, book_data, search_hits)
    }
  end

  # Trailing academic / generational honorifics — strip these before passing
  # to Hardcover's Typesense search. The search tokenizes the query and
  # requires non-trivial tokens to match book fields, so "PhD" would
  # exclude any book record whose author isn't tagged with PhD.
  HONORIFIC_TRAILING = /\s+(Ph\.?D\.?|M\.?D\.?|D\.?D\.?S\.?|Esq\.?|Jr\.?|Sr\.?|II|III|IV)\.?\s*\z/i

  def search_query_string
    cleaned_author = clean_author_name(@book.authors.first&.name)
    [ @book.title, cleaned_author ].compact.map(&:to_s).map(&:strip).reject(&:empty?).join(" ")
  end

  def clean_author_name(name)
    name.to_s.strip.gsub(HONORIFIC_TRAILING, "").gsub(/\s+/, " ").strip
  end

  # Normalize for *matching* — lowercase, drop dots, collapse whitespace,
  # and merge consecutive single-letter tokens into one. This way
  # "James S.A. Corey", "James S. A. Corey", and "James S A Corey" all
  # hash to "james sa corey" and the stamp_author_slugs lookup finds
  # the local author regardless of which spacing the upstream uses.
  def normalized_author_name(name)
    cleaned = clean_author_name(name).downcase.tr(".", " ").gsub(/\s+/, " ").strip
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

  # Bidirectional substring match: keep a hit if its title (or any of its
  # alternative_titles) either contains the local book's title or is
  # contained by it. Catches the "local says Accelerate / Hardcover has
  # Accelerate: Building..." case and the reverse, while dropping
  # same-author-different-book matches like "My Favourite Mistake" when
  # we asked for "Again, Rachel".
  def matching_search_hits(hits)
    return [] if hits.blank? || @book.title.blank?
    needle = @book.title.to_s.downcase.strip
    return [] if needle.empty?

    hits.select do |hit|
      titles = [ hit["title"], *Array(hit["alternative_titles"]) ].compact
      titles.any? do |t|
        normalized = t.to_s.downcase.strip
        normalized.present? && (normalized.include?(needle) || needle.include?(normalized))
      end
    end
  end

  # Match Hardcover's authors/series back to our local records by cleaned
  # name (case-insensitive) and stamp the slug if we don't already have
  # one. Idempotent — re-running an enrichment doesn't overwrite existing
  # slugs.
  def stamp_hardcover_slugs(book_data)
    return unless book_data.is_a?(Hash)
    stamp_author_slugs(book_data["contributions"])
    stamp_series_slug(book_data["book_series"])
  end

  def stamp_author_slugs(contributions)
    return unless contributions.is_a?(Array)

    local_by_normalized = @book.authors.index_by { |a| normalized_author_name(a.name) }

    contributions.each do |contribution|
      hc_name = contribution.dig("author", "name")
      hc_slug = contribution.dig("author", "slug")
      next if hc_name.blank? || hc_slug.blank?

      local = local_by_normalized[normalized_author_name(hc_name)]
      next unless local
      next if local.hardcover_slug.present?
      local.update!(hardcover_slug: hc_slug)
    end
  end

  def stamp_series_slug(book_series)
    return unless book_series.is_a?(Array) && @book.series.present?

    hc_series = book_series.map { |bs| bs["series"] }.compact.find { |s| s["name"].to_s.casecmp(@book.series.name).zero? }
    return unless hc_series && hc_series["slug"].present?
    return if @book.series.hardcover_slug.present?
    @book.series.update!(hardcover_slug: hc_series["slug"])
  end

  private

  def base_proposal(matched:)
    { "source" => "hardcover", "matched" => matched, "fields" => {}, "identifiers" => [], "cover" => nil }
  end

  def differs?(current, proposed)
    proposed.present? && current.to_s.strip != proposed.to_s.strip
  end

  def pubdate_differs?(edition, book_data)
    proposed = book_data["release_date"].presence || edition["release_date"].presence
    return false unless proposed
    @book.pubdate.blank? || @book.pubdate.to_date.to_s != proposed.to_s
  end

  def proposed_identifiers(edition)
    candidates = []
    candidates << { "kind" => "hardcover_edition", "value" => edition["id"].to_s } if edition["id"]
    candidates << { "kind" => "hardcover_book",    "value" => edition.dig("book", "id").to_s } if edition.dig("book", "id")
    candidates << { "kind" => "isbn13",            "value" => edition["isbn_13"] } if edition["isbn_13"].present?
    candidates << { "kind" => "isbn10",            "value" => edition["isbn_10"] } if edition["isbn_10"].present?
    candidates << { "kind" => "asin",              "value" => edition["asin"]    } if edition["asin"].present?

    existing = @book.book_identifiers.pluck(:kind, :value).to_set
    candidates.reject { |c| existing.include?([ c["kind"], c["value"] ]) }
  end

  # Pick the highest-resolution book-shaped cover Hardcover knows about,
  # across the matched edition, the matched book, every other edition under
  # that book, and book.canonical if Hardcover has deduped the record.
  #
  # "Book-shaped" means aspect ratio (height/width) between ~1.35 and ~1.75
  # — the range typical book covers fall in. Hardcover ships a lot of 500x500
  # square thumbnails alongside the real cover; without the ratio filter, raw
  # area picks the square over the proper 2:3 cover.
  BOOK_RATIO_MIN = 1.35
  BOOK_RATIO_MAX = 1.75

  def proposed_cover(edition, book_data, search_hits = [])
    candidates = []
    add_cover_candidate(candidates, edition["cached_image"])
    harvest_book_covers(candidates, book_data)
    harvest_book_covers(candidates, book_data["canonical"]) if book_data["canonical"].present?
    Array(search_hits).each { |hit| add_cover_candidate(candidates, hit["image"]) }

    candidates.uniq! { |c| c["url"] }

    book_shaped = candidates.select { |c| book_shaped_ratio?(c) }
    best = (book_shaped.presence || candidates).max_by { |c| c["width"].to_i * c["height"].to_i }

    log_candidates(candidates, best)
    return nil unless best && best["url"].present?
    best
  end

  def harvest_book_covers(candidates, book_data)
    return unless book_data.is_a?(Hash)
    add_cover_candidate(candidates, book_data["cached_image"])
    Array(book_data["images"]).each { |img| add_cover_candidate(candidates, img) }

    default_edition = book_data["default_cover_edition"]
    if default_edition.is_a?(Hash)
      add_cover_candidate(candidates, default_edition["cached_image"])
      Array(default_edition["images"]).each { |img| add_cover_candidate(candidates, img) }
    end

    Array(book_data["editions"]).each { |ed| add_cover_candidate(candidates, ed["cached_image"]) }
  end

  def book_shaped_ratio?(candidate)
    width  = candidate["width"].to_i
    height = candidate["height"].to_i
    return false if width.zero? || height.zero?
    ratio = height.to_f / width
    ratio.between?(BOOK_RATIO_MIN, BOOK_RATIO_MAX)
  end

  def add_cover_candidate(candidates, raw)
    return if raw.nil? || (raw.is_a?(Hash) && raw.empty?)
    url = unwrap_resize(raw.is_a?(Hash) ? raw["url"] : raw)
    return if url.blank?

    candidates << {
      "url"    => url,
      "width"  => raw.is_a?(Hash) ? raw["width"]  : nil,
      "height" => raw.is_a?(Hash) ? raw["height"] : nil
    }
  end

  def log_candidates(candidates, best)
    summary = candidates.map { |c| "#{c['width']}x#{c['height']}" }.join(", ")
    chosen  = best ? "#{best['width']}x#{best['height']} (#{best['url']})" : "none"
    Rails.logger.info("BookEnricher: book ##{@book.id} cover candidates=[#{summary}], chosen=#{chosen}")
  end

  # Hardcover's cached_image is typically the direct asset URL, but the website
  # version sometimes goes through production-img.hardcover.app/enlarge?url=...
  # Strip the proxy if present so we end up with the publisher's original.
  def unwrap_resize(url)
    return nil if url.blank?
    parsed = URI.parse(url)
    if parsed.host == HARDCOVER_RESIZE_HOST
      inner = CGI.parse(parsed.query.to_s)["url"]&.first
      return inner if inner.present?
    end
    url
  rescue URI::InvalidURIError
    nil
  end
end
