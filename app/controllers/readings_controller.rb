class ReadingsController < ApplicationController
  before_action :set_book

  # PATCH /books/:book_id/reading
  # Drives the three controls on the status_picker partial:
  #
  #   reading[sync_to_device] = "true" | "false"
  #       Flip the Kobo sync intent. Creating a Reading is a side
  #       effect of toggling sync on for a book that has none yet.
  #
  #   reading[mark_finished] = "1" | "0"
  #       Manually stamp / clear finished_at. "1" forces progress to
  #       100% and finished_at = now. "0" clears finished_at so the
  #       book reads as in_progress or not_started again (whichever
  #       the current progress_percent encodes).
  #
  # Both can be present; sync flips before status mark so a single
  # request could in principle do both.
  def update
    reading = current_user.readings.find_or_initialize_by(book: @book)

    apply_sync_flag(reading)
    apply_finished_mark(reading)

    reading.save! if reading.changed? || reading.new_record?
    @reading = reading.persisted? ? reading : nil

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @book }
    end
  end

  # DELETE /books/:book_id/reading
  # Remove the user's Reading record entirely. The book drops out of
  # this user's syncable set on next sync — the existing
  # removed_book_records path in Kobo::SyncController emits a
  # tombstone for the device.
  def destroy
    current_user.readings.where(book: @book).destroy_all
    @reading = nil

    respond_to do |format|
      format.turbo_stream { render :update }
      format.html         { redirect_to @book }
    end
  end

  private

  def set_book
    @book = Book.find(params[:book_id])
  end

  def apply_sync_flag(reading)
    return unless params.dig(:reading)&.key?(:sync_to_device)
    reading.sync_to_device = ActiveModel::Type::Boolean.new.cast(params[:reading][:sync_to_device])
  end

  def apply_finished_mark(reading)
    case params.dig(:reading, :mark_finished)
    when "1"
      # Force the finished state explicitly. The before_save callback
      # on Reading also stamps finished_at when progress crosses the
      # threshold, but a user clicking "Mark as finished" may not have
      # any progress recorded yet (paper read, side-loaded read, etc.).
      reading.progress_percent = 100
      reading.finished_at      = Time.current
    when "0"
      # Clear the finished stamp. Don't touch progress_percent — the
      # device's last-known reading position stays as the truthful
      # data. The next sync may reset it as the user opens the book.
      reading.finished_at = nil
    end
  end
end
