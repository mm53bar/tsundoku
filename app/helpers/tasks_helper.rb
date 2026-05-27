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
    when "metadata_enrichment"
      r = task.result.with_indifferent_access
      return "No Hardcover match" unless r[:hardcover_matched]

      parts = []
      parts << "cover replaced" if r[:cover_replaced]
      parts << "#{r[:identifiers_added]} new IDs" if r[:identifiers_added].to_i.positive?
      parts << "#{r[:fields_updated]} fields filled" if r[:fields_updated].to_i.positive?
      parts.any? ? "Hardcover: #{parts.join(' · ')}" : "Hardcover: already current"
    end
  end
end
