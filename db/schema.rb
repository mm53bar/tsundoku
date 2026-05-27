# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_27_160000) do
  create_table "authors", force: :cascade do |t|
    t.integer "calibre_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "sort_name"
    t.datetime "updated_at", null: false
    t.index ["calibre_id"], name: "index_authors_on_calibre_id", unique: true
    t.index ["name"], name: "index_authors_on_name"
  end

  create_table "book_authors", force: :cascade do |t|
    t.integer "author_id", null: false
    t.integer "book_id", null: false
    t.integer "position", default: 0
    t.index ["author_id"], name: "index_book_authors_on_author_id"
    t.index ["book_id", "author_id"], name: "index_book_authors_on_book_id_and_author_id", unique: true
    t.index ["book_id"], name: "index_book_authors_on_book_id"
  end

  create_table "book_identifiers", force: :cascade do |t|
    t.integer "book_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.string "value", null: false
    t.index ["book_id", "kind", "value"], name: "index_book_identifiers_on_book_id_and_kind_and_value", unique: true
    t.index ["book_id"], name: "index_book_identifiers_on_book_id"
    t.index ["kind", "value"], name: "index_book_identifiers_on_kind_and_value"
  end

  create_table "book_tags", force: :cascade do |t|
    t.integer "book_id", null: false
    t.integer "tag_id", null: false
    t.index ["book_id", "tag_id"], name: "index_book_tags_on_book_id_and_tag_id", unique: true
    t.index ["book_id"], name: "index_book_tags_on_book_id"
    t.index ["tag_id"], name: "index_book_tags_on_tag_id"
  end

  create_table "books", force: :cascade do |t|
    t.datetime "added_at"
    t.integer "calibre_id", null: false
    t.string "cover_path"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "file_format"
    t.string "file_name"
    t.datetime "imported_at", null: false
    t.datetime "last_modified"
    t.string "path", null: false
    t.datetime "pubdate"
    t.integer "publisher_id"
    t.integer "series_id"
    t.decimal "series_index", precision: 10, scale: 2
    t.string "sort_title"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["added_at"], name: "index_books_on_added_at"
    t.index ["calibre_id"], name: "index_books_on_calibre_id", unique: true
    t.index ["publisher_id"], name: "index_books_on_publisher_id"
    t.index ["series_id"], name: "index_books_on_series_id"
    t.index ["title"], name: "index_books_on_title"
    t.index ["uuid"], name: "index_books_on_uuid"
  end

  create_table "publishers", force: :cascade do |t|
    t.integer "calibre_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "sort_name"
    t.datetime "updated_at", null: false
    t.index ["calibre_id"], name: "index_publishers_on_calibre_id", unique: true
    t.index ["name"], name: "index_publishers_on_name"
  end

  create_table "series", force: :cascade do |t|
    t.integer "calibre_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "sort_name"
    t.datetime "updated_at", null: false
    t.index ["calibre_id"], name: "index_series_on_calibre_id", unique: true
    t.index ["name"], name: "index_series_on_name"
  end

  create_table "tags", force: :cascade do |t|
    t.integer "calibre_id"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["calibre_id"], name: "index_tags_on_calibre_id", unique: true
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "book_authors", "authors"
  add_foreign_key "book_authors", "books"
  add_foreign_key "book_identifiers", "books"
  add_foreign_key "book_tags", "books"
  add_foreign_key "book_tags", "tags"
  add_foreign_key "books", "publishers"
  add_foreign_key "books", "series"
end
