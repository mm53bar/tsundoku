require "fileutils"

class IngestFileJob < ApplicationJob
  queue_as :default

  # Subdirs of the ingest root where we park files we've finished with but did
  # not import. Dot-prefixed on purpose: AutoIngestScanJob's
  # Dir.glob("**/*.epub") skips dot-directories (no FNM_DOTMATCH), so parked
  # files are excluded from re-scan — that's what stops the re-ingest loop.
  # Same volume as the source, so the move is an atomic rename.
  DUPLICATES_DIR = ".duplicates".freeze
  FAILED_DIR     = ".failed".freeze

  retry_on StandardError, attempts: 5, wait: :polynomially_longer do |job, error|
    if (task = Task.find_by(id: job.arguments.first))
      task.mark_failed!(error_message: "#{error.class}: #{error.message}")
    end
  end

  def perform(task_id, file_path)
    task = Task.find(task_id)
    task.mark_running!

    result = BookIngester.ingest(file_path)

    case result.status
    when :ingested
      task.update!(subject: result.book)
      task.mark_succeeded!(result_data: {
        "status" => "ingested",
        "book_id" => result.book.id,
        "title" => result.book.title
      })

      # Always enqueue enrichment. BookEnricher uses the ISBN path when
      # one is present and falls back to a title+author search otherwise;
      # either way the proposal is reviewable and surfaces in the banner
      # the same way. If nothing matches, the task auto-clears via the
      # proposal_actionable? check in EnrichBookJob.
      enrich_task = Task.create!(kind: "metadata_enrichment", subject: result.book, status: :queued)
      EnrichBookJob.perform_later(enrich_task.id)

      # Convert to KEPUB so the Kobo gets paragraph-level reading-progress
      # fidelity. Background job — the sync controller serves KEPUB when
      # available and falls back to EPUB otherwise, so this is purely
      # additive (sync works either way).
      ConvertToKepubJob.perform_later(result.book.id)

    when :duplicate
      # The book is already in the library, so this dropped file is redundant.
      # Park it out of the scan path so it isn't re-ingested every cycle (it's
      # preserved under .duplicates/ rather than deleted, in case the operator
      # wants the file).
      parked = quarantine(file_path, DUPLICATES_DIR)
      task.update!(subject: result.book)
      task.mark_succeeded!(result_data: {
        "status" => "duplicate",
        "book_id" => result.book.id,
        "title" => result.book.title,
        "parked_at" => parked
      })

    else
      # Terminal failure — BookIngester rescues internally and returns :failed,
      # and a bad EPUB won't succeed on retry. Park it for inspection so it
      # stops looping through the scan.
      quarantine(file_path, FAILED_DIR)
      task.mark_failed!(error_message: result.reason || "Unknown ingest failure")
    end
  end

  private

  # Move a processed-but-not-imported file into a dot-subdir of the ingest
  # root. Best-effort: on any error we log and leave the file in place (it
  # will simply be retried on the next scan — the pre-fix behavior, no worse).
  def quarantine(file_path, subdir)
    return nil unless File.exist?(file_path)
    root = Rails.configuration.x.ingest_path
    return nil if root.blank?

    dest_dir = File.join(root, subdir)
    FileUtils.mkdir_p(dest_dir)
    dest = collision_free(File.join(dest_dir, File.basename(file_path)))
    FileUtils.mv(file_path, dest)
    Rails.logger.info("IngestFileJob: parked #{file_path} → #{dest}")
    dest
  rescue => e
    Rails.logger.warn("IngestFileJob: could not park #{file_path} in #{subdir}/: #{e.class}: #{e.message}")
    nil
  end

  # Don't clobber an already-parked file of the same name.
  def collision_free(path)
    return path unless File.exist?(path)
    dir  = File.dirname(path)
    ext  = File.extname(path)
    base = File.basename(path, ext)
    n = 2
    n += 1 while File.exist?(File.join(dir, "#{base}-#{n}#{ext}"))
    File.join(dir, "#{base}-#{n}#{ext}")
  end
end
