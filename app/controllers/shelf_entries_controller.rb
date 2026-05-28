class ShelfEntriesController < ApplicationController
  before_action :set_book
  before_action :set_shelf

  # Single toggle endpoint — creates the ShelfEntry if not present,
  # destroys it if it is. Matches the checkbox UX: one click, one
  # endpoint, state inferred from current membership.
  def toggle
    entry = @shelf.shelf_entries.find_by(book: @book)
    if entry
      entry.destroy
      @on_shelf = false
    else
      @shelf.shelf_entries.create!(book: @book, position: next_position)
      @on_shelf = true
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @book }
    end
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end

  # current_user.shelves enforces ownership — toggling someone else's
  # shelf is a 404, not a forbidden.
  def set_shelf
    @shelf = current_user.shelves.find(params[:shelf_id])
  end

  def next_position
    (@shelf.shelf_entries.maximum(:position) || -1) + 1
  end
end
