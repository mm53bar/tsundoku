class CreateLibrarySchema < ActiveRecord::Migration[8.1]
  def change
    create_table :authors do |t|
      t.string :name, null: false
      t.string :sort_name
      t.integer :calibre_id
      t.timestamps
    end
    add_index :authors, :calibre_id, unique: true
    add_index :authors, :name

    create_table :series do |t|
      t.string :name, null: false
      t.string :sort_name
      t.integer :calibre_id
      t.timestamps
    end
    add_index :series, :calibre_id, unique: true
    add_index :series, :name

    create_table :tags do |t|
      t.string :name, null: false
      t.integer :calibre_id
      t.timestamps
    end
    add_index :tags, :calibre_id, unique: true
    add_index :tags, :name, unique: true

    create_table :books do |t|
      t.integer :calibre_id, null: false
      t.string :title, null: false
      t.string :sort_title
      t.references :series, foreign_key: true
      t.decimal :series_index, precision: 10, scale: 2
      t.datetime :pubdate
      t.string :isbn
      t.string :uuid
      t.text :description
      t.string :path, null: false
      t.string :cover_path
      t.string :file_name
      t.string :file_format
      t.datetime :last_modified
      t.datetime :imported_at, null: false
      t.timestamps
    end
    add_index :books, :calibre_id, unique: true
    add_index :books, :title
    add_index :books, :uuid

    create_table :book_authors do |t|
      t.references :book, foreign_key: true, null: false
      t.references :author, foreign_key: true, null: false
      t.integer :position, default: 0
    end
    add_index :book_authors, [ :book_id, :author_id ], unique: true

    create_table :book_tags do |t|
      t.references :book, foreign_key: true, null: false
      t.references :tag, foreign_key: true, null: false
    end
    add_index :book_tags, [ :book_id, :tag_id ], unique: true
  end
end
