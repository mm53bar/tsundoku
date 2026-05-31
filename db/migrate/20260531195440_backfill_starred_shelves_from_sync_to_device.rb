class BackfillStarredShelvesFromSyncToDevice < ActiveRecord::Migration[8.1]
  # Moves every (user, book) pair where readings.sync_to_device=true onto
  # the user's Starred shelf. Creates the Starred shelf lazily per user.
  # The Reading row is left intact — only the sync intent is migrated;
  # progress and other Reading state stay.
  #
  # Idempotent: re-running skips books already on the user's Starred
  # shelf. Safe to run before or after the column drop (the next
  # migration), but ordering matters for production — run THIS one
  # first so we don't lose the data.
  #
  # On users.find_each: this migration uses plain SQL via execute() so
  # it doesn't depend on application code that may have moved on by
  # the time the migration runs in a fresh environment.
  def up
    say_with_time "Backfilling Starred shelves from sync_to_device readings" do
      backfill_count = 0

      execute(<<~SQL).each do |row|
        SELECT DISTINCT r.user_id, r.book_id
        FROM readings r
        WHERE r.sync_to_device = 1
      SQL
        user_id = row["user_id"]
        book_id = row["book_id"]

        # Find or create the user's Starred shelf.
        shelf = execute(<<~SQL).first
          SELECT id FROM shelves
          WHERE user_id = #{user_id} AND default_for_star = 1
          LIMIT 1
        SQL

        if shelf.nil?
          execute(<<~SQL)
            INSERT INTO shelves (user_id, name, sync_to_kobo, default_for_star, kobo_uuid, created_at, updated_at)
            VALUES (#{user_id}, 'Starred', 1, 1, '#{SecureRandom.uuid}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          SQL
          shelf_id = execute("SELECT last_insert_rowid() AS id").first["id"]
        else
          shelf_id = shelf["id"]
        end

        # Skip if the book is already on this Starred shelf (idempotency).
        existing = execute(<<~SQL).first
          SELECT id FROM shelf_entries
          WHERE shelf_id = #{shelf_id} AND book_id = #{book_id}
          LIMIT 1
        SQL
        next if existing

        next_position = execute(<<~SQL).first["pos"].to_i
          SELECT COALESCE(MAX(position), -1) + 1 AS pos
          FROM shelf_entries
          WHERE shelf_id = #{shelf_id}
        SQL

        execute(<<~SQL)
          INSERT INTO shelf_entries (shelf_id, book_id, position, created_at, updated_at)
          VALUES (#{shelf_id}, #{book_id}, #{next_position}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
        backfill_count += 1
      end

      say "#{backfill_count} (user, book) pairs moved onto Starred shelves", true
    end
  end

  def down
    # Best-effort reverse: drop every entry on a Starred shelf and the
    # Starred shelves themselves. We don't restore sync_to_device — it
    # may be gone by the time this runs.
    say_with_time "Removing Starred shelves" do
      execute(<<~SQL)
        DELETE FROM shelf_entries
        WHERE shelf_id IN (SELECT id FROM shelves WHERE default_for_star = 1)
      SQL
      execute("DELETE FROM shelves WHERE default_for_star = 1")
    end
  end
end
