namespace :enrichment do
  desc "Run BookEnricher#build_proposal against every slug-less-author book " \
       "that hasn't been attempted in the last 30 days. Paced under Hardcover's " \
       "60 req/min limit. Idempotent — re-running picks up where the previous " \
       "run paused and skips the long tail of books with no current match."
  task backfill_slugs: :environment do
    unless HardcoverClient.available?
      abort "Hardcover token not configured — set HARDCOVER_APP_API_TOKEN to enable."
    end

    cutoff = ENV.fetch("ENRICHMENT_RETRY_AFTER_DAYS", "30").to_i.days.ago
    # Sleep between books so the burst never breaches Hardcover's 60 req/min
    # quota. Each book costs 2-3 calls (ISBN or title-search lookup + cover
    # harvest), so ~2.5s between books holds us under the limit with headroom.
    pause_seconds = ENV.fetch("ENRICHMENT_PAUSE_SECONDS", "2.5").to_f

    candidates = Book.joins(:authors)
                     .where(authors: { hardcover_slug: nil })
                     .where("books.last_enrichment_attempted_at IS NULL OR books.last_enrichment_attempted_at < ?", cutoff)
                     .distinct

    total = candidates.count
    if total.zero?
      puts "No books need slug backfill — every author has a slug or has been attempted within the last #{cutoff.then { |t| (Time.current - t).to_i / 86_400 }} days."
      next
    end

    puts "Backfilling Hardcover slugs across #{total} #{'book'.pluralize(total)} (pace: #{pause_seconds}s/book)…"
    processed = 0
    stamped_authors = 0
    failed = 0

    candidates.find_each do |book|
      author_ids_before = book.authors.where(hardcover_slug: nil).pluck(:id)
      if author_ids_before.empty?
        # Raced — a sibling book under the same author already stamped it.
        processed += 1
        next
      end

      begin
        BookEnricher.new(book).build_proposal
        newly_stamped = Author.where(id: author_ids_before).where.not(hardcover_slug: nil).count
        stamped_authors += newly_stamped
      rescue StandardError => e
        failed += 1
        Rails.logger.warn("enrichment:backfill_slugs failed for book ##{book.id}: #{e.class}: #{e.message}")
      end

      processed += 1
      puts "  #{processed}/#{total} processed (#{stamped_authors} authors stamped, #{failed} failed)" if (processed % 25).zero?

      sleep pause_seconds
    end

    puts "Done. Processed #{processed} books; stamped #{stamped_authors} authors; #{failed} failed."
  end
end
