class CreateShelves < ActiveRecord::Migration[8.1]
  def change
    create_table :shelves do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.boolean :sync_to_kobo, null: false, default: false
      t.timestamps
    end
    add_index :shelves, [ :user_id, :name ], unique: true
    add_index :shelves, :sync_to_kobo

    create_table :shelf_entries do |t|
      t.references :shelf, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :shelf_entries, [ :shelf_id, :book_id ], unique: true
    add_index :shelf_entries, [ :shelf_id, :position ]
  end
end
