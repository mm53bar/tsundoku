class BooksController < ApplicationController
  before_action :set_book
  before_action :require_admin!, only: [ :enrich, :edit, :update ]

  def show
  end

  def cover
    path = safe_cover_path
    return head :not_found unless path

    send_file path, type: cover_mime_type(path), disposition: "inline"
  end

  def edit
    @task     = consume_proposal_task(params[:from_task])
    @proposal = @task&.result.presence || {}
  end

  def update
    @task     = Task.find_by(id: params[:task_id], subject: @book, kind: "metadata_enrichment", status: :succeeded) if params[:task_id].present?
    @proposal = @task&.result.presence || {}

    Book.transaction do
      apply_publisher
      apply_authors
      @book.update!(book_params)
      apply_accepted_identifiers
      apply_accepted_cover
    end

    redirect_to @book, notice: "Book updated."
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Save failed: #{e.message}"
    render :edit, status: :unprocessable_content
  end

  def enrich
    if Task.active.where(kind: "metadata_enrichment", subject: @book).exists?
      redirect_to @book, alert: "An enrichment is already running for this book."
      return
    end
    if Task.pending_review.where(kind: "metadata_enrichment", subject: @book).exists?
      pending = Task.pending_review.where(kind: "metadata_enrichment", subject: @book).order(:created_at).last
      redirect_to edit_book_path(@book, from_task: pending.id), notice: "Reviewing the existing enrichment proposal."
      return
    end

    task = Task.create!(kind: "metadata_enrichment", subject: @book, status: :queued)
    EnrichBookJob.perform_later(task.id)
    redirect_to @book, notice: "Enrichment started — review will appear in the banner above."
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end

  def require_admin!
    return if current_user&.admin?
    redirect_to @book, alert: "Admins only."
  end

  # Find the task, verify it belongs to this book, and mark it reviewed.
  # Viewing the edit form *is* the review — explicit per the project rule
  # ("just viewing them is enough to mark the enrichment as finished").
  def consume_proposal_task(task_id)
    return nil if task_id.blank?
    task = Task.find_by(id: task_id, subject: @book, kind: "metadata_enrichment", status: :succeeded)
    return nil unless task
    task.mark_reviewed! if task.reviewed_at.nil?
    task
  end

  def book_params
    params.require(:book).permit(:title, :sort_title, :description, :pubdate, :series_index)
  end

  def apply_publisher
    name = params.dig(:book, :publisher_name).to_s.strip
    return if name.blank?
    return if @book.publisher&.name == name
    publisher = Publisher.find_or_create_by!(name: name)
    @book.update!(publisher: publisher)
  end

  # Parse the comma-separated author_names field, reuse existing Author
  # records when names normalize to the same canonical form (so "James
  # S.A. Corey" and "James S. A. Corey" don't fragment into two records),
  # create new ones for unmatched names, then rebuild book_authors in the
  # order the user typed. Field absent → no change. Field present-but-
  # blank → clears all authors.
  def apply_authors
    text = params.dig(:book, :author_names_text)
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

  # Form submits an array of "kind|value" tokens for each accepted identifier.
  # We re-validate each one against the proposal to make sure the form can't
  # inject arbitrary kinds/values.
  def apply_accepted_identifiers
    tokens = Array(params[:accepted_identifiers])
    return if tokens.empty? || @proposal.blank?

    proposed = Array(@proposal["identifiers"]).map { |h| [ h["kind"], h["value"] ] }.to_set
    tokens.each do |token|
      kind, value = token.to_s.split("|", 2)
      next unless proposed.include?([ kind, value ])
      next if @book.book_identifiers.exists?(kind: kind, value: value)
      @book.book_identifiers.create!(kind: kind, value: value)
    end
  end

  # Cover URL comes from the task's proposal, never the form, so the user
  # can't trick us into fetching an arbitrary URL.
  def apply_accepted_cover
    return unless params[:accept_cover] == "1"
    cover = @proposal&.dig("cover")
    return unless cover && cover["url"].present?

    download_proposed_cover(cover["url"])
  end

  def download_proposed_cover(url)
    require "net/http"
    uri = URI(url)
    return unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.start(uri.hostname, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 5,
                               read_timeout: 30) do |http|
      http.get(uri.request_uri)
    end
    return unless response.is_a?(Net::HTTPSuccess)

    FileUtils.mkdir_p(Rails.root.join("storage", "covers"))
    relative = "covers/book_#{@book.id}.jpg"
    File.binwrite(Rails.root.join("storage", relative), response.body)
    @book.update!(enriched_cover_path: relative, last_enriched_at: Time.current)
  rescue => e
    Rails.logger.warn("BooksController: cover download failed for book #{@book.id} — #{e.class}: #{e.message}")
  end

  # Resolve a cover path and refuse anything that tries to escape its
  # expected root directory. Enriched covers live under Rails.root/storage,
  # Calibre covers live under the library bind-mount.
  def safe_cover_path
    if @book.enriched_cover_path.present?
      enriched = safe_path_under(Rails.root.join("storage"), @book.enriched_cover_path)
      return enriched if enriched
    end

    return nil if @book.cover_path.blank?
    safe_path_under(Rails.configuration.x.library_path, @book.cover_path)
  end

  def safe_path_under(root, relative)
    base = Pathname.new(root).expand_path
    candidate = base.join(relative).expand_path
    return nil unless candidate.to_s.start_with?(base.to_s + File::SEPARATOR)
    return nil unless candidate.file?
    candidate.to_s
  end

  def cover_mime_type(path)
    case File.extname(path).downcase
    when ".png"  then "image/png"
    when ".gif"  then "image/gif"
    when ".webp" then "image/webp"
    else              "image/jpeg"
    end
  end
end
