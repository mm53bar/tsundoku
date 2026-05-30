class AddRemainingTimeMinutesToReadings < ActiveRecord::Migration[8.1]
  def change
    add_column :readings, :remaining_time_minutes, :integer
  end
end
