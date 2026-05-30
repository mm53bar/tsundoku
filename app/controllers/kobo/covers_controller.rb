module Kobo
  # GET /kobo/:handle/:book_uuid/:width/:height/:greyscale/image.jpg
  # Serves a book's cover image. The device requests specific dimensions;
  # for phase B we serve the original cover and let the device resize.
  # Add server-side resizing later if the device proves unhappy.
  class CoversController < BaseController
    def show
      book = find_book_by_kobo_uuid(params[:book_uuid])
      return head :not_found unless book

      assets = book.assets
      return head :not_found unless assets.cover_available?

      send_file assets.cover_full_path,
                type:        assets.cover_mime_type,
                disposition: "inline"
    end
  end
end
