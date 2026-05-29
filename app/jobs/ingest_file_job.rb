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

      # Auto-enqueue enrichment if there's an ISBN to look up. The enrichment
      # task is reviewable and will surface in the banner as a pending review
      # the way every other enrichment does.
      if result.book.isbn.present?
        enrich_task = Task.create!(kind: "metadata_enrichment", subject: result.book, status: :queued)
        EnrichBookJob.perform_later(enrich_task.id)
      end

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
