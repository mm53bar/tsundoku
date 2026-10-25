class AddResolutionToListEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :list_entries, :hardcover_book_id, :integer
    add_column :list_entries, :resolved_title, :string
    add_column :list_entries, :resolved_author, :string
    add_column :list_entries, :release_year, :integer
    add_column :list_entries, :cover_url, :string
    add_column :list_entries, :resolution_status, :string
    add_column :list_entries, :resolution_candidates, :json
  end
end
