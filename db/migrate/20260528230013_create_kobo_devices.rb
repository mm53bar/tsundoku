class CreateKoboDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :kobo_devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :serial_number, null: false
      t.string :model
      t.string :firmware_version
      t.string :os_version
      t.datetime :last_seen_at

      t.timestamps
    end
    add_index :kobo_devices, [ :user_id, :serial_number ], unique: true
  end
end
