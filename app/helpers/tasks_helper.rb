module TasksHelper
  def summarize_task_result(task)
    return nil unless task.succeeded? && task.result.present?

    case task.kind
    when "calibre_import"
      r = task.result.with_indifferent_access
      parts = []
      parts << "#{r[:books_created]} new"
      parts << "#{r[:books_updated]} updated"
      parts << "#{r[:books_skipped_no_epub]} skipped (no EPUB)" if r[:books_skipped_no_epub].to_i.positive?
      parts.join(" · ")
    end
  end
end
