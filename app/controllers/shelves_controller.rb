class ShelvesController < ApplicationController
  before_action :set_shelf, only: [ :show, :edit, :update, :destroy, :remove_book ]

  def index
    @shelves = current_user.shelves.by_name.includes(:shelf_entries)
  end

  def show
    @books = @shelf.books.by_title.includes(:authors, :series, :lists)
    @user_shelves, @shelf_member_ids_by_book, @starred_shelf_id = preload_shelf_membership_for(@books)
  end

  def new
    @shelf = current_user.shelves.new
  end

  def create
    @shelf = current_user.shelves.new(shelf_params)
    if @shelf.save
      redirect_to @shelf, notice: "Created shelf '#{@shelf.name}'."
    else
      flash.now[:alert] = @shelf.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @shelf.update(shelf_params)
      respond_to do |format|
        format.turbo_stream # used by the inline sync_to_kobo switch on shelves#show
        format.html { redirect_to @shelf, notice: "Updated." }
      end
    else
      flash.now[:alert] = @shelf.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @shelf.destroy
    redirect_to shelves_path, notice: "Deleted '#{@shelf.name}'."
  end

  # DELETE /shelves/:id/books/:book_id
  # Used by the X button on shelves#show. Separate from the picker's
  # toggle endpoint (which returns turbo-stream for the picker UI) —
  # this one just removes and redirects back to the shelf.
  def remove_book
    book = Book.find(params[:book_id])
    @shelf.shelf_entries.where(book: book).destroy_all
    redirect_to @shelf, notice: "Removed '#{book.title}' from this shelf."
  end

  private

  # current_user.shelves.find — 404s if the shelf isn't owned by this user,
  # which is the privacy gate. No cross-user visibility.
  def set_shelf
    @shelf = current_user.shelves.find(params[:id])
  end

  def shelf_params
    params.require(:shelf).permit(:name, :description, :sync_to_kobo)
  end
end
