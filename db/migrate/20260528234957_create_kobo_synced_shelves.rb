class CreateKoboSyncedShelves < ActiveRecord::Migration[8.1]
  # Per-user snapshot of which shelves the device has already received.
  # Unlike kobo_synced_books, shelf_id has NO foreign key — when a Shelf
  # is destroyed in Tsundoku we want the kobo_synced_shelves row to
  # survive as an orphan so the next sync can emit a DeletedTag. The
  # cached kobo_uuid is what enables that — we don't need the Shelf row
  # to reconstruct the tombstone.
  def change
    create_table :kobo_synced_shelves do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :shelf_id, null: false
      t.string  :kobo_uuid, null: false

      t.timestamps
    end
    add_index :kobo_synced_shelves, [ :user_id, :shelf_id ], unique: true
    add_index :kobo_synced_shelves, :kobo_uuid
  end
end
