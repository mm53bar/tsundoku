class AddOwnershipAndSharingToLists < ActiveRecord::Migration[8.1]
  # Lists become per-user (owner) with an opt-in "share with others"
  # flag. Existing rows are assigned to the first user (the operator,
  # by virtue of the first-user-becomes-admin provisioning convention)
  # and marked shared so prior behavior — every household member could
  # see every list — survives the migration.
  def change
    add_reference :lists, :user, foreign_key: true
    add_column    :lists, :shared, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        first_user_id = execute("SELECT id FROM users ORDER BY id LIMIT 1").first&.values&.first
        if first_user_id
          execute "UPDATE lists SET user_id = #{first_user_id.to_i} WHERE user_id IS NULL"
          execute "UPDATE lists SET shared = 1"
        end
      end
    end

    change_column_null :lists, :user_id, false
  end
end
