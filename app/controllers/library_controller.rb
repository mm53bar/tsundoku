class LibraryController < ApplicationController
  ALLOWED_SORTS   = %w[title recently_added].freeze
  ALLOWED_FILTERS = %w[on_kobo].freeze

  def index
    @sort   = ALLOWED_SORTS.include?(params[:sort])     ? params[:sort]   : "title"
    @filter = ALLOWED_FILTERS.include?(params[:filter]) ? params[:filter] : nil

    scope = (@sort == "recently_added") ? Book.recently_added : Book.by_title
    if @filter == "on_kobo" && current_user
      scope = scope.where(id: current_user.on_kobo_books.select(:id))
    end
    @books = scope.includes(:authors, :series, :lists)

    # Per-user readings keyed by book_id so the card partial can render
    # a progress bar without an N+1 lookup.
    @readings_by_book_id = if current_user
      current_user.readings.where(book_id: @books.map(&:id)).index_by(&:book_id)
    else
      {}
    end

    @user_shelves, @shelf_member_ids_by_book = preload_shelf_membership_for(@books)
    @calibre_db_available = CalibreImporter.available?
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
end
