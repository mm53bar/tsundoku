class LibraryController < ApplicationController
  before_action :require_admin!, only: :import

  ALLOWED_SORTS = %w[title recently_added].freeze

  def index
    @sort = ALLOWED_SORTS.include?(params[:sort]) ? params[:sort] : "title"
    scope = (@sort == "recently_added") ? Book.recently_added : Book.by_title
    @books = scope.includes(:authors, :series)
    @calibre_db_available = CalibreImporter.available?
    @calibre_import_in_progress = Task.active.where(kind: "calibre_import").exists?
  end

  def import
    if Task.active.where(kind: "calibre_import").exists?
      redirect_to root_path, alert: "An import is already running."
      return
    end

    task = Task.create!(kind: "calibre_import", status: :queued)
    CalibreImportJob.perform_later(task.id)
    redirect_to root_path, notice: "Import started — progress will appear in the banner above."
  end

  private

  def require_admin!
    return if current_user&.admin?
    redirect_to root_path, alert: "Admins only."
  end
end
