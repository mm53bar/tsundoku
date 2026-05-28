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
  end
end
