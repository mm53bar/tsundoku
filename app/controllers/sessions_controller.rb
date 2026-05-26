class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:destroy]

  def destroy
    reset_session
    if (logout_url = ENV["AUTHELIA_LOGOUT_URL"]).present?
      redirect_to logout_url, allow_other_host: true
    else
      redirect_to root_path, notice: "Signed out"
    end
  end
end
