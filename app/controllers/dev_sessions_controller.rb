class DevSessionsController < ApplicationController
  skip_before_action :require_authentication
  before_action :ensure_development!

  def new
    @existing_users = User.order(:name)
  end

  def create
    username = params[:as].to_s.strip.presence || "alex"
    user = User.find_or_provision_from_proxy(
      username: username,
      email:    "#{username}@dev.local",
      name:     username.titleize,
    )
    session[:dev_user_id] = user.id
    redirect_to root_path, notice: "Dev sign-in as #{user.display_name} (#{user.role})"
  end

  private

  def ensure_development!
    raise ActionController::RoutingError, "Not Found" unless Rails.env.development?
  end
end
