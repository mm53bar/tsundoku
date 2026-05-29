namespace :kobo do
  desc "Migrate sync UUIDs from CWA — adopt Calibre's books.uuid as kobo_uuid so the device de-dupes against entitlements it already has"
  task migrate_from_cwa: :environment do
    # CWA's Kobo sync emits Calibre's books.uuid as the entitlement Id —
    # never persisting a separate sync UUID. Tsundoku's first migration
    # derived its own v5(book.id) UUIDs, so for any book a user synced
    # under both stacks, the device ended up with two entitlements: the
    # CWA one (still holding the downloaded EPUB) and a duplicate from
    # Tsundoku.
    #
    # This task swings the kobo_uuid over to Calibre's value. For each
    # affected book we also detach the existing kobo_synced_books rows
    # (book_id -> NULL, snapshot kept) so the next sync tombstones the
    # stale v5 UUID before re-emitting the entitlement under Calibre's
    # UUID — which the device matches against the CWA copy and no-ops.
    migrated = 0
    skipped  = 0

    Book.where.not(uuid: [ nil, "" ]).find_each do |book|
      if book.kobo_uuid == book.uuid
        skipped += 1
        next
      end

      Book.transaction do
        # Each detached row survives with its v5 UUID snapshot so sync
        # can emit a tombstone for it next pass. The existing destroy_all
        # in SyncController cleans them up afterward.
        book.kobo_synced_books.update_all(book_id: nil)

        # update_columns bypasses updated_at — we touch separately so the
        # sync diff for *this* book also re-emits under the new UUID.
        book.update_columns(kobo_uuid: book.uuid)
        book.touch
      end

      migrated += 1
      puts "  ##{book.id.to_s.ljust(5)} #{book.title.to_s.truncate(60)}"
    end

    puts "Migrated #{migrated} #{'book'.pluralize(migrated)}; #{skipped} already aligned."
    puts "Trigger a sync from each device to drop orphaned entitlements." if migrated.positive?
  end
end
