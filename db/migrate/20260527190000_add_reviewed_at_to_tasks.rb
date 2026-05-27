class AddReviewedAtToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :reviewed_at, :datetime
    add_index :tasks, :reviewed_at
    # Backfill existing tasks — anything succeeded/failed before this column
    # existed didn't have an explicit review step, so consider them reviewed.
    reversible do |dir|
      dir.up do
        execute "UPDATE tasks SET reviewed_at = finished_at WHERE finished_at IS NOT NULL"
      end
    end
  end
end
