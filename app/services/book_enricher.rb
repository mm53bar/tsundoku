require "net/http"
require "uri"
require "cgi"

# Applies Hardcover metadata to a single Book.
#
# Conservative by default — only fills in *missing* descriptive fields,
# never overwrites what Calibre already populated. The one exception is
# the cover, which is replaced entirely if Hardcover has one (that's the
# primary user-facing reason to run enrichment). Identifiers from
# Hardcover are added alongside existing ones.
class BookEnricher
  HARDCOVER_RESIZE_HOST = "production-img.hardcover.app".freeze
  COVERS_DIR = Rails.root.join("storage", "covers").freeze

  Stats = Struct.new(
    :hardcover_matched, :fields_updated, :identifiers_added, :cover_replaced,
    keyword_init: true
  )

  attr_reader :book, :stats

  def initialize(book)
    @book = book
    @stats = Stats.new(hardcover_matched: false, fields_updated: 0, identifiers_added: 0, cover_replaced: false)
  end

  def enrich!
    return stats unless HardcoverClient.available?

    isbn = book.isbn
    unless isbn.present?
      Rails.logger.info("BookEnricher: book ##{book.id} has no ISBN, skipping Hardcover lookup")
      finalize!
      return stats
    end

    edition = HardcoverClient.new.find_edition_by_isbn(isbn)
    unless edition
      finalize!
      return stats
    end

    stats.hardcover_matched = true

    Book.transaction do
      apply_book_fields(edition)
      apply_identifiers(edition)
    end

    download_cover(edition)
    finalize!
    stats
  end

  private

  def apply_book_fields(edition)
    book_data = edition["book"] || {}
    updates = {}

    if book.description.blank?
      hc_description = edition["description"].presence || book_data["description"].presence
      updates[:description] = hc_description if hc_description
    end

    if book.pubdate.blank? && edition["release_date"].present?
      parsed = parse_date(edition["release_date"])
      updates[:pubdate] = parsed if parsed
    end

    stats.fields_updated = updates.size
    book.update!(updates) if updates.any?
  end

  def apply_identifiers(edition)
    candidates = []
    candidates << [ "hardcover_edition", edition["id"].to_s ] if edition["id"]
    candidates << [ "hardcover_book", edition.dig("book", "id").to_s ] if edition.dig("book", "id")
    candidates << [ "isbn13", edition["isbn_13"] ] if edition["isbn_13"].present?
    candidates << [ "isbn10", edition["isbn_10"] ] if edition["isbn_10"].present?
    candidates << [ "asin",   edition["asin"]    ] if edition["asin"].present?

    existing = book.book_identifiers.pluck(:kind, :value).to_set

    candidates.each do |(kind, value)|
      next if existing.include?([ kind, value ])
      book.book_identifiers.create!(kind: kind, value: value)
      stats.identifiers_added += 1
    end
  end

  def download_cover(edition)
    image_url = extract_cover_url(edition)
    return unless image_url

    FileUtils.mkdir_p(COVERS_DIR)
    relative_path = "covers/book_#{book.id}.jpg"
    full_path     = Rails.root.join("storage", relative_path)

    if fetch_image(image_url, full_path)
      book.update!(enriched_cover_path: relative_path)
      stats.cover_replaced = true
    end
  end

  # Hardcover's `cached_image` is sometimes a URL string, sometimes an object
  # like { "url" => "...", "width" => ..., "height" => ... }. Handle both,
  # and unwrap the resize-cdn so we get the publisher's full-resolution
  # original instead of the thumbnail.
  def extract_cover_url(edition)
    raw = edition["cached_image"] || edition.dig("book", "cached_image")
    url = raw.is_a?(Hash) ? raw["url"] : raw
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

  def fetch_image(url, dest)
    uri = URI(url)
    response = Net::HTTP.start(uri.hostname, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 5,
                               read_timeout: 30) do |http|
      http.get(uri.request_uri)
    end

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("BookEnricher: cover fetch HTTP #{response.code} for #{url}")
      return false
    end

    File.binwrite(dest, response.body)
    true
  rescue => e
    Rails.logger.warn("BookEnricher: cover fetch failed for #{url} — #{e.class}: #{e.message}")
    false
  end

  def finalize!
    book.update!(last_enriched_at: Time.current)
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
