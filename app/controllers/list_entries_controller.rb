class ListEntriesController < ApplicationController
  before_action :set_owned_list

  def create
    title  = params.dig(:list_entry, :title).to_s.strip
    author = params.dig(:list_entry, :author_name).to_s.strip

    if title.empty?
      redirect_to @list, alert: "Title is required."
      return
    end

    book = BookMatcher.match(title: title, author: author.presence)
    position = (@list.list_entries.maximum(:position) || -1) + 1

    @list.list_entries.create!(
      position: position,
      title: title,
      author_name: author.presence,
      book: book
    )

    flash_message = if book
      "Added '#{title}' — matched to your library."
    else
      "Added '#{title}' — not in your library."
    end
    redirect_to @list, notice: flash_message
  end

  def destroy
    entry = @list.list_entries.find(params[:id])
    entry.destroy
    redirect_to @list, notice: "Removed '#{entry.title}'."
  end

  private

  # Entries are an owner-only concern. Scoping the lookup through
  # `current_user.lists` means non-owners 404 here rather than landing
  # on a "not allowed" redirect — matches the rest of the app.
  def set_owned_list
    @list = current_user.lists.find(params[:list_id])
  end
end
