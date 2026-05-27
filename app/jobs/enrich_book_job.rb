class EnrichBookJob < ApplicationJob
  queue_as :default

  retry_on StandardError, attempts: 5, wait: :polynomially_longer do |job, error|
    if (task = Task.find_by(id: job.arguments.first))
      task.mark_failed!(error_message: "#{error.class}: #{error.message}")
    end
  end

  def perform(task_id)
    task = Task.find(task_id)
    book = task.subject
    unless book
      task.mark_failed!(error_message: "Task has no subject book")
      return
    end

    task.mark_running!
    task.update_progress!(0, 1)

    proposal = BookEnricher.new(book).build_proposal

    task.update_progress!(1, 1)
    task.mark_succeeded!(result_data: proposal)
  end
end
