require "test_helper"

# End-to-end smoke tests over the real Rack stack (no browser). These cover the
# app's load-bearing entry paths — the proxy-auth boundary, first-user
# provisioning, and that the library index renders — cheaply and
# deterministically. Feature behavior lives in the per-controller integration
# tests; genuinely-JS surfaces (Turbo/Stimulus) are manual-tested for now.
# See docs/adr/20260803-integration-tests-over-system-tests.md.
class SmokeTest < ActionDispatch::IntegrationTest
  test "unauthenticated requests are rejected at the proxy-auth boundary" do
    get root_path
    assert_response :unauthorized
  end

  test "first proxy user is provisioned admin, subsequent users are readers" do
    User.destroy_all

    get root_path, headers: { "HTTP_REMOTE_USER" => "firstie" }
    assert User.find_by(username: "firstie")&.admin?, "first provisioned user should be admin"

    get root_path, headers: { "HTTP_REMOTE_USER" => "secondie" }
    assert User.find_by(username: "secondie")&.reader?, "subsequent users should be readers"
  end

  test "a signed-in user sees the library index with the book grid" do
    Book.create!(title: "Smoke Signal", path: "smoke", file_name: "smoke",
                 file_format: "EPUB", imported_at: Time.current, added_at: Time.current)

    get root_path, headers: headers_for(users(:admin))

    assert_response :success
    assert_select "div.grid" # the cover grid container
    assert_includes response.body, "Smoke Signal" # the book rendered into it
  end
end
