module Kobo
  # GET /kobo/:handle/download/:book_id/:format
  # Streams the book to the device. Format dispatches between KEPUB (the
  # Kobo's native format, used when pre-converted by ConvertToKepubJob)
  # and EPUB (universal fallback).
  class DownloadsController < BaseController
    def show
      book = syncable_books.find_by(id: params[:book_id])
      return head :not_found unless book

      assets = book.assets
      case params[:format].to_s.upcase
      when "KEPUB"
        return head :not_found unless assets.kepub_available?
        send_file assets.kepub_path,
                  type: "application/epub+zip",
                  disposition: "attachment",
                  filename: "#{book.title.parameterize.presence || 'book'}.kepub.epub"
      else
        return head :not_found unless assets.epub_downloadable?
        send_file assets.epub_full_path,
                  type: "application/epub+zip",
                  disposition: "attachment",
                  filename: "#{book.title.parameterize.presence || 'book'}.epub"
      end
    end
  end
end
