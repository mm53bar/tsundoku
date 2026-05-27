class AddEnrichmentToBooks < ActiveRecord::Migration[8.1]
  def change
    add_column :books, :enriched_cover_path, :string
    add_column :books, :last_enriched_at, :datetime
    add_index :books, :last_enriched_at
  end
end
