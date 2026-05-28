class AddKoboUuidToBooksAndShelves < ActiveRecord::Migration[8.1]
  # Hoist Book/Shelf reverse-lookup from O(n) Ruby scan + per-row v5
  # computation to a single indexed DB query. Backfill existing rows
  # with their previously-computed deterministic UUIDs so the Kobo's
  # cached entitlements continue to match.
  BOOK_NS  = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "tsundoku-kobo-books").freeze
  SHELF_NS = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "tsundoku-kobo-shelves").freeze

  def up
    add_column :books, :kobo_uuid, :string
    Book.reset_column_information
    Book.where(kobo_uuid: nil).find_each do |b|
      b.update_columns(kobo_uuid: Digest::UUID.uuid_v5(BOOK_NS, b.id.to_s))
    end
    add_index :books, :kobo_uuid, unique: true

    add_column :shelves, :kobo_uuid, :string
    Shelf.reset_column_information
    Shelf.where(kobo_uuid: nil).find_each do |s|
      s.update_columns(kobo_uuid: Digest::UUID.uuid_v5(SHELF_NS, s.id.to_s))
    end
    add_index :shelves, :kobo_uuid, unique: true
  end

  def down
    remove_index  :books,   :kobo_uuid
    remove_column :books,   :kobo_uuid
    remove_index  :shelves, :kobo_uuid
    remove_column :shelves, :kobo_uuid
  end
end
