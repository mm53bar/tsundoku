class AddKoboHandleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :kobo_handle, :string
    add_index :users, :kobo_handle, unique: true
  end
end
