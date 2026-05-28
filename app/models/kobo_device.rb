class KoboDevice < ApplicationRecord
  belongs_to :user

  validates :serial_number, presence: true, uniqueness: { scope: :user_id }

  scope :recently_seen, -> { order(last_seen_at: :desc) }

  # Pulls the bits we care about out of an analytics or affiliate request's
  # parameters and upserts a device record for the given user. Tolerant of
  # missing fields — only updates what's actually present in the payload.
  def self.upsert_from_request(user:, params:)
    serial = params["SerialNumber"]
    return nil if serial.blank?

    events = Array(params["Events"]).map { |e| e.respond_to?(:to_unsafe_h) ? e.to_unsafe_h : e }
    metadata_event = events.find { |e| e["EventType"] == "UserMetadataUpdate" }

    attrs = { last_seen_at: Time.current }
    attrs[:firmware_version] = params["ApplicationVersion"] if params["ApplicationVersion"].present?

    if metadata_event
      m = metadata_event["Attributes"] || {}
      attrs[:model]            ||= m["DeviceModel"]
      attrs[:firmware_version] ||= metadata_event["ClientApplicationVersion"]
      attrs[:os_version]       ||= m["OSVersion"]
    end

    record = user.kobo_devices.find_or_initialize_by(serial_number: serial)
    record.assign_attributes(attrs.compact)
    record.save!
    record
  end
end
