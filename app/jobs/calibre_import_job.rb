class CalibreImportJob < ApplicationJob
  queue_as :default

  # Permanent condition — the user needs to fix something (mount the library
  # directory, drop a metadata.db into it). No point retrying.
  discard_on CalibreImporter::MissingDatabase do |job, error|
    if (task = Task.find_by(id: job.arguments.first))
      task.mark_failed!(error_message: error.message)
    end
  end

  # Anything else (transient I/O, DB lock, etc.) gets exponential backoff up
  # to 5 attempts; after that, mark the task failed so the user sees why.
  retry_on StandardError, attempts: 5, wait: :polynomially_longer do |job, error|
    if (task = Task.find_by(id: job.arguments.first))
      task.mark_failed!(error_message: "#{error.class}: #{error.message}")
    end
  end

  PROGRESS_THROTTLE_SECONDS = 0.5

  def perform(task_id)
    task = Task.find(task_id)
    task.mark_running!

    last_broadcast = Time.current - PROGRESS_THROTTLE_SECONDS
    importer = CalibreImporter.new
    importer.import! do |current, total|
      if Time.current - last_broadcast >= PROGRESS_THROTTLE_SECONDS
        task.update_progress!(current, total)
        last_broadcast = Time.current
      end
    end

    task.update_progress!(importer.stats.books_seen, importer.stats.books_seen)
    task.mark_succeeded!(result_data: importer.stats.to_h)
  end
end
