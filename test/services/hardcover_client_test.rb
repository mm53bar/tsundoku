require "test_helper"

class HardcoverClientTest < ActiveSupport::TestCase
  # Per the "external deps degrade gracefully" rule, every public method
  # returns nil/[] when the API token is unset or the input is blank.
  # The tests below pin that contract for the two new methods that
  # support the ISBN-less enrichment fallback — without them, a token-
  # less prod (or any caller passing a blank book id) could surface a
  # real HTTP error instead of a clean no-match.

  test "find_book_by_search returns nil when no API token is configured" do
    client = HardcoverClient.new(token: nil)
    assert_nil client.find_book_by_search(title: "Anything", author: "Someone")
  end

  test "find_book_by_search returns nil when title is blank" do
    client = HardcoverClient.new(token: "fake")
    assert_nil client.find_book_by_search(title: nil)
    assert_nil client.find_book_by_search(title: "")
    assert_nil client.find_book_by_search(title: "   ")
  end

  test "find_book_by_id returns nil when no API token is configured" do
    client = HardcoverClient.new(token: nil)
    assert_nil client.find_book_by_id(12345)
  end

  test "find_book_by_id returns nil when book_id is blank" do
    client = HardcoverClient.new(token: "fake")
    assert_nil client.find_book_by_id(nil)
    assert_nil client.find_book_by_id("")
  end

  # BOOK_PAYLOAD_GQL is shared between find_edition_by_isbn (nested
  # under edition.book) and find_book_by_id (top level). The shape must
  # carry the fields BookEnricher consumes — pin a few key ones so a
  # future trim of the selection set fails loudly here instead of
  # silently dropping enrichment data.

  test "BOOK_PAYLOAD_GQL includes the fields BookEnricher consumes" do
    payload = HardcoverClient::BOOK_PAYLOAD_GQL
    %w[
      id title subtitle slug headline description rating release_date
      cached_image default_cover_edition editions canonical contributions
      book_series
    ].each do |field|
      assert_includes payload, field, "Expected BOOK_PAYLOAD_GQL to select `#{field}`"
    end
  end
end
