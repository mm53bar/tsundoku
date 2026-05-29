module Kobo
  # GET /kobo/:handle/:book_uuid/:width/:height/:greyscale/image.jpg
  # Serves a book's cover image. The device requests specific dimensions;
  # for phase B we serve the original cover and let the device resize.
  # Add server-side resizing later if the device proves unhappy.
  class CoversController < BaseController
    def show
      book = find_book_by_kobo_uuid(params[:book_uuid])
      return head :not_found unless book

      path = book.cover_full_path
      return head :not_found unless path && File.exist?(path)

      send_file path, type: cover_mime_type(path), disposition: "inline"
    end

    private

    def cover_mime_type(path)
      case File.extname(path).downcase
      when ".png"           then "image/png"
      when ".gif"           then "image/gif"
      when ".webp"          then "image/webp"
      when ".jpg", ".jpeg"  then "image/jpeg"
      else                       "application/octet-stream"
      end
    end
  end
end
