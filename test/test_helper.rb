ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  # Forward-auth: the upstream proxy injects Remote-User to identify the
  # signed-in user (see docs/adr/20260530-proxy-auth-trust-model.md). Tests
  # authenticate the same way — splat the result into a request's `headers:`:
  #   get some_path, headers: headers_for(users(:admin))
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end
end
