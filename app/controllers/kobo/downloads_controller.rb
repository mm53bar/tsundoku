module Kobo
  # GET /kobo/:handle/download/:book_id/:format
  # Streams the book to the device. Format dispatches between KEPUB (the
  # Kobo's native format, used when pre-converted by ConvertToKepubJob)
  # and EPUB (universal fallback).
  class DownloadsController < BaseController
    def show
      book = syncable_books.find_by(id: params[:book_id])
      return head :not_found unless book

      case params[:format].to_s.upcase
      when "KEPUB"
        return head :not_found unless book.kepub_available?
        send_file book.kepub_path,
                  type: "application/epub+zip",
                  disposition: "attachment",
                  filename: "#{book.title.parameterize.presence || 'book'}.kepub.epub"
      else
        path = book.epub_full_path
        return head :not_found unless path && File.exist?(path)
        send_file path,
                  type: "application/epub+zip",
                  disposition: "attachment",
                  filename: "#{book.title.parameterize.presence || 'book'}.epub"
      end
    end
  end
end
