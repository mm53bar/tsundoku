module Kobo
  # Parent for every /kobo/:handle/* endpoint. Authelia forward-auth is
  # bypassed at NPM for /kobo/* — the mnemonic handle in the URL identifies
  # the user, so we skip Rails' Authelia-header-based authentication and
  # look the user up directly.
  class BaseController < ApplicationController
    skip_before_action :require_authentication
    skip_forgery_protection
    before_action :set_kobo_user
    after_action  :capture_device_info, if: -> { @kobo_user.present? }

    # The device hits ~10 endpoints per sync that we don't implement and
    # which route to #fallback — analytics, deals, recommendations, wishlist,
    # nextread, etc. Each one logs Started/Processing/Completed at INFO,
    # drowning the meaningful sync/metadata/download lines. Raise the level
    # for the duration of those actions so the structured logs stay readable.
    around_action :quiet_fallback_logs, only: :fallback

    # GET /kobo/:handle
    # Top-level connectivity ping. The real Kobo store returns an empty
    # object here; we mirror that so device sync sees a normal "no work to
    # do at the root" response.
    def root
      render json: {}
    end

    # Catch-all for endpoints we don't implement (analytics, deals,
    # subscriptions, recommendations, etc.). The Kobo fires many of these
    # during sync; 404s cause sync to fail outright. Returning {} with 200
    # tells the device "nothing here, carry on" — same approach calibre-web
    # uses when its proxy mode is off. See design doc §4.1.
    def fallback
      render json: {}
    end

    private

    def set_kobo_user
      @kobo_user = User.find_by(kobo_handle: params[:handle])
      head :unauthorized unless @kobo_user
    end

    # Books the @kobo_user has opted to sync to their Kobo. The set
    # lives on User (books on any syncing shelf, including the
    # per-user Starred shelf the star icon drives); this method just
    # delegates so the device-facing sync set and the web-facing "On
    # your Kobo" navbar always agree on the same query.
    def syncable_books
      @kobo_user.on_kobo_books
    end

    # Indexed reverse lookup: kobo_uuid -> Book. Filtered to syncable
    # books so the device can only reference back to things it could
    # plausibly know about — anything else came from Kobo's store catalog.
    #
    # Orphan detection: if the UUID maps to a real Book that's just not
    # currently syncable, the device must have cached the entitlement
    # from an earlier sync (before KoboSyncedBook tracking existed, or
    # via some other gap). Track it so the next /v1/library/sync emits
    # IsRemoved and the device archives the ghost. Self-healing — no
    # one-shot backfill needed.
    def find_book_by_kobo_uuid(uuid)
      book = syncable_books.find_by(kobo_uuid: uuid)
      return book if book

      orphan = Book.find_by(kobo_uuid: uuid)
      @kobo_user.kobo_synced_books.find_or_create_by!(book: orphan) if orphan
      nil
    end

    # Indexed reverse lookup: kobo_uuid -> Shelf for this user.
    def find_shelf_by_kobo_uuid(uuid)
      @kobo_user.shelves.find_by(kobo_uuid: uuid)
    end

    # Opportunistically pulls device telemetry out of request params and
    # upserts a KoboDevice row. Failures are swallowed — capturing device
    # info must never break a sync response.
    def capture_device_info
      KoboDevice.upsert_from_request(user: @kobo_user, params: params)
    rescue StandardError => e
      Rails.logger.warn("KoboDevice capture failed: #{e.class}: #{e.message}")
    end

    def quiet_fallback_logs
      old_level = Rails.logger.level
      Rails.logger.level = Logger::WARN
      yield
    ensure
      Rails.logger.level = old_level
    end
  end
end
