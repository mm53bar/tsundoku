class KoboSyncController < ApplicationController
  def show
    current_user.regenerate_kobo_handle! if current_user.kobo_handle.blank?
    @url     = kobo_sync_url_for(current_user)
    @devices = current_user.kobo_devices.recently_seen
  end

  def regenerate
    current_user.regenerate_kobo_handle!
    redirect_to kobo_sync_path, notice: "New Kobo URL generated. Update the api_endpoint in your Kobo's eReader.conf."
  end

  private

  def kobo_sync_url_for(user)
    "#{request.base_url}/kobo/#{user.kobo_handle}"
  end
end
