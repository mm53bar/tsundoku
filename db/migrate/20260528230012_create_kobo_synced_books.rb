class CreateKoboSyncedBooks < ActiveRecord::Migration[8.1]
  def change
    create_table :kobo_synced_books do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true

      t.timestamps
    end
    add_index :kobo_synced_books, [ :user_id, :book_id ], unique: true
  end
end
