class SettingsController < ApplicationController
  before_action :require_settings_access

  def show
    @setting = Setting.current
  end

  def update
    @setting = Setting.current
    if @setting.update(setting_params)
      redirect_to settings_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  # Passive predicate today (every signed-in household member is trusted —
  # see docs/architecture-principles.md §3). The check exists so a future,
  # less-trusted deployment can restrict settings editing in one place.
  def require_settings_access
    redirect_to root_path, alert: "You can't edit settings." unless current_user&.can_edit_settings?
  end

  def setting_params
    params.require(:setting).permit(:shelfmark_url, :authelia_logout_url)
  end
end
