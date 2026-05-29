class AddSyncToDeviceToReadings < ActiveRecord::Migration[8.1]
  # Split sync intent from reading progress: the old `status` enum was
  # overloaded ("want_to_read" *also* meant "sync to my Kobo"). With a
  # dedicated boolean, the user can keep finished books on the device,
  # read on another device without syncing, etc. — combinations the old
  # model couldn't express. Backfill follows the legacy mapping so the
  # existing syncable set stays exactly the same.
  def change
    add_column :readings, :sync_to_device, :boolean, default: false, null: false
    add_index  :readings, :sync_to_device

    reversible do |dir|
      dir.up do
        # status enum: want_to_read=0, currently_reading=1, read=2.
        # The first two were SYNCABLE_STATUSES; carry that forward.
        execute "UPDATE readings SET sync_to_device = 1 WHERE status IN (0, 1)"
      end
    end
  end
end
