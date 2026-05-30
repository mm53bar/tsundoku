class Reading < ApplicationRecord
  belongs_to :user
  # touch: true so a progress or sync change in Tsundoku bumps
  # book.updated_at, triggering ChangedEntitlement in the next Kobo
  # sync diff so the device picks up the new state.
  belongs_to :book, touch: true

  validates :user_id, uniqueness: { scope: :book_id }

  # The threshold above which a book is considered finished. The Kobo
  # itself never reports exactly 100% — its calculation rounds — so
  # treating "near the end" as done is more honest than insisting on
  # the literal value.
  FINISHED_THRESHOLD_PCT = 95

  # Tsundoku derived state → Kobo wire format. Kobo's protocol uses
  # ReadyToRead / Reading / Finished. Our derivation produces the
  # corresponding symbol; this table is the one place that converts.
  KOBO_STATUS = {
    not_started: "ReadyToRead",
    in_progress: "Reading",
    finished:    "Finished"
  }.freeze

  # SQL scopes mirror the Ruby derivation in progress_state so callers
  # can query without loading rows into Ruby. Keep these in sync with
  # the method below — both reference FINISHED_THRESHOLD_PCT so the
  # boundary lives in one place.
  scope :in_progress, -> {
    where(finished_at: nil)
      .where("progress_percent > 0 AND progress_percent < ?", FINISHED_THRESHOLD_PCT)
  }

  scope :finished, -> {
    where("finished_at IS NOT NULL OR progress_percent >= ?", FINISHED_THRESHOLD_PCT)
  }

  scope :not_started, -> {
    where(finished_at: nil)
      .where("progress_percent = 0 OR progress_percent IS NULL")
  }

  before_save :stamp_progress_timestamps, if: :progress_percent_changed?

  # Maintain users.in_progress_reading_count via delta updates so the
  # navbar pill renders without a COUNT query on every page load. The
  # state machine compares the previous and current in_progress?
  # values via dirty tracking; mismatches issue a +1 / -1
  # update_counters call.
  after_save    :adjust_user_in_progress_counter, if: :in_progress_relevant_change?
  after_destroy :decrement_user_in_progress_counter_if_was_in_progress

  # Derived progress state. Progress data is the source of truth;
  # status is just a label for it.
  def progress_state
    return :finished    if finished_at.present? || (progress_percent || 0) >= FINISHED_THRESHOLD_PCT
    return :in_progress if (progress_percent || 0).positive?
    :not_started
  end

  def finished?    ; progress_state == :finished    end
  def in_progress? ; progress_state == :in_progress end
  def not_started? ; progress_state == :not_started end

  def kobo_status
    KOBO_STATUS.fetch(progress_state)
  end

  # Display label for the UI, mapping derived state to friendly text.
  def status_label
    { not_started: "Not started", in_progress: "Reading", finished: "Finished" }.fetch(progress_state)
  end

  # Wire format for the device. Used in both the sync response (inline
  # inside an entitlement) and the standalone /v1/library/:uuid/state
  # endpoint. The book param is passed in so callers can avoid an extra
  # load when they already have the Book in hand.
  def kobo_state_payload(book = self.book)
    iso = (updated_at || Time.current).iso8601

    payload = {
      "EntitlementId"     => book.kobo_uuid,
      "Created"           => (created_at || Time.current).iso8601,
      "LastModified"      => iso,
      "PriorityTimestamp" => iso,
      "StatusInfo" => {
        "LastModified"        => iso,
        "Status"              => kobo_status,
        "TimesStartedReading" => started_at ? 1 : 0
      }.compact,
      "Statistics" => {
        "LastModified" => iso
      }.tap { |s| s["SpentReadingMinutes"] = spent_reading_minutes if spent_reading_minutes.present? },
      "CurrentBookmark" => current_bookmark_payload(iso)
    }
    payload["StatusInfo"]["LastTimeStartedReading"] = started_at.iso8601 if started_at.present?
    payload
  end

  private

  # Was the row in_progress immediately before the just-completed save?
  # Uses dirty tracking to reconstruct the previous values of the two
  # fields that determine in_progress? state.
  def was_in_progress?
    prev_pct      = saved_change_to_progress_percent? ? saved_change_to_progress_percent.first.to_i : (progress_percent || 0).to_i
    prev_finished = saved_change_to_finished_at?      ? saved_change_to_finished_at.first           : finished_at

    return false if prev_finished.present?
    return false if prev_pct >= FINISHED_THRESHOLD_PCT
    prev_pct.positive?
  end

  def in_progress_relevant_change?
    saved_change_to_progress_percent? || saved_change_to_finished_at?
  end

  def adjust_user_in_progress_counter
    was = was_in_progress?
    is  = in_progress?
    return if was == is

    User.where(id: user_id).update_counters(in_progress_reading_count: is ? 1 : -1)
  end

  def decrement_user_in_progress_counter_if_was_in_progress
    return unless in_progress?
    User.where(id: user_id).update_counters(in_progress_reading_count: -1)
  end

  # Whenever progress_percent changes, derive the timestamps:
  #   - started_at gets set the first time progress goes positive
  #   - finished_at gets set when progress crosses the threshold
  #   - finished_at clears on a re-read (progress drops back below the
  #     threshold), so the user appears in-progress again
  def stamp_progress_timestamps
    pct     = (progress_percent || 0).to_i
    old_pct = (progress_percent_was || 0).to_i

    self.started_at  ||= Time.current if pct.positive?
    self.finished_at ||= Time.current if pct >= FINISHED_THRESHOLD_PCT

    if old_pct >= FINISHED_THRESHOLD_PCT && pct < FINISHED_THRESHOLD_PCT
      self.finished_at = nil
    end
  end

  def current_bookmark_payload(iso)
    bm = { "LastModified" => iso }
    bm["ProgressPercent"]               = progress_percent if progress_percent.present?
    bm["ContentSourceProgressPercent"]  = progress_percent if progress_percent.present?
    if location_value.present?
      bm["Location"] = {
        "Value"  => location_value,
        "Type"   => location_type,
        "Source" => location_source
      }.compact
    end
    bm
  end
end
