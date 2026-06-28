class AutoIngestScanJob < ApplicationJob
  queue_as :default

  # Recurring scan of INGEST_PATH for new EPUBs (see config/recurring.yml).
  # Hand-off shape mirrors the manual "Scan" button: create a Task per
  # file, queue an IngestFileJob, let the existing downstream flow
  # (BookIngester → enrichment task → KEPUB conversion) take over.
  #
  # Two behaviors worth knowing:
  #
  #   1. Empty / no-op scans are silent. No task is created, nothing is
  #      logged. The scan runs every couple of minutes regardless of
  #      whether the directory has anything in it; we don't want to
  #      decorate the task tray or the logs with that noise.
  #
  #   2. When the scan finds work, a single auto_ingest_scan summary
  #      task is created in addition to the per-file book_ingest
  #      tasks. The summary is marked succeeded immediately (the work
  #      isn't this task, it's the spawned IngestFileJobs), so it
  #      settles within the standard 30-second recently_settled
  #      window — the user sees "Auto-ingest: queued N files" briefly
  #      and then the per-book metadata_enrichment tasks become the
  #      pending_review surface they care about.
  def perform
    root = Rails.configuration.x.ingest_path
    return if root.blank? || !Dir.exist?(root)

    # Dir.glob skips dot-directories by default (no FNM_DOTMATCH), so files
    # IngestFileJob parks in .duplicates/ and .failed/ are intentionally
    # excluded here — that's what stops finished files from re-ingesting.
    pending_paths = Dir.glob(File.join(root, "**/*.epub")).sort
    return if pending_paths.empty?

    in_flight_paths = Task.where(kind: "book_ingest", status: [ :queued, :running ])
                          .pluck(:result)
                          .filter_map { |r| r&.dig("file_path") }
                          .to_set

    fresh = pending_paths.reject { |p| in_flight_paths.include?(p) }
    return if fresh.empty?

    fresh.each do |path|
      task = Task.create!(kind: "book_ingest", status: :queued, result: { "file_path" => path })
      IngestFileJob.perform_later(task.id, path)
    end

    summary = Task.create!(kind: "auto_ingest_scan", status: :queued)
    summary.mark_succeeded!(result_data: {
      "queued_count" => fresh.length,
      "files"        => fresh.map { |p| File.basename(p) }
    })

    Rails.logger.info("AutoIngestScanJob: queued #{fresh.length} of #{pending_paths.length} pending file#{'s' if pending_paths.length != 1}")
  end
end
