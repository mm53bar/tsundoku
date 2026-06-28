namespace :kobo do
  # Self-contained helper for the CWA reading-state lookup. Lives inside
  # the namespace block as a class rather than top-level `def`s so the
  # methods don't leak onto Object.
  cwa_helpers = Class.new do
    # Pull CWA's per-(user, book) reading state out of app.db: latest
    # bookmark + statistics row, joined via kobo_reading_state. Returns
    # an empty hash when the user never opened the book.
    def self.reading_state(cwa, cwa_user_id, calibre_book_id)
      row = cwa.execute(<<~SQL, [ cwa_user_id, calibre_book_id ]).first
        SELECT rs.last_modified              AS rs_last_modified,
               bm.location_source            AS location_source,
               bm.location_type              AS location_type,
               bm.location_value             AS location_value,
               bm.progress_percent           AS percent,
               st.spent_reading_minutes      AS spent_minutes,
               st.remaining_time_minutes     AS remaining_minutes
        FROM   kobo_reading_state rs
        LEFT JOIN kobo_bookmark    bm ON bm.kobo_reading_state_id = rs.id
        LEFT JOIN kobo_statistics  st ON st.kobo_reading_state_id = rs.id
        WHERE  rs.user_id = ? AND rs.book_id = ?
        LIMIT  1
      SQL
      return {} unless row

      last_modified = begin
        Time.zone.parse(row["rs_last_modified"].to_s)
      rescue StandardError
        nil
      end

      {
        percent:           row["percent"],
        location_source:   row["location_source"].presence,
        location_type:     row["location_type"].presence,
        location_value:    row["location_value"].presence,
        spent_minutes:     row["spent_minutes"],
        remaining_minutes: row["remaining_minutes"],
        last_modified:     last_modified
      }
    end
  end

  # Replicate CWA's per-user sync state into Tsundoku — kobo_synced_books
  # rows (so deletes can tombstone), a ShelfEntry on the user's Starred
  # shelf (so the book stays in syncable_books), and a Reading record
  # carrying any progress/bookmark/timing data CWA captured.
  #
  # Putting the book on the Starred shelf is the important bit: without
  # it the next sync would immediately tombstone every imported book
  # that doesn't have a Tsundoku-side shelf membership — which is the
  # wrong default for a migration. Users opt *out* explicitly later
  # (un-star, or remove from the shelf); they shouldn't have to opt
  # back *in* for books CWA was already pushing.
  #
  # Usage:
  #   bin/rails 'kobo:import_sync_state_from_cwa[alex,smoketest]'
  #     — picks up <CWA_CONFIG_PATH>/app.db (default /cwa-config/app.db)
  #   bin/rails 'kobo:import_sync_state_from_cwa[alex,smoketest,/explicit/path.db]'
  #     — overrides the auto-discovered location
  desc "Import CWA's sync state (kobo_synced_books + reading progress) for a user pair"
  task :import_sync_state_from_cwa, [ :cwa_username, :tsundoku_username, :cwa_db_path ] => :environment do |_t, args|
    require "sqlite3"

    cwa_username      = args[:cwa_username].to_s
    tsundoku_username = args[:tsundoku_username].to_s
    cwa_db_path       = args[:cwa_db_path].presence ||
                        File.join(Rails.configuration.x.cwa_config_path, "app.db")

    abort "Usage: bin/rails 'kobo:import_sync_state_from_cwa[<cwa_user>,<tsundoku_user>,[<app.db>]]'" \
      if cwa_username.blank? || tsundoku_username.blank?
    abort "CWA db not found: #{cwa_db_path} (set CWA_CONFIG_PATH or pass an explicit path)" \
      unless File.exist?(cwa_db_path)

    tsundoku_user = User.find_by(username: tsundoku_username)
    abort "Tsundoku user not found: #{tsundoku_username}" unless tsundoku_user

    cwa = SQLite3::Database.new(cwa_db_path, readonly: true)
    cwa.results_as_hash = true

    cwa_user = cwa.execute("SELECT id FROM user WHERE name = ?", cwa_username).first
    abort "CWA user not found in app.db: #{cwa_username}" unless cwa_user
    cwa_user_id = cwa_user["id"]

    cwa_rows = cwa.execute("SELECT book_id FROM kobo_synced_books WHERE user_id = ?", cwa_user_id)
    puts "CWA reports #{cwa_rows.length} synced #{'book'.pluralize(cwa_rows.length)} for user #{cwa_username.inspect}."

    synced_created  = 0
    synced_existing = 0
    reading_created = 0
    reading_updated = 0
    missing         = 0

    cwa_rows.each do |row|
      calibre_id = row["book_id"]
      book = Book.find_by(calibre_id: calibre_id)
      unless book
        missing += 1
        next
      end

      # 1. kobo_synced_books row (so deletes can tombstone)
      ksb = tsundoku_user.kobo_synced_books.find_by(book_id: book.id)
      if ksb
        synced_existing += 1
      else
        tsundoku_user.kobo_synced_books.create!(book: book)
        synced_created  += 1
      end

      # 2. Star the book so it lands in syncable_books (this is what
      # the sync controller diffs against). Adds to the user's Starred
      # shelf, idempotent for re-runs.
      starred = tsundoku_user.starred_shelf
      starred.shelf_entries.find_or_create_by!(book: book) do |entry|
        entry.position = (starred.shelf_entries.maximum(:position) || -1) + 1
      end

      # 3. Reading record (so progress carries over)
      progress = cwa_helpers.reading_state(cwa, cwa_user_id, calibre_id)
      reading  = tsundoku_user.readings.find_or_initialize_by(book: book)
      was_new  = reading.new_record?

      # Status is derived from progress_percent + finished_at (no enum
      # to set). The before_save callback on Reading stamps started_at
      # / finished_at when progress changes — but we override those
      # with CWA's last_modified timestamp where available so the
      # history reflects when the user actually read, not "now."
      reading.progress_percent = progress[:percent].to_i  if progress[:percent].present?
      reading.location_source        = progress[:location_source]    if progress[:location_source]
      reading.location_type          = progress[:location_type]      if progress[:location_type]
      reading.location_value         = progress[:location_value]     if progress[:location_value]
      reading.spent_reading_minutes  = progress[:spent_minutes]      if progress[:spent_minutes]
      reading.remaining_time_minutes = progress[:remaining_minutes]  if progress[:remaining_minutes]
      reading.started_at  ||= progress[:last_modified] if progress[:percent].to_i.positive?
      reading.finished_at ||= progress[:last_modified] if progress[:percent].to_i >= Reading::FINISHED_THRESHOLD_PCT
      reading.save!

      was_new ? reading_created += 1 : reading_updated += 1
    end

    puts "kobo_synced_books: created #{synced_created}, already present #{synced_existing}."
    puts "readings:          created #{reading_created}, updated #{reading_updated}."
    puts "skipped:           #{missing} (no matching Tsundoku book)." if missing.positive?
    puts "Trigger a sync to push reading state to the device." if (synced_created + reading_created + reading_updated).positive?
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
