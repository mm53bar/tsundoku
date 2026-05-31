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

    # Per-card quick-add-to-shelf picker needs both the user's shelves
    # (constant across cards) and the set of shelves each book is
    # already on (per card). Preload both so the index render doesn't
    # do a query per card.
    if current_user
      @user_shelves = current_user.shelves.by_name.to_a
      memberships   = ShelfEntry.joins(:shelf)
                                .where(book_id: @books.map(&:id), shelves: { user_id: current_user.id })
                                .pluck(:book_id, :shelf_id)
      @shelf_member_ids_by_book = memberships.group_by(&:first).transform_values { |pairs| pairs.map(&:last).to_set }
      @shelf_member_ids_by_book.default = Set.new
    else
      @user_shelves = []
      @shelf_member_ids_by_book = {}
    end

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
