class AddInProgressReadingCountToUsers < ActiveRecord::Migration[8.1]
  # Maintained counter — incremented/decremented by Reading callbacks
  # when a row enters or leaves the in-progress state (matching the
  # Reading.in_progress SQL scope). Lets the navbar "Reading (N)" pill
  # render without a COUNT query on every page load.
  #
  # The boundary stays in Reading::FINISHED_THRESHOLD_PCT — both this
  # backfill and the runtime scope reference it.
  def change
    add_column :users, :in_progress_reading_count, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE users
          SET in_progress_reading_count = (
            SELECT COUNT(*) FROM readings
            WHERE readings.user_id = users.id
              AND finished_at IS NULL
              AND progress_percent > 0
              AND progress_percent < 95
          )
        SQL
      end
    end
  end
end
