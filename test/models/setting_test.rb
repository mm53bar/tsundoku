require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "current returns a singleton row, creating it exactly once" do
    assert_equal 0, Setting.count
    first  = Setting.current
    second = Setting.current
    assert_equal first.id, second.id
    assert_equal 1, Setting.count
  end

  test "effective_shelfmark_url prefers the stored value" do
    Setting.current.update!(shelfmark_url: "https://db.example.com")
    with_env("SHELFMARK_URL", "https://env.example.com") do
      assert_equal "https://db.example.com", Setting.current.effective_shelfmark_url
    end
  end

  test "effective_shelfmark_url falls back to the env var when blank" do
    Setting.current.update!(shelfmark_url: "")
    with_env("SHELFMARK_URL", "https://env.example.com") do
      assert_equal "https://env.example.com", Setting.current.effective_shelfmark_url
    end
  end

  test "effective_authelia_logout_url falls back to the env var when blank" do
    Setting.current.update!(authelia_logout_url: nil)
    with_env("AUTHELIA_LOGOUT_URL", "https://auth.example.com/logout") do
      assert_equal "https://auth.example.com/logout", Setting.current.effective_authelia_logout_url
    end
  end

  test "effective values are nil when neither stored nor env is set" do
    with_env("SHELFMARK_URL", nil) do
      with_env("AUTHELIA_LOGOUT_URL", nil) do
        assert_nil Setting.current.effective_shelfmark_url
        assert_nil Setting.current.effective_authelia_logout_url
      end
    end
  end

  private

  def with_env(key, value)
    original = ENV[key]
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    original.nil? ? ENV.delete(key) : ENV[key] = original
  end
end
