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

    # Secrets (master.key + credentials.yml.enc) can live in a single
    # bind-mounted directory, config/secrets/, so they stay out of the published
    # image and `rails credentials:edit` persists across container recreation.
    # content_path/key_path take a single path (no built-in fallback list), so
    # we probe: use config/secrets/ when it's populated (production/Docker),
    # otherwise leave Rails' conventional config/ location (local dev).
    secrets_dir = Rails.root.join("config/secrets")
    if secrets_dir.directory? && (secrets_dir.join("credentials.yml.enc").exist? || secrets_dir.join("master.key").exist?)
      config.credentials.content_path = secrets_dir.join("credentials.yml.enc")
      config.credentials.key_path     = secrets_dir.join("master.key")
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = ENV.fetch("TZ", "UTC")

    config.x.library_path = ENV.fetch("LIBRARY_PATH") { Rails.root.join("storage/library_dev").to_s }
    config.x.ingest_path  = ENV.fetch("INGEST_PATH")  { Rails.root.join("storage/ingest_dev").to_s }

    # Shelfmark base URL (e.g. https://shelfmark.example.com). When set,
    # ShelfmarkHelper renders "Find via Shelfmark" links on surfaces that
    # show books not in the local library (unmatched list entries,
    # Hardcover "more by author" / "more in series" thumbs). Shelfmark
    # downloads land in INGEST_PATH and AutoIngestScanJob picks them up.
    # Unset → no links rendered.
    config.x.shelfmark_url = ENV.fetch("SHELFMARK_URL", nil)

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
