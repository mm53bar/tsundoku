class SetupController < ApplicationController
  # One-time-ish onboarding actions. Linked from the user menu, and from
  # the library empty-state when the library has no books yet.
  #
  # No admin gate — per docs/architecture-principles.md §3, the homelab
  # trust model means any signed-in household member can run these.
  def show
    @library_empty              = !Book.exists?
    @calibre_db_available       = CalibreImporter.available?
    @calibre_import_in_progress = Task.active.where(kind: "calibre_import").exists?
    @cwa_db_available           = cwa_db_available?
  end

  private

  # The CWA bind mount sits at Rails.configuration.x.cwa_config_path
  # (default /cwa-config). If the operator wired up the volume per
  # README "Migrating from CWA", app.db will exist there.
  def cwa_db_available?
    File.exist?(File.join(Rails.configuration.x.cwa_config_path, "app.db"))
  end
end
