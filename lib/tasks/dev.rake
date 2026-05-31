# frozen_string_literal: true

# Sample data for the local development environment. Mirrors the pattern
# used at github.com/visio-media/elev8-central — entry rake + per-domain
# module files under lib/tasks/dev/. Guarded so the task doesn't get
# defined (and the dev/* files don't get required) in production.

if Rails.env.development? || Rails.env.test?
  Dir[Rails.root.join("lib/tasks/dev/*.rb")].each { |file| require file }

  namespace :dev do
    desc "Populate the local development DB with a realistic Tsundoku library + curation. Destroys existing rows for the touched models."
    task prime: :environment do
      abort "Refusing to run in #{Rails.env}" unless Rails.env.development? || Rails.env.test?

      ActiveRecord::Base.transaction do
        # Order matters — curation depends on the library which depends on users.
        users   = Dev::Users.create_users
        library = Dev::Library.create_library
        Dev::Curation.create_for(users[:sheila], library)
      end

      Rails.logger.silence do
        puts "dev:prime complete."
        puts "  Users:    #{User.count}"
        puts "  Authors:  #{Author.count} (#{Author.where.not(hardcover_slug: nil).count} with hardcover_slug)"
        puts "  Series:   #{Series.count}"
        puts "  Books:    #{Book.count}"
        puts "  Readings: #{Reading.count} (#{Reading.in_progress.count} in-progress, #{Reading.finished.count} finished)"
        puts "  Shelves:  #{Shelf.count} (#{Shelf.syncing.count} syncing to Kobo)"
        puts "  Lists:    #{List.count} (#{ListEntry.count} entries; #{ListEntry.where.not(book_id: nil).count} matched)"
      end
    end
  end
end
