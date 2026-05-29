class AddKoboUuidToKoboSyncedBooks < ActiveRecord::Migration[8.1]
  def change
    # Denormalized snapshot of the book's kobo_uuid so we can emit a
    # tombstone (ChangedEntitlement IsRemoved=true) after the book row
    # has been destroyed. Mirrors the same pattern on kobo_synced_shelves.
    add_column :kobo_synced_books, :kobo_uuid, :string
    add_index  :kobo_synced_books, :kobo_uuid

    # Backfill from the currently-associated book before the new NOT NULL
    # constraint goes on. Raw SQL because model code in migrations is
    # fragile across schema versions.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE kobo_synced_books
          SET kobo_uuid = (
            SELECT books.kobo_uuid
            FROM   books
            WHERE  books.id = kobo_synced_books.book_id
          )
          WHERE kobo_uuid IS NULL
        SQL
      end
    end

    change_column_null :kobo_synced_books, :kobo_uuid, false

    # Book.destroy will nullify book_id on these rows (dependent: :nullify)
    # so the row survives — with kobo_uuid intact — until the next sync
    # emits the tombstone and the existing destroy_all path cleans it up.
    change_column_null :kobo_synced_books, :book_id, true
  end
end
