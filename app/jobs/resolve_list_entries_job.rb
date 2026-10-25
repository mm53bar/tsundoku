class ResolveListEntriesJob < ApplicationJob
  queue_as :default

  # Hardcover allows 60 requests a minute.
  SEARCH_INTERVAL_SECONDS = 1.1

  def perform(list)
    return unless HardcoverClient.available?

    client = HardcoverClient.new
    list.list_entries.pending_resolution.each_with_index do |entry, index|
      sleep SEARCH_INTERVAL_SECONDS if index.positive?

      query = [ entry.title, entry.author_name ].compact_blank.join(" ")
      hits = client.search_books(query, per_page: 10).map { |doc| HardcoverHit.from_document(doc) }
      entry.resolve_with!(hits)
    end
  end
end
