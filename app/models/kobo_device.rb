class KoboDevice < ApplicationRecord
  belongs_to :user

  validates :serial_number, presence: true, uniqueness: { scope: :user_id }

  scope :recently_seen, -> { order(last_seen_at: :desc) }

  # Pulls device telemetry out of an analytics POST and upserts a device
  # record. Only acts on requests carrying a UserMetadataUpdate event —
  # that's where the real device serial (`N4182B3181981` style) and rich
  # metadata live. Other endpoints (notably /v1/affiliate) also send a
  # "SerialNumber" parameter but use a 32-hex platform hash instead of
  # the actual serial, which would create a phantom second device row.
  def self.upsert_from_request(user:, params:)
    events = Array(params["Events"]).map { |e| e.respond_to?(:to_unsafe_h) ? e.to_unsafe_h : e }
    metadata_event = events.find { |e| e["EventType"] == "UserMetadataUpdate" }
    return nil unless metadata_event

    serial = params["SerialNumber"]
    return nil if serial.blank?

    m = metadata_event["Attributes"] || {}
    attrs = {
      last_seen_at:     Time.current,
      model:            m["DeviceModel"],
      firmware_version: metadata_event["ClientApplicationVersion"] || params["ApplicationVersion"],
      os_version:       m["OSVersion"]
    }.compact

    record = user.kobo_devices.find_or_initialize_by(serial_number: serial)
    record.assign_attributes(attrs)
    record.save!
    record
  end
end
