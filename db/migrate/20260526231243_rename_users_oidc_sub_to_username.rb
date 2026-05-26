class RenameUsersOidcSubToUsername < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :oidc_sub, :username
  end
end
