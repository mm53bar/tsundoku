class AddPublishersIdentifiersAddedAt < ActiveRecord::Migration[8.1]
  def change
    create_table :publishers do |t|
      t.string :name, null: false
      t.string :sort_name
      t.integer :calibre_id
      t.timestamps
    end
    add_index :publishers, :calibre_id, unique: true
    add_index :publishers, :name

    create_table :book_identifiers do |t|
      t.references :book, foreign_key: true, null: false
      t.string :kind, null: false
      t.string :value, null: false
      t.timestamps
    end
    add_index :book_identifiers, [ :book_id, :kind, :value ], unique: true
    add_index :book_identifiers, [ :kind, :value ]

    add_reference :books, :publisher, foreign_key: true
    add_column :books, :added_at, :datetime
    add_index :books, :added_at

    remove_column :books, :isbn, :string
  end
end
