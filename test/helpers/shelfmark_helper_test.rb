require "test_helper"

class ShelfmarkHelperTest < ActionView::TestCase
  setup do
    Setting.current.update!(shelfmark_url: "https://shelfmark.example.com")
  end

  # shelfmark_search_url — the URL builder. Pins the param shape Shelfmark
  # expects (calibrain/shelfmark parseUrlSearchParams.ts) so a future
  # refactor doesn't silently drop a query field.

  test "returns nil when the Shelfmark URL is unset" do
    Setting.current.update!(shelfmark_url: nil)
    with_env("SHELFMARK_URL", nil) do
      assert_nil shelfmark_search_url(title: "Anything")
    end
  end

  test "returns nil when the Shelfmark URL is blank" do
    Setting.current.update!(shelfmark_url: "")
    with_env("SHELFMARK_URL", nil) do
      assert_nil shelfmark_search_url(title: "Anything")
    end
  end

  test "returns nil when title is blank" do
    assert_nil shelfmark_search_url(title: nil)
    assert_nil shelfmark_search_url(title: "")
  end

  test "builds a URL with title and content_type" do
    url = shelfmark_search_url(title: "Dune")
    assert_includes url, "https://shelfmark.example.com/?"
    assert_includes url, "title=Dune"
    assert_includes url, "content_type=ebook"
    refute_includes url, "author="
    refute_includes url, "isbn="
  end

  test "includes author when supplied" do
    url = shelfmark_search_url(title: "Dune", author: "Frank Herbert")
    assert_includes url, "author=Frank+Herbert"
  end

  test "includes isbn when supplied" do
    url = shelfmark_search_url(title: "Dune", isbn: "9780441013593")
    assert_includes url, "isbn=9780441013593"
  end

  test "URL-encodes special characters in title and author" do
    url = shelfmark_search_url(title: "A&B: The Story", author: "O'Brien, Tim")
    assert_includes url, "title=A%26B%3A+The+Story"
    assert_includes url, "author=O%27Brien%2C+Tim"
  end

  test "strips a single trailing slash from the configured base URL" do
    Setting.current.update!(shelfmark_url: "https://shelfmark.example.com/")
    url = shelfmark_search_url(title: "Dune")
    assert_includes url, "https://shelfmark.example.com/?"
    refute_includes url, "//?"
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
