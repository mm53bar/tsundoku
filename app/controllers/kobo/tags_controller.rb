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
      # Mark as already-synced so next sync doesn't re-emit NewTag for a
      # shelf the device just created itself.
      @kobo_user.kobo_synced_shelves.create!(shelf_id: shelf.id, kobo_uuid: shelf.kobo_uuid)
      add_books_to_shelf(shelf, items_param)
      render json: shelf.kobo_uuid, status: :created
    end

    # PUT /kobo/:handle/v1/library/tags/:tag_id
    def update
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      shelf.update!(name: name_param) if name_param.present?
      touch_synced_shelf(shelf)
      head :ok
    end

    # DELETE /kobo/:handle/v1/library/tags/:tag_id
    def destroy
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      # Device just deleted the shelf — no tombstone needed. Clear the
      # synced record too so next sync doesn't try to send a DeletedTag.
      @kobo_user.kobo_synced_shelves.where(shelf_id: shelf.id).destroy_all
      shelf.destroy
      head :ok
    end

    # POST /kobo/:handle/v1/library/tags/:tag_id/items
    def add_items
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      add_books_to_shelf(shelf, items_param)
      touch_synced_shelf(shelf)
      head :ok
    end

    # POST /kobo/:handle/v1/library/tags/:tag_id/items/delete
    def remove_items
      shelf = find_shelf_by_kobo_uuid(params[:tag_id])
      return head :not_found unless shelf

      remove_books_from_shelf(shelf, items_param)
      touch_synced_shelf(shelf)
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
        # Device already has this book; record it as synced so next sync
        # doesn't re-emit it as a NewEntitlement.
        @kobo_user.kobo_synced_books.find_or_create_by!(book: book)
      end
    end

    def remove_books_from_shelf(shelf, items)
      items.each do |item|
        book = find_book_by_kobo_uuid(item["RevisionId"])
        next unless book

        shelf.shelf_entries.where(book: book).destroy_all
      end
    end

    def touch_synced_shelf(shelf)
      @kobo_user.kobo_synced_shelves.where(shelf_id: shelf.id).update_all(updated_at: Time.current)
    end
  end
end
