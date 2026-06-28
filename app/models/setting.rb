class Setting < ApplicationRecord
  # The app has exactly one settings row. `Setting.current` returns it,
  # creating it on first access — call sites should always go through
  # `Setting.current` rather than querying Setting directly.
  def self.current
    first_or_create!
  end

  # Effective values fall back to the legacy environment variables when the
  # stored value is blank, so existing env-based deployments keep working
  # until an operator saves values here. Once set in the UI, SHELFMARK_URL /
  # AUTHELIA_LOGOUT_URL can be dropped from the deployment.
  def effective_shelfmark_url
    shelfmark_url.presence || ENV["SHELFMARK_URL"].presence
  end

  def effective_authelia_logout_url
    authelia_logout_url.presence || ENV["AUTHELIA_LOGOUT_URL"].presence
  end
end
