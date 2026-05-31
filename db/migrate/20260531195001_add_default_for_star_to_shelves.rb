class AddDefaultForStarToShelves < ActiveRecord::Migration[8.1]
  # Flags the per-user "Starred" shelf. Two effects:
  #   - it's the target of the star icon on book cards (single-click
  #     quick toggle for "I want this on my Kobo")
  #   - it's exempt from Kobo Tag emission so it doesn't manifest as a
  #     redundant collection on the device (the Kobo's "My Books"
  #     already covers "everything on the device")
  #
  # Constraints enforced at the model level (not the schema):
  #   - one default_for_star shelf per user
  #   - cannot be destroyed (Shelf#before_destroy guard)
  #   - sync_to_kobo locked true while default_for_star is true
  def change
    add_column :shelves, :default_for_star, :boolean, default: false, null: false
    add_index  :shelves, [ :user_id, :default_for_star ],
               unique: true,
               where:  "default_for_star = 1",
               name:   "index_shelves_default_for_star_per_user"
  end
end
