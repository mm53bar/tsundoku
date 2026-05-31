class RemoveInProgressReadingCountFromUsers < ActiveRecord::Migration[8.1]
  # The counter cache was added to power a navbar "Reading (N)" pill
  # that has since been replaced by a live "On your Kobo (N)" count
  # (User#on_kobo_books). With no remaining caller, the column and its
  # Reading-callback maintenance cost are dead weight.
  def change
    remove_column :users, :in_progress_reading_count, :integer, default: 0, null: false
  end
end
