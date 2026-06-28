class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :shelfmark_url
      t.string :authelia_logout_url

      t.timestamps
    end
  end
end
