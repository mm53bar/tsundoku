class ReadingsController < ApplicationController
  before_action :set_book

  ALLOWED_STATUSES = Reading.statuses.keys.freeze

  def update
    status = params.dig(:reading, :status).to_s

    if status.blank? || status == "none"
      current_user.readings.where(book: @book).destroy_all
      @reading = nil
    elsif ALLOWED_STATUSES.include?(status)
      reading = current_user.readings.find_or_initialize_by(book: @book)
      previous_status = reading.persisted? ? reading.status : nil
      reading.status = status

      # Stamp transition timestamps lazily — only when entering the state
      # for the first time, never overwrite. Lets the user backdate later
      # via the edit form if they want.
      reading.started_at  ||= Time.current if status == "currently_reading"
      reading.finished_at ||= Time.current if %w[read did_not_finish].include?(status) && previous_status != status

      reading.save!
      @reading = reading
    else
      head :bad_request and return
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @book }
    end
  end

  private

  def set_book
    @book = Book.find(params[:book_id])
  end
end
