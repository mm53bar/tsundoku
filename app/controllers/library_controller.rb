class LibraryController < ApplicationController
  before_action :require_admin!, only: :import

  def index
    @books = Book.by_title.includes(:authors, :series)
    @calibre_db_available = CalibreImporter.available?
  end

  def import
    stats = CalibreImporter.new.import!
    redirect_to root_path, notice: import_summary(stats)
  rescue CalibreImporter::MissingDatabase => e
    redirect_to root_path, alert: e.message
  rescue => e
    Rails.logger.error("Calibre import failed: #{e.class}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    redirect_to root_path, alert: "Import failed: #{e.message}"
  end

  private

  def require_admin!
    return if current_user&.admin?
    redirect_to root_path, alert: "Admins only."
  end

  def import_summary(stats)
    parts = []
    parts << "#{stats.books_created} new, #{stats.books_updated} updated (#{stats.books_seen} total)"
    parts << "#{stats.authors_created} new authors" if stats.authors_created.positive?
    parts << "#{stats.series_created} new series" if stats.series_created.positive?
    parts << "#{stats.tags_created} new tags" if stats.tags_created.positive?
    "Imported from Calibre: #{parts.join(' · ')}."
  end
end
