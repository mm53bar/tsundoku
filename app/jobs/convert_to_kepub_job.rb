require "open3"

class ConvertToKepubJob < ApplicationJob
  queue_as :default

  # Convert a book's EPUB to KEPUB so the Kobo gets paragraph-level
  # reading-progress fidelity instead of chapter-level. Output lands
  # alongside the source EPUB (so it rides along with library backups
  # and re-ingest); sync prefers it when present and falls back to the
  # raw EPUB otherwise. Paths come from BookAssets so the safe-root
  # rules apply uniformly.
  def perform(book_id, force: false)
    book = Book.find_by(id: book_id)
    return unless book

    assets = book.assets
    return unless assets.epub_downloadable?
    return if !force && assets.kepub_available?

    FileUtils.mkdir_p(File.dirname(assets.kepub_path))

    # kepubify writes to either a file or directory depending on -o.
    # Use a temp output and atomic-rename to avoid serving a partial
    # file if conversion fails halfway. Open3 captures stderr so we
    # can log kepubify's actual error message, not just exit status.
    tmp = "#{assets.kepub_path}.partial"
    stdout_str, stderr_str, status = Open3.capture3("kepubify", "-o", tmp, assets.epub_full_path)

    if status.success? && File.exist?(tmp)
      FileUtils.mv(tmp, assets.kepub_path)
      # Bump book.updated_at so the next Kobo sync emits ChangedEntitlement
      # with the new DownloadUrls listing the KEPUB. Without this touch the
      # diff doesn't see anything to send and the device keeps its cached
      # EPUB-only entitlements indefinitely.
      book.touch
    else
      File.delete(tmp) if File.exist?(tmp)
      Rails.logger.warn(
        "kepubify failed for book #{book.id} (#{book.title.inspect}) " \
        "from #{assets.epub_full_path.inspect}: " \
        "exit=#{status.exitstatus} stderr=#{stderr_str.strip.inspect} stdout=#{stdout_str.strip.inspect}"
      )
    end
  end
end
