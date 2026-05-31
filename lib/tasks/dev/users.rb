# frozen_string_literal: true

module Dev
  module Users
    class << self
      # Mike (admin) + Sheila (reader). Usernames match what /dev_login
      # expects — sign in as "mike" or "sheila" to drive the UI. Kobo
      # handles are stable so the device URLs don't churn between runs.
      def create_users
        # Tear down everything user-attached. The dev DB is disposable;
        # the production guard in dev.rake keeps this from running
        # outside development/test.
        User.destroy_all # cascades to readings, shelves, lists, kobo_*

        mike   = User.create!(username: "mike",   name: "Mike",   email: "mike@example.com",   role: :admin,  kobo_handle: "ocelot")
        sheila = User.create!(username: "sheila", name: "Sheila", email: "sheila@example.com", role: :reader, kobo_handle: "marigold")

        { mike: mike, sheila: sheila }
      end
    end
  end
end
