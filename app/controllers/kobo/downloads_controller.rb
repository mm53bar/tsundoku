module Kobo
  # GET /kobo/:handle/download/:book_id/:format
  # Streams the book's EPUB to the device. Phase B serves EPUB only;
  # KEPUB conversion is deferred to Phase E.
  class DownloadsController < BaseController
    def show
      book = syncable_books.find_by(id: params[:book_id])
      return head :not_found unless book

      path = book.epub_full_path
      return head :not_found unless path && File.exist?(path)

      send_file path,
                type: "application/epub+zip",
                disposition: "attachment",
                filename: "#{book.title.parameterize.presence || 'book'}.epub"
    end
  end
end
