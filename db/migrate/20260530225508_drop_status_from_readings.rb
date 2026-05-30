class DropStatusFromReadings < ActiveRecord::Migration[8.1]
  # The status enum is being replaced by derivation from progress_percent
  # + finished_at. See ADR 20260530-reading-status-derived-from-progress.
  #
  # Rows with status=2 ("read") need their progress_percent and
  # finished_at populated so the derivation produces the same observable
  # state. currently_reading and want_to_read rows already encode their
  # state in (progress_percent, started_at, finished_at) correctly, so
  # they need no backfill.
  def up
    execute <<~SQL.squish
      UPDATE readings
      SET   finished_at      = COALESCE(finished_at, updated_at),
            progress_percent = COALESCE(progress_percent, 100)
      WHERE status = 2
    SQL

    remove_column :readings, :status
  end

  def down
    add_column :readings, :status, :integer, default: 0, null: false

    # Reverse derivation: progress_percent + finished_at -> the old
    # three-state enum. Lossy if anyone changed progress between up and
    # down, but the migration is intended to be one-way in practice.
    execute <<~SQL.squish
      UPDATE readings
      SET   status = CASE
                       WHEN finished_at IS NOT NULL OR COALESCE(progress_percent, 0) >= 95 THEN 2
                       WHEN COALESCE(progress_percent, 0) > 0                              THEN 1
                       ELSE 0
                     END
    SQL

    add_index :readings, :status
  end
end
