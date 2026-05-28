class CreateReadings < ActiveRecord::Migration[8.1]
  def change
    create_table :readings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    # One Reading record per user per book — status is the canonical
    # "where am I with this book" state.
    add_index :readings, [ :user_id, :book_id ], unique: true
    add_index :readings, :status
  end
end
