class ToolsController < ApplicationController
  # Ongoing maintenance: re-sync Calibre, manual ingest scan, KEPUB
  # tools. The actions themselves live in their existing controllers
  # (LibraryController#import, IngestController, the kepub:* rake
  # tasks); this page is just a discoverable surface.
  def show
    @calibre_db_available       = CalibreImporter.available?
    @calibre_import_in_progress = Task.active.where(kind: "calibre_import").exists?
    @pending_ingest_count       = pending_ingest_count
  end

  private

  def pending_ingest_count
    root = Rails.configuration.x.ingest_path
    return 0 if root.blank? || !Dir.exist?(root)
    Dir.glob(File.join(root, "**/*.epub")).count
  end
end
