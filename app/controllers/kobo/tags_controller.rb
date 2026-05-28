module Kobo
  # Device-side shelf edits. The Kobo calls these endpoints when the user
  # creates/renames/deletes a "shelf" on the device, or adds/removes a
  # book from one. Each lands as a corresponding Shelf / ShelfEntry change
  # in Tsundoku, owned by the auth-handle's user.
  #
  # Books referenced by RevisionId that we don't recognise (e.g. Kobo-
  # store books the device knows about but we don't sync) are silently
  # skipped — they're not part of the Tsundoku library.
  class TagsController < BaseController
    # POST /kobo/:handle/v1/library/tags
    def create
      shelf = @kobo_user.shelves.create!(name: name_param, sync_to_kobo: true)
      add_books_to_shelf(shelf, items_param)
      render json: shelf.kobo_uuid, status: :created
    end

    # PUT /kobo/:handle/v1/library/tags/:tag_id
    def update
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      shelf.update!(name: name_param) if name_param.present?
      head :ok
    end

    # DELETE /kobo/:handle/v1/library/tags/:tag_id
    def destroy
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      shelf.destroy
      head :ok
    end

    # POST /kobo/:handle/v1/library/tags/:tag_id/items
    def add_items
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      add_books_to_shelf(shelf, items_param)
      head :ok
    end

    # POST /kobo/:handle/v1/library/tags/:tag_id/items/delete
    def remove_items
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      remove_books_from_shelf(shelf, items_param)
      head :ok
    end

    private

    def name_param
      params[:Name].presence
    end

    def items_param
      Array(params[:Items])
    end

    def add_books_to_shelf(shelf, items)
      items.each do |item|
        book = find_book_by_kobo_uuid(item["RevisionId"])
        next unless book

        shelf.shelf_entries.find_or_create_by!(book: book) do |entry|
          entry.position = (shelf.shelf_entries.maximum(:position) || -1) + 1
        end
      end
    end

    def remove_books_from_shelf(shelf, items)
      items.each do |item|
        book = find_book_by_kobo_uuid(item["RevisionId"])
        next unless book

        shelf.shelf_entries.where(book: book).destroy_all
      end
    end
  end
end
