class BooksController < ApplicationController
  before_action :set_book

  def show
    @reading = current_user.readings.find_by(book: @book) if signed_in?
  end

  def cover
    assets = @book.assets
    return head :not_found unless assets.cover_available?

    send_file assets.cover_full_path,
              type:        assets.cover_mime_type,
              disposition: "inline"
  end

  def download
    assets = @book.assets
    return head :not_found unless assets.epub_downloadable?

    send_file assets.epub_full_path,
              type:        "application/epub+zip",
              disposition: "attachment",
              filename:    "#{@book.title}.epub"
  end

  def edit
    @task     = consume_proposal_task(params[:from_task])
    @proposal = @task&.result.presence || {}
  end

  def update
    @task     = find_succeeded_task(params[:task_id])
    @proposal = @task&.result.presence || {}

    MetadataProposal.new(book: @book, task: @task, choices: extract_choices).apply!
    redirect_to @book, notice: "Book updated."
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Save failed: #{e.message}"
    render :edit, status: :unprocessable_content
  end

  def destroy
    title = @book.title
    # Cascades to readings/shelf_entries/book_authors/book_tags/book_identifiers
    # via :destroy; list_entries via :nullify; kobo_synced_books via :nullify
    # (those rows survive to tombstone on the next sync). Files come off
    # disk in Book's before_destroy callback.
    @book.destroy
    redirect_to root_path, notice: "Deleted \"#{title}\"."
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

  # Edit's task-lookup and update's task-lookup differ only in the param
  # name (`from_task` vs `task_id`). consume_proposal_task uses the
  # former and marks the task reviewed (viewing the form *is* the
  # review per the project rule); find_succeeded_task uses the latter
  # without marking, since update's task came from the hidden field on
  # the form and was already consumed at edit time.
  def consume_proposal_task(task_id)
    task = find_succeeded_task(task_id)
    task.mark_reviewed! if task && task.reviewed_at.nil?
    task
  end

  def find_succeeded_task(task_id)
    return nil if task_id.blank?
    Task.find_by(id: task_id, subject: @book, kind: "metadata_enrichment", status: :succeeded)
  end

  # Pull the user's accept/reject decisions out of params into a plain
  # struct so the MetadataProposal PORO doesn't need to know about
  # ActionController::Parameters. book_attributes is the only piece
  # that needs strong-param filtering; the others are scalars or arrays
  # we re-validate inside the PORO.
  def extract_choices
    MetadataProposal::Choices.new(
      book_attributes:            params.require(:book).permit(:title, :sort_title, :description, :pubdate, :series_index),
      publisher_name:             params.dig(:book, :publisher_name),
      author_names_text:          params.dig(:book, :author_names_text),
      accepted_identifier_tokens: Array(params[:accepted_identifiers]),
      accept_cover:               params[:accept_cover] == "1"
    )
  end
end
