class ReadingsController < ApplicationController
  before_action :set_book

  # PATCH /books/:book_id/reading
  #
  #   reading[mark_finished] = "1" | "0"
  #       Manually stamp / clear finished_at. "1" forces progress to
  #       100% and finished_at = now. "0" clears finished_at so the
  #       book reads as in_progress or not_started again (whichever
  #       the current progress_percent encodes).
  #
  # Sync intent used to be controlled here via reading[sync_to_device];
  # that path was retired in favor of the star icon driving the
  # default-for-star shelf. The mark_finished controls remain.
  def update
    reading = current_user.readings.find_or_initialize_by(book: @book)

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
