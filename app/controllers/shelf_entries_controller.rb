class ShelfEntriesController < ApplicationController
  before_action :set_book
  before_action :set_shelf,  only: :toggle
  before_action :set_starred, only: :toggle_star

  # Single toggle endpoint — creates the ShelfEntry if not present,
  # destroys it if it is. Matches the checkbox UX: one click, one
  # endpoint, state inferred from current membership.
  def toggle
    entry = @shelf.shelf_entries.find_by(book: @book)
    if entry
      entry.destroy
      @on_shelf = false
    else
      @shelf.shelf_entries.create!(book: @book, position: next_position(@shelf))
      @on_shelf = true
    end

    @user_shelves, @shelf_member_ids_by_book, @starred_shelf_id = preload_shelf_membership_for([ @book ])

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @book }
    end
  end

  # Toggle the book's membership in the current user's Starred shelf.
  # Wrapper around the same toggle semantics; the caller (star icon)
  # doesn't need to know the shelf id. Re-renders just the card so the
  # star icon and the picker's `+` button both reflect the new state.
  def toggle_star
    entry = @starred.shelf_entries.find_by(book: @book)
    if entry
      entry.destroy
      @starred_on = false
    else
      @starred.shelf_entries.create!(book: @book, position: next_position(@starred))
      @starred_on = true
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: @book }
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

  def set_starred
    @starred = current_user.starred_shelf
  end

  def next_position(shelf)
    (shelf.shelf_entries.maximum(:position) || -1) + 1
  end
end
