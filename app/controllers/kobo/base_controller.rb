module Kobo
  # Parent for every /kobo/:handle/* endpoint. Authelia forward-auth is
  # bypassed at NPM for /kobo/* — the mnemonic handle in the URL identifies
  # the user, so we skip Rails' Authelia-header-based authentication and
  # look the user up directly.
  class BaseController < ApplicationController
    skip_before_action :require_authentication
    before_action :set_kobo_user

    # GET /kobo/:handle
    # Top-level connectivity ping. The real Kobo store returns an empty
    # object here; we mirror that so device sync sees a normal "no work to
    # do at the root" response.
    def root
      render json: {}
    end

    private

    def set_kobo_user
      @kobo_user = User.find_by(kobo_handle: params[:handle])
      head :unauthorized unless @kobo_user
    end
  end
end
