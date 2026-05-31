namespace :enrichment do
  desc "Run BookEnricher#build_proposal against every book so Hardcover slugs " \
       "get stamped onto local Authors and Series. Idempotent — re-running " \
       "skips books whose authors already have slugs and Hardcover lookups " \
       "already happened."
  task backfill_slugs: :environment do
    unless HardcoverClient.available?
      abort "Hardcover token not configured — set HARDCOVER_APP_API_TOKEN to enable."
    end

    candidates = Book.joins(:authors).where(authors: { hardcover_slug: nil }).distinct
    total = candidates.count
    if total.zero?
      puts "No books need slug backfill — every author already has a hardcover_slug."
    else
      puts "Backfilling Hardcover slugs across #{total} #{'book'.pluralize(total)}…"
      processed = 0
      stamped_authors = 0
      failed = 0

      candidates.find_each do |book|
        author_ids_before = book.authors.where(hardcover_slug: nil).pluck(:id)
        if author_ids_before.empty?
          # Raced — another pass on a sibling book already stamped this author. Still count it.
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
      end

      puts "Done. Processed #{processed} books; stamped #{stamped_authors} authors; #{failed} failed."
    end
  end
end
