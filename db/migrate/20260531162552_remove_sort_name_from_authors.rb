class RemoveSortNameFromAuthors < ActiveRecord::Migration[8.1]
  # Authors are now found via search (library + authors index both
  # carry a substring filter) rather than scanned through a
  # surname-first alphabetical sort. Hardcover stores names as flat
  # strings; Tsundoku follows suit. Series and Publisher keep their
  # sort_name — those entities are browsed-by-list, not searched.
  def change
    remove_column :authors, :sort_name, :string
  end
end
