class Reading < ApplicationRecord
  belongs_to :user
  # touch: true so a reading-status change in Tsundoku bumps book.updated_at,
  # triggering ChangedEntitlement in the next Kobo sync diff so the device
  # picks up the new state.
  belongs_to :book, touch: true

  enum :status, {
    want_to_read:      0,
    currently_reading: 1,
    read:              2
  }, validate: true

  # Tsundoku status ↔ Kobo status. Matches design doc §6 (one-to-one
  # after we collapsed paused/did_not_finish in earlier work). Note that
  # status is now a *progress* signal, not a sync signal — sync intent
  # lives in the dedicated sync_to_device column.
  KOBO_STATUS_MAP = {
    "want_to_read"      => "ReadyToRead",
    "currently_reading" => "Reading",
    "read"              => "Finished"
  }.freeze

  validates :user_id, uniqueness: { scope: :book_id }

  # Transitional bridge: until the UI exposes the sync toggle separately,
  # status changes still drive sync_to_device using the legacy mapping
  # (want_to_read / currently_reading → sync; read → don't sync). Explicit
  # sync_to_device assignments win — when the toggle UI lands, callers
  # that set both fields aren't overridden by this.
  before_save :default_sync_to_device_from_status

  def kobo_status
    KOBO_STATUS_MAP[status] || "ReadyToRead"
  end

  def self.tsundoku_status_for(kobo_status)
    KOBO_STATUS_MAP.invert[kobo_status]
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

  def self.status_label(status)
    {
      "want_to_read"      => "Want to Read",
      "currently_reading" => "Currently Reading",
      "read"              => "Read"
    }[status.to_s]
  end

  private

  def default_sync_to_device_from_status
    # Skip if the caller has explicitly assigned sync_to_device — they're
    # opting out of the legacy mapping. Otherwise apply the mapping on
    # creation (when status_changed? is false for default values) and
    # whenever status changes thereafter.
    return if sync_to_device_changed?
    return unless new_record? || status_changed?
    self.sync_to_device = %w[want_to_read currently_reading].include?(status)
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
