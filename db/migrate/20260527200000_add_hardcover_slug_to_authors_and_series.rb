class AddHardcoverSlugToAuthorsAndSeries < ActiveRecord::Migration[8.1]
  def change
    add_column :authors, :hardcover_slug, :string
    add_index :authors, :hardcover_slug
    add_column :series, :hardcover_slug, :string
    add_index :series, :hardcover_slug
  end
end
