require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

  setup { @user = users(:admin) }

  test "show renders the settings form for a signed-in user" do
    get settings_path, headers: headers_for(@user)
    assert_response :success
    assert_select "form"
    assert_select "input[name=?]", "setting[shelfmark_url]"
    assert_select "input[name=?]", "setting[authelia_logout_url]"
  end

  test "update saves the settings" do
    patch settings_path,
          params: { setting: { shelfmark_url: "https://shelfmark.example.com",
                               authelia_logout_url: "https://auth.example.com/logout" } },
          headers: headers_for(@user)
    assert_redirected_to settings_path
    assert_equal "https://shelfmark.example.com", Setting.current.shelfmark_url
    assert_equal "https://auth.example.com/logout", Setting.current.authelia_logout_url
  end

  test "requires authentication" do
    get settings_path
    assert_response :unauthorized
  end
end
