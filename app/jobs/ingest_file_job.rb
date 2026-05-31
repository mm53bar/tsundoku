class IngestFileJob < ApplicationJob
  queue_as :default

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
      task.update!(subject: result.book)
      task.mark_succeeded!(result_data: {
        "status" => "duplicate",
        "book_id" => result.book.id,
        "title" => result.book.title
      })

    else
      task.mark_failed!(error_message: result.reason || "Unknown ingest failure")
    end
  end
end
