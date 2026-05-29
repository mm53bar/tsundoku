require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Tsundoku
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = ENV.fetch("TZ", "UTC")

    config.x.library_path = ENV.fetch("LIBRARY_PATH") { Rails.root.join("storage/library_dev").to_s }
    config.x.ingest_path  = ENV.fetch("INGEST_PATH")  { Rails.root.join("storage/ingest_dev").to_s }

    # Optional read-only bind mount of CWA's config directory (the same
    # one CWA itself uses at /config in its compose). When present, the
    # CWA migration rake tasks pick up app.db automatically without
    # needing a path argument.
    config.x.cwa_config_path = ENV.fetch("CWA_CONFIG_PATH", "/cwa-config")

    revision_file       = Rails.root.join("REVISION")
    revision_short_file = Rails.root.join("REVISION_SHORT")
    config.x.git_sha       = revision_file.exist?       ? revision_file.read.strip       : "dev"
    config.x.git_sha_short = revision_short_file.exist? ? revision_short_file.read.strip : "dev"
  end
end
