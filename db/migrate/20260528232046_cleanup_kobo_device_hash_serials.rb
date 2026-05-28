class CleanupKoboDeviceHashSerials < ActiveRecord::Migration[8.1]
  # The first version of KoboDevice.upsert_from_request created rows from
  # any endpoint carrying a SerialNumber param. The /v1/affiliate endpoint
  # uses a 32-hex platform-hash instead of the real device serial, which
  # showed up as a duplicate device on /kobo-sync. This deletes those
  # phantom rows; the next sync will repopulate the real-serial row.
  def up
    KoboDevice.where("LENGTH(serial_number) = 32").find_each do |device|
      device.destroy if device.serial_number.match?(/\A[0-9a-f]{32}\z/)
    end
  end

  def down
    # one-way — restoring phantom rows isn't useful
  end
end
