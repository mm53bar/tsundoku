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

    edition = HardcoverClient.new.find_edition_by_isbn(@book.isbn)
    return base_proposal(matched: false) unless edition

    book_data = edition["book"] || {}

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
      "cover"       => proposed_cover(edition, book_data)
    }
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

  # Prefer book.default_cover_edition.images[] (Hardcover's curated cover),
  # picking the highest-resolution variant. Falls back to default_cover_edition.cached_image,
  # then book.cached_image, then edition.cached_image. Skip if the URL matches
  # what we already have stored.
  def proposed_cover(edition, book_data)
    default_edition = book_data["default_cover_edition"] || {}

    candidates = []
    Array(default_edition["images"]).each do |img|
      url = unwrap_resize(img["url"])
      candidates << { "url" => url, "width" => img["width"], "height" => img["height"] } if url
    end
    [ default_edition["cached_image"], book_data["cached_image"], edition["cached_image"] ].each do |raw|
      next unless raw
      url = unwrap_resize(raw.is_a?(Hash) ? raw["url"] : raw)
      candidates << { "url" => url, "width" => raw.is_a?(Hash) ? raw["width"] : nil, "height" => raw.is_a?(Hash) ? raw["height"] : nil } if url
    end

    best = candidates.max_by { |c| (c["width"].to_i * c["height"].to_i) }
    return nil unless best && best["url"].present?

    best
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
