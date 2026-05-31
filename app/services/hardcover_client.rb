require "net/http"
require "uri"
require "json"

# Thin wrapper around Hardcover's GraphQL API.
#
# Per the "external deps degrade gracefully" rule: every method returns
# nil if HARDCOVER_APP_API_TOKEN is unset, the HTTP call fails, or the
# response is unusable. Callers should treat absence of data as "we
# don't have an enrichment to apply" and move on, not as an error.
#
# Rate limit per Hardcover docs: 60 req/min. Queries time out at 30s.
class HardcoverClient
  ENDPOINT = "https://api.hardcover.app/v1/graphql".freeze
  TIMEOUT_SECONDS = 30

  # The full book selection set that BookEnricher consumes. Shared by
  # both find_edition_by_isbn (nested under edition.book) and
  # find_book_by_id (top level) so the two paths produce identical
  # downstream shapes.
  BOOK_PAYLOAD_GQL = <<~GQL.freeze
    id
    title
    subtitle
    slug
    headline
    description
    rating
    pages
    release_date
    literary_type_id
    cached_image
    images { id url width height }
    default_cover_edition {
      id
      cached_image
      images { id url width height }
    }
    editions(limit: 30) {
      id
      cached_image
    }
    canonical {
      id
      cached_image
      images { id url width height }
      default_cover_edition {
        id
        cached_image
        images { id url width height }
      }
      editions(limit: 30) {
        id
        cached_image
      }
    }
    contributions {
      contribution
      author { id name slug }
    }
    book_series {
      position
      series { id name slug }
    }
  GQL

  def self.available?
    ENV["HARDCOVER_APP_API_TOKEN"].present?
  end

  def initialize(token: ENV["HARDCOVER_APP_API_TOKEN"])
    @token = token
  end

  # Fetch books linked to a given author slug via the contributions
  # relationship. Each returned hash has at minimum: id, title, slug,
  # cached_image. Used for the "more by this author" live-fetch on
  # author show pages.
  def books_by_author_slug(slug, limit: 50)
    return [] unless @token.present? && slug.present?

    query = <<~GQL
      query AuthorBooks($slug: String!, $limit: Int!) {
        authors(where: { slug: { _eq: $slug } }, limit: 1) {
          id
          name
          slug
          contributions(limit: $limit) {
            book {
              id
              title
              slug
              cached_image
            }
          }
        }
      }
    GQL

    response = post(query: query, variables: { slug: slug, limit: limit })
    return [] unless response

    contributions = Array(response.dig("data", "authors", 0, "contributions"))
    books = contributions.map { |c| c["book"] }.compact.uniq { |b| b["id"] }
    Rails.logger.info("HardcoverClient: books_by_author_slug(#{slug.inspect}) returned #{books.size} book(s)")
    books
  end

  # Fetch books in a given series slug, ordered by series position.
  def books_in_series_slug(slug, limit: 50)
    return [] unless @token.present? && slug.present?

    query = <<~GQL
      query SeriesBooks($slug: String!, $limit: Int!) {
        series(where: { slug: { _eq: $slug } }, limit: 1) {
          id
          name
          slug
          book_series(order_by: { position: asc }, limit: $limit) {
            position
            book {
              id
              title
              slug
              cached_image
            }
          }
        }
      }
    GQL

    response = post(query: query, variables: { slug: slug, limit: limit })
    return [] unless response

    book_series = Array(response.dig("data", "series", 0, "book_series"))
    books = book_series.map { |bs| bs["book"] }.compact.uniq { |b| b["id"] }
    Rails.logger.info("HardcoverClient: books_in_series_slug(#{slug.inspect}) returned #{books.size} book(s)")
    books
  end

  # Hardcover's Typesense-backed search. Required for finding sibling book
  # records (e.g. different ISBNs of the same title) — the regular where
  # clauses don't support _ilike on this server, so naive title matching
  # is exact-only. The search hits are full Typesense documents with the
  # cover `image` already populated.
  def search_books(query, per_page: 10)
    return [] unless @token.present? && query.present?

    gql = <<~GQL
      query SearchBooks($query: String!, $per_page: Int!) {
        search(query: $query, query_type: "Book", per_page: $per_page) {
          results
        }
      }
    GQL

    response = post(query: gql, variables: { query: query, per_page: per_page })
    return [] unless response

    hits = Array(response.dig("data", "search", "results", "hits"))
    Rails.logger.info("HardcoverClient: search returned #{hits.size} hit(s) for #{query.inspect}")
    hits.map { |hit| hit["document"] }.compact
  end

  # Look up an edition by ISBN-13 (or ISBN-10 — the editions table indexes
  # both columns). Returns the first matching edition hash, or nil.
  def find_edition_by_isbn(isbn)
    return nil unless @token.present? && isbn.present?

    normalized = isbn.gsub(/[^0-9Xx]/, "")
    query = <<~GQL
      query EditionByIsbn($isbn: String!) {
        editions(
          where: { _or: [ { isbn_13: { _eq: $isbn } }, { isbn_10: { _eq: $isbn } } ] }
          limit: 1
        ) {
          id
          title
          subtitle
          isbn_13
          isbn_10
          asin
          pages
          release_date
          cached_image
          edition_format
          publisher { name }
          language { language }
          book { #{BOOK_PAYLOAD_GQL} }
        }
      }
    GQL

    response = post(query: query, variables: { isbn: normalized })
    return nil unless response

    edition = response.dig("data", "editions", 0)
    if edition.nil?
      Rails.logger.info("HardcoverClient: no edition found for ISBN #{normalized}")
    else
      Rails.logger.info("HardcoverClient: matched edition #{edition['id']} (book #{edition.dig('book', 'id')}) for ISBN #{normalized}")
    end
    edition
  end

  # ISBN-less fallback. Search by title (+ author when known), keep
  # hits whose title is bidirectionally contained in the local title,
  # take the first, and fetch the full book payload by id. Wraps the
  # result in the same edition-shaped hash that find_edition_by_isbn
  # returns so BookEnricher's downstream logic doesn't need to branch
  # on which path produced the data. ISBN/ASIN fields are left nil —
  # we don't have them, by definition of this path.
  def find_book_by_search(title:, author: nil)
    return nil unless @token.present? && title.to_s.strip.present?

    query_string = [ title, author ].compact.map(&:to_s).map(&:strip).reject(&:empty?).join(" ")
    hits = search_books(query_string, per_page: 10)
    return nil if hits.empty?

    matched = first_title_matching_hit(hits, title)
    if matched.nil?
      Rails.logger.info("HardcoverClient: no title-matching hit for #{title.inspect} (#{hits.size} raw hits)")
      return nil
    end

    book_id = matched["id"]
    return nil if book_id.blank?

    book = find_book_by_id(book_id)
    return nil unless book

    default_edition = book["default_cover_edition"].is_a?(Hash) ? book["default_cover_edition"] : nil
    {
      "id"           => default_edition&.dig("id"),
      "isbn_13"      => nil,
      "isbn_10"      => nil,
      "asin"         => nil,
      "release_date" => book["release_date"],
      "cached_image" => default_edition&.dig("cached_image") || book["cached_image"],
      "publisher"    => nil,
      "book"         => book
    }
  end

  # Fetch a full book payload by Hardcover book id. Returns the same
  # shape that edition.book has from find_edition_by_isbn.
  def find_book_by_id(book_id)
    return nil unless @token.present? && book_id.present?

    query = <<~GQL
      query BookById($book_id: Int!) {
        books(where: { id: { _eq: $book_id } }, limit: 1) {
          #{BOOK_PAYLOAD_GQL}
        }
      }
    GQL

    response = post(query: query, variables: { book_id: book_id.to_i })
    return nil unless response

    book = response.dig("data", "books", 0)
    if book.nil?
      Rails.logger.info("HardcoverClient: no book found for id #{book_id}")
    else
      Rails.logger.info("HardcoverClient: fetched book #{book['id']} (#{book['title']}) by id")
    end
    book
  end

  private

  # Bidirectional title containment, matching BookEnricher.matching_search_hits.
  # Returns the first hit whose title (or any alternative title) contains the
  # needle or is contained by it.
  def first_title_matching_hit(hits, needle_title)
    needle = needle_title.to_s.downcase.strip
    return nil if needle.empty?

    hits.find do |hit|
      titles = [ hit["title"], *Array(hit["alternative_titles"]) ].compact
      titles.any? do |t|
        normalized = t.to_s.downcase.strip
        normalized.present? && (normalized.include?(needle) || needle.include?(normalized))
      end
    end
  end

  def post(query:, variables: {})
    uri = URI(ENDPOINT)
    body = { query: query, variables: variables }.to_json

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{@token}"
    request.body = body

    response = Net::HTTP.start(uri.hostname, uri.port,
                               use_ssl: true,
                               open_timeout: 5,
                               read_timeout: TIMEOUT_SECONDS) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("HardcoverClient: HTTP #{response.code} from Hardcover — #{response.body.to_s[0, 500]}")
      return nil
    end

    parsed = JSON.parse(response.body)
    if (errors = parsed["errors"]).present?
      Rails.logger.warn("HardcoverClient: GraphQL errors — #{errors.inspect}")
      return nil
    end

    parsed
  rescue => e
    Rails.logger.warn("HardcoverClient: request failed — #{e.class}: #{e.message}")
    nil
  end
end
