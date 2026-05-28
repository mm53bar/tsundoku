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

  def self.available?
    ENV["HARDCOVER_APP_API_TOKEN"].present?
  end

  def initialize(token: ENV["HARDCOVER_APP_API_TOKEN"])
    @token = token
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
          book {
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
              author { name }
            }
            book_series {
              position
              series { name }
            }
          }
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

  private

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
