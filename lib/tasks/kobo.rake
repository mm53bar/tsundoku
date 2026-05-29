namespace :kobo do
  # Read CWA's per-user kobo_synced_books table and replicate it into
  # Tsundoku's kobo_synced_books. This gives Tsundoku knowledge of every
  # entitlement CWA had pushed to a given device — without it, books CWA
  # synced but the user never touched in Tsundoku stay as orphans on the
  # device forever (no Tsundoku row to nullify, no tombstone on delete).
  #
  # After running this, the next sync will tombstone any imported book
  # that isn't in the user's current syncable set (no reading status, no
  # syncing-shelf membership) — which is the design intent: only books
  # the user has explicitly opted into ride along.
  #
  # Usage: bin/rails 'kobo:import_sync_state_from_cwa[/path/to/app.db,mike,smoketest]'
  desc "Import CWA's kobo_synced_books rows for a (CWA user → Tsundoku user) pair"
  task :import_sync_state_from_cwa, [ :cwa_db_path, :cwa_username, :tsundoku_username ] => :environment do |_t, args|
    require "sqlite3"

    cwa_db_path       = args[:cwa_db_path].to_s
    cwa_username      = args[:cwa_username].to_s
    tsundoku_username = args[:tsundoku_username].to_s

    abort "Usage: bin/rails 'kobo:import_sync_state_from_cwa[<app.db>,<cwa_username>,<tsundoku_username>]'" \
      if cwa_db_path.blank? || cwa_username.blank? || tsundoku_username.blank?
    abort "CWA db not found: #{cwa_db_path}" unless File.exist?(cwa_db_path)

    tsundoku_user = User.find_by(username: tsundoku_username)
    abort "Tsundoku user not found: #{tsundoku_username}" unless tsundoku_user

    cwa = SQLite3::Database.new(cwa_db_path, readonly: true)
    cwa.results_as_hash = true

    cwa_user = cwa.execute("SELECT id FROM user WHERE name = ?", cwa_username).first
    abort "CWA user not found in app.db: #{cwa_username}" unless cwa_user
    cwa_user_id = cwa_user["id"]

    cwa_rows = cwa.execute("SELECT book_id FROM kobo_synced_books WHERE user_id = ?", cwa_user_id)
    puts "CWA reports #{cwa_rows.length} synced #{'book'.pluralize(cwa_rows.length)} for user #{cwa_username.inspect}."

    created  = 0
    existing = 0
    missing  = 0

    cwa_rows.each do |row|
      calibre_id = row["book_id"]
      book = Book.find_by(calibre_id: calibre_id)
      unless book
        missing += 1
        next
      end

      ksb = tsundoku_user.kobo_synced_books.find_by(book_id: book.id)
      if ksb
        existing += 1
      else
        tsundoku_user.kobo_synced_books.create!(book: book)
        created += 1
      end
    end

    puts "Created #{created} #{'row'.pluralize(created)}; #{existing} already present; #{missing} skipped (no matching Tsundoku book)."
    puts "Trigger a sync to tombstone any non-syncable books." if created.positive?
  end

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
