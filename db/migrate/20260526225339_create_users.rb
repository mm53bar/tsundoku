class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :oidc_sub, null: false
      t.string :email
      t.string :name
      t.integer :role, null: false, default: 0

      t.timestamps
    end
    add_index :users, :oidc_sub, unique: true
  end
end
