class ListEntry < ApplicationRecord
  belongs_to :list, inverse_of: :list_entries
  belongs_to :book, optional: true

  RESOLUTION_STATUSES = %w[resolved ambiguous unresolved].freeze

  # Resolution data that survives a re-import for an unchanged entry.
  RESOLUTION_ATTRIBUTES = %w[
    hardcover_book_id resolved_title resolved_author release_year cover_url
    resolution_status resolution_candidates
  ].freeze

  validates :title, presence: true
  validates :resolution_status, inclusion: { in: RESOLUTION_STATUSES }, allow_nil: true
  validate :cover_url_must_be_http

  scope :pending_resolution, -> { where(resolution_status: nil) }

  def matched?
    book_id.present?
  end

  def resolved?
    resolution_status == "resolved"
  end

  def ambiguous?
    resolution_status == "ambiguous"
  end

  def display_title
    resolved_title.presence || title
  end

  def display_author
    resolved_author.presence || author_name.presence || book&.author_names
  end

  def candidates
    Array(resolution_candidates).map { |c| HardcoverHit.from_candidate(c) }
  end

  def resolve_with!(hits)
    pick = ClearWinner.new(hits, title: title, author: author_name)

    if (hit = pick.hit)
      choose!(hit)
    else
      suggestions = pick.suggestions
      update!(
        resolution_status: suggestions.any? ? "ambiguous" : "unresolved",
        resolution_candidates: suggestions.map(&:to_candidate).presence
      )
    end
  end

  def choose!(hit)
    update!(
      hardcover_book_id: hit.id,
      resolved_title: hit.title,
      resolved_author: hit.author,
      release_year: hit.release_year,
      cover_url: hit.cover_url,
      resolution_status: "resolved",
      resolution_candidates: nil
    )
    rematch!
  end

  def rematch!
    return if matched?

    book = BookMatcher.match(
      title: title, author: author_name, hardcover_book_id: hardcover_book_id,
      resolved_title: resolved_title, resolved_author: resolved_author
    )
    update!(book: book) if book
  end

  # Identity of a typed entry across re-imports. Order and resolution are
  # deliberately not part of it.
  def self.matching_key(title, author)
    [ title.to_s.downcase.strip, author.to_s.downcase.strip ].join("|")
  end

  def matching_key
    self.class.matching_key(title, author_name)
  end

  private

  def cover_url_must_be_http
    return if cover_url.blank?
    errors.add(:cover_url, "must be an http or https URL") unless URI.parse(cover_url).is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    errors.add(:cover_url, "is not a valid URL")
  end
end
