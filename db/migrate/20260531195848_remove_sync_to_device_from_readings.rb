class RemoveSyncToDeviceFromReadings < ActiveRecord::Migration[8.1]
  # The sync-intent role of this column was migrated to Starred-shelf
  # membership in the prior migration. Books reach the Kobo via
  # syncing shelves (default Starred + any user-created syncing
  # shelves); Reading rows now carry only progress data.
  def change
    remove_column :readings, :sync_to_device, :boolean, default: false, null: false
  end
end
