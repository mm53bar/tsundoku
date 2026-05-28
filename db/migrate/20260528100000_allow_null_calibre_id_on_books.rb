class AllowNullCalibreIdOnBooks < ActiveRecord::Migration[8.1]
  def change
    # Ingested books come from /ingest with no Calibre origin, so calibre_id
    # needs to be optional. The unique index on calibre_id already excludes
    # NULL (SQLite's default for unique indexes), so multiple ingested books
    # without a calibre_id won't collide.
    change_column_null :books, :calibre_id, true
  end
end
