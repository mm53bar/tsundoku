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

    # Status transition rules from design doc §6. The device is
    # authoritative for transitions seen during active reading, but we
    # preserve Tsundoku-local nuances where they don't contradict.
    def apply_status(reading, status_info)
      return unless status_info && status_info["Status"]

      new_status = Reading.tsundoku_status_for(status_info["Status"])
      return unless new_status

      old_status = reading.status
      reading.status = new_status

      case new_status
      when "currently_reading"
        reading.started_at ||= Time.current
        # Re-reading case: device says Reading on a previously-finished book.
        reading.finished_at = nil if old_status == "read"
      when "read"
        reading.finished_at ||= Time.current
      end
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
      reading.spent_reading_minutes = stats["SpentReadingMinutes"] if stats["SpentReadingMinutes"].present?
    end
  end
end
