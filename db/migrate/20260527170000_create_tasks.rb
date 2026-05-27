class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.string :kind, null: false
      t.references :subject, polymorphic: true, null: true
      t.integer :status, default: 0, null: false
      t.integer :progress_current, default: 0, null: false
      t.integer :progress_total
      t.integer :attempts, default: 0, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.json :result
      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :kind
    add_index :tasks, :finished_at
  end
end
