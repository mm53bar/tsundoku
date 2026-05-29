class AddKoboProgressToReadings < ActiveRecord::Migration[8.1]
  def change
    add_column :readings, :progress_percent, :integer
    add_column :readings, :location_value, :string
    add_column :readings, :location_type, :string
    add_column :readings, :location_source, :string
    add_column :readings, :kobo_synced_at, :datetime
    add_column :readings, :spent_reading_minutes, :integer
  end
end
