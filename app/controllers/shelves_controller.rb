class ShelvesController < ApplicationController
  before_action :set_shelf, only: [ :show, :edit, :update, :destroy ]

  def index
    @shelves = current_user.shelves.by_name.includes(:shelf_entries)
  end

  def show
    @books = @shelf.books.by_title.includes(:authors, :series, :lists)
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
