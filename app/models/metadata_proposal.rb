# A pending proposal of book metadata changes — sourced from an
# enrichment Task and refined by the user's accept/reject decisions
# on the edit form. Knows how to apply itself to a Book within a
# transaction.
#
# Per docs/architecture-principles.md §2: this is a noun, not a
# verb. The concept is "the proposed-and-chosen state of a book"
# living between the enrichment job and the persisted Book record.
# BooksController#update used to own the apply logic (apply_publisher,
# apply_authors, apply_accepted_identifiers, apply_accepted_cover,
# download_proposed_cover, ~95 lines of controller-private workflow);
# that workflow lives here now, leaving the controller to do HTTP.
class MetadataProposal
  # The user's choices on the edit form, after strong-parameter
  # filtering. The controller builds this struct and passes it in so
  # the PORO doesn't need to know about ActionController::Parameters.
  Choices = Struct.new(
    :book_attributes,       # ActionController::Parameters (permitted)
    :publisher_name,        # String (raw; we strip and dedupe)
    :author_names_text,     # String or nil (nil = leave authors alone)
    :accepted_identifier_tokens, # Array of "kind|value" strings
    :accept_cover,          # Boolean — true means fetch the proposed cover URL
    keyword_init: true
  )

  def initialize(book:, task:, choices:)
    @book    = book
    @task    = task
    @choices = choices
  end

  # The raw proposal hash from the task's result — what the enrichment
  # job suggested. Empty when there's no task (a manual edit with no
  # enrichment proposal in play).
  def proposed
    @task&.result.presence || {}
  end

  attr_reader :task

  # Apply everything in one transaction. Raises ActiveRecord::RecordInvalid
  # if validations fail (the controller catches it and re-renders edit).
  def apply!
    Book.transaction do
      apply_publisher
      apply_authors
      @book.update!(@choices.book_attributes)
      apply_accepted_identifiers
      apply_accepted_cover
    end
  end

  private

  def apply_publisher
    name = @choices.publisher_name.to_s.strip
    return if name.blank?
    return if @book.publisher&.name == name
    @book.update!(publisher: Publisher.find_or_create_by!(name: name))
  end

  # Parse the comma-separated author_names field, reuse existing Author
  # records when names normalize to the same canonical form (so "James
  # S.A. Corey" and "James S. A. Corey" don't fragment into two records),
  # create new ones for unmatched names, then rebuild book_authors in the
  # order the user typed. Field absent → no change. Field present-but-
  # blank → clears all authors.
  def apply_authors
    text = @choices.author_names_text
    return if text.nil?

    names = text.to_s.split(",").map(&:strip).reject(&:empty?)
    normalized_to_author = Author.all.index_by { |a| Author.normalize_name(a.name) }

    target_authors = names.map do |name|
      key = Author.normalize_name(name)
      existing = normalized_to_author[key]
      if existing
        existing
      else
        Author.create!(name: name).tap { |a| normalized_to_author[key] = a }
      end
    end

    @book.book_authors.destroy_all
    target_authors.each_with_index do |author, i|
      @book.book_authors.create!(author: author, position: i)
    end
  end

  # The form submits an array of "kind|value" tokens for each accepted
  # identifier. Re-validate each one against the proposal so the form
  # can't inject arbitrary kinds/values that weren't proposed.
  def apply_accepted_identifiers
    tokens = Array(@choices.accepted_identifier_tokens)
    return if tokens.empty? || proposed.blank?

    proposed_set = Array(proposed["identifiers"]).map { |h| [ h["kind"], h["value"] ] }.to_set
    tokens.each do |token|
      kind, value = token.to_s.split("|", 2)
      next unless proposed_set.include?([ kind, value ])
      next if @book.book_identifiers.exists?(kind: kind, value: value)
      @book.book_identifiers.create!(kind: kind, value: value)
    end
  end

  # Cover URL comes from the task's proposal, never the form — the
  # form just opts in via accept_cover. That way the user can't trick
  # us into fetching an arbitrary URL by editing the radio button's
  # value.
  def apply_accepted_cover
    return unless @choices.accept_cover
    cover = proposed["cover"]
    return unless cover && cover["url"].present?
    download_proposed_cover(cover["url"])
  end

  def download_proposed_cover(url)
    require "net/http"
    uri = URI(url)
    return unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.start(uri.hostname, uri.port,
                               use_ssl:      uri.scheme == "https",
                               open_timeout: 5,
                               read_timeout: 30) do |http|
      http.get(uri.request_uri)
    end
    return unless response.is_a?(Net::HTTPSuccess)

    FileUtils.mkdir_p(Rails.root.join("storage", "covers"))
    relative = "covers/book_#{@book.id}.jpg"
    File.binwrite(Rails.root.join("storage", relative), response.body)
    @book.update!(enriched_cover_path: relative, last_enriched_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("MetadataProposal: cover download failed for book #{@book.id} — #{e.class}: #{e.message}")
  end
end
