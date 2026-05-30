module Kobo
  # Reading state endpoints. The device GETs to check a book's current
  # state and PUTs to push progress / status transitions. Mapping rules
  # follow design doc §6: Kobo is authoritative for transitions during
  # active reading; Tsundoku's local state nuances are preserved on the
  # round-trip.
  class ReadingStatesController < BaseController
    # GET /kobo/:handle/v1/library/:book_uuid/state
    def show
      book = find_book_by_kobo_uuid(params[:book_uuid])
      return head :not_found unless book

      reading = @kobo_user.readings.find_or_initialize_by(book: book)
      render json: [ reading.kobo_state_payload(book) ]
    end

    # PUT /kobo/:handle/v1/library/:book_uuid/state
    def update
      book = find_book_by_kobo_uuid(params[:book_uuid])
      return head :not_found unless book

      states = Array(params[:ReadingStates])
      states.each { |state| apply_state(book, state) }

      render json: {
        "RequestResult" => "Success",
        "UpdateResults" => states.map do
          {
            "EntitlementId"         => book.kobo_uuid,
            "StatusInfoResult"      => { "Result" => "Success" },
            "CurrentBookmarkResult" => { "Result" => "Success" },
            "StatisticsResult"      => { "Result" => "Success" },
            "LastModified"          => Time.current.iso8601,
            "PriorityTimestamp"     => Time.current.iso8601
          }
        end
      }
    end

    private

    def apply_state(book, state)
      reading = @kobo_user.readings.find_or_initialize_by(book: book)

      apply_status(reading, state["StatusInfo"])
      apply_bookmark(reading, state["CurrentBookmark"])
      apply_stats(reading, state["Statistics"])

      reading.kobo_synced_at = Time.current
      reading.save!
    end

    # The Kobo's Status field is informational — our progress_state is
    # derived from progress_percent + finished_at. We mostly ignore the
    # value except for one case worth catching:
    #   * Long-pressing a book on the device and tapping "Mark as
    #     finished" sends Status="Finished" without touching progress.
    #     Stamp finished_at so the book derives correctly on our side.
    # Re-read transitions (device reports Reading after a previously-
    # finished book) are handled by the Reading model's
    # stamp_progress_timestamps callback when progress drops back
    # below the threshold.
    def apply_status(reading, status_info)
      return unless status_info && status_info["Status"] == "Finished"
      reading.finished_at      ||= Time.current
      reading.progress_percent   = 100 if (reading.progress_percent || 0) < Reading::FINISHED_THRESHOLD_PCT
    end

    def apply_bookmark(reading, bookmark)
      return unless bookmark

      reading.progress_percent = bookmark["ProgressPercent"] if bookmark.key?("ProgressPercent")
      if (loc = bookmark["Location"])
        reading.location_value  = loc["Value"]
        reading.location_type   = loc["Type"]
        reading.location_source = loc["Source"]
      end
    end

    def apply_stats(reading, stats)
      return unless stats
      reading.spent_reading_minutes     = stats["SpentReadingMinutes"]     if stats["SpentReadingMinutes"].present?
      reading.remaining_time_minutes    = stats["RemainingTimeMinutes"]    if stats["RemainingTimeMinutes"].present?
    end
  end
end
