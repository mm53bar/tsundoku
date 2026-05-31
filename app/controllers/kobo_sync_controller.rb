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

  # Wipes the per-user kobo_synced_books snapshot. The sync diff is
  # between syncable_books and that snapshot — if the device was
  # manually emptied, the books look stale to the device but Tsundoku
  # thinks it already sent them. This puts Tsundoku back at "I've
  # never synced anything to this user." Next device sync emits a
  # NewEntitlement for every book currently flagged for sync.
  #
  # CWA's equivalent ("Force full kobo sync" button on user_edit.html)
  # works the same way — see janeczku/calibre-web cps/admin.py
  # do_full_kobo_sync. Same pattern, same one-shot mechanism.
  def force_full_sync
    count = current_user.kobo_synced_books.delete_all
    redirect_to kobo_sync_path,
      notice: "Cleared #{count} sync #{'record'.pluralize(count)}. " \
              "Your next Kobo sync will re-send every book in your library that's flagged for the device."
  end

  private

  def kobo_sync_url_for(user)
    "#{request.base_url}/kobo/#{user.kobo_handle}"
  end
end
