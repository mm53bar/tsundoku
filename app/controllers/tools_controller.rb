class ToolsController < ApplicationController
  # Ongoing maintenance: re-sync Calibre, manual ingest scan, KEPUB
  # tools. The actions themselves live in their existing controllers
  # (LibraryController#import, IngestController, the kepub:* rake
  # tasks); this page is just a discoverable surface.
  def show
    @calibre_db_available       = CalibreImporter.available?
    @calibre_import_in_progress = Task.active.where(kind: "calibre_import").exists?
    @author_cleanup_in_progress = Task.active.where(kind: "author_cleanup").exists?
    @pending_ingest_count       = pending_ingest_count
  end

  def cleanup_authors
    if Task.active.where(kind: "author_cleanup").exists?
      redirect_to tools_path, alert: "An author cleanup is already running."
      return
    end

    task = Task.create!(kind: "author_cleanup", status: :queued)
    CleanupAuthorsJob.perform_later(task.id)
    redirect_to tools_path, notice: "Author cleanup started — progress will appear in the task tray."
  end

  private

  def pending_ingest_count
    root = Rails.configuration.x.ingest_path
    return 0 if root.blank? || !Dir.exist?(root)
    Dir.glob(File.join(root, "**/*.epub")).count
  end
end
