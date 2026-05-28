module Kobo
  # Parent for every /kobo/:handle/* endpoint. Authelia forward-auth is
  # bypassed at NPM for /kobo/* — the mnemonic handle in the URL identifies
  # the user, so we skip Rails' Authelia-header-based authentication and
  # look the user up directly.
  class BaseController < ApplicationController
    skip_before_action :require_authentication
    skip_forgery_protection
    before_action :set_kobo_user

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

    # Books the @kobo_user has opted to sync to their Kobo. Union of two
    # signals (see ADR 20260528-shelf-wins-sync-conflict.md):
    #   - reading status in want_to_read / currently_reading
    #   - membership in a shelf with sync_to_kobo = true
    # Returns an ActiveRecord::Relation so callers can chain includes/limit.
    def syncable_books
      via_reading = @kobo_user.readings.where(status: Reading::SYNCABLE_STATUSES).select(:book_id)
      via_shelves = ShelfEntry.joins(:shelf).where(shelves: { user: @kobo_user, sync_to_kobo: true }).select(:book_id)
      Book.where(id: via_reading).or(Book.where(id: via_shelves))
    end
  end
end
