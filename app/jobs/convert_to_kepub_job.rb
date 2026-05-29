class ConvertToKepubJob < ApplicationJob
  queue_as :default

  # Convert a book's EPUB to KEPUB so the Kobo gets paragraph-level
  # reading-progress fidelity instead of chapter-level. Output is
  # cached in Rails storage; sync prefers it when present and falls
  # back to the raw EPUB otherwise.
  def perform(book_id, force: false)
    book = Book.find_by(id: book_id)
    return unless book
    return unless book.epub_downloadable?
    return if !force && book.kepub_available?

    FileUtils.mkdir_p(File.dirname(book.kepub_path))

    # kepubify writes to either a file or directory depending on -o.
    # Use a temp output and atomic-rename to avoid serving a partial
    # file if conversion fails halfway.
    tmp = "#{book.kepub_path}.partial"
    success = system("kepubify", "-o", tmp, book.epub_full_path)

    if success && File.exist?(tmp)
      FileUtils.mv(tmp, book.kepub_path)
    else
      File.delete(tmp) if File.exist?(tmp)
      Rails.logger.warn("kepubify failed for book #{book.id} (#{book.title.inspect})")
    end
  end
end
