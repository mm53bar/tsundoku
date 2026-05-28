class CreateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :lists do |t|
      t.string :name, null: false
      t.text :description
      t.string :source_url
      t.timestamps
    end
    add_index :lists, :name

    create_table :list_entries do |t|
      t.references :list, foreign_key: true, null: false
      t.integer :position, null: false, default: 0
      t.string :title, null: false
      t.string :author_name
      t.references :book, foreign_key: true
      t.timestamps
    end
    add_index :list_entries, [ :list_id, :position ]
  end
end
