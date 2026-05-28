class IngestController < ApplicationController
  before_action :require_admin!

  def index
    @ingest_path = Rails.configuration.x.ingest_path
    @pending_files = pending_files
    @recent_tasks = Task.where(kind: "book_ingest").order(created_at: :desc).limit(20)
  end

  # POST: walk INGEST_PATH for .epub files and create a book_ingest task +
  # job per file. The job moves the file, so re-running scan won't pick up
  # already-processed files (because they're gone from /ingest).
  def scan
    pending = pending_files
    if pending.empty?
      redirect_to ingest_path_route, alert: "No EPUB files found in #{Rails.configuration.x.ingest_path}."
      return
    end

    queued = 0
    pending.each do |path|
      task = Task.create!(kind: "book_ingest", status: :queued, result: { "file_path" => path })
      IngestFileJob.perform_later(task.id, path)
      queued += 1
    end

    redirect_to ingest_path_route, notice: "Queued #{pluralize(queued, "file")} for ingest. Watch the banner above for progress."
  end

  private

  def require_admin!
    return if current_user&.admin?
    redirect_to root_path, alert: "Admins only."
  end

  def pending_files
    root = Rails.configuration.x.ingest_path
    return [] if root.blank? || !Dir.exist?(root)
    Dir.glob(File.join(root, "**/*.epub")).sort
  end

  # The controller path "ingest" collides with the Rails URL-helper method
  # `ingest_path` we'd otherwise want to use, so route helpers expose this
  # as `ingest_index_path`. Aliasing for readability.
  def ingest_path_route
    ingest_index_path
  end
end
