require "test_helper"

class BookIngesterTest < ActiveSupport::TestCase
  # attach_identifiers — handles OPF files that carry the same identifier
  # twice (different scheme tags that classify to the same kind, or a raw
  # and hyphenated ISBN that normalize to the same digits). ePubLibre is a
  # known offender. BookIdentifier has uniqueness on [book_id, kind,
  # value], so the implementation must dedupe rather than create twice.

  test "attach_identifiers de-duplicates identical (kind, value) pairs" do
    book = make_book

    BookIngester.new("/ignored").send(:attach_identifiers, book, [
      { kind: "uuid", value: "urn:uuid:abc-123" },
      { kind: "uuid", value: "urn:uuid:abc-123" },
      { kind: "isbn13", value: "9780000000001" }
    ])

    kinds = book.book_identifiers.pluck(:kind, :value).sort
    assert_equal [ [ "isbn13", "9780000000001" ], [ "uuid", "urn:uuid:abc-123" ] ], kinds
  end

  test "attach_identifiers keeps distinct kinds with the same value" do
    # ISBN and ISBN13 both classifying to the same digits is legitimate
    # and should round-trip — only exact (kind, value) dupes get folded.
    book = make_book

    BookIngester.new("/ignored").send(:attach_identifiers, book, [
      { kind: "isbn",   value: "9780000000001" },
      { kind: "isbn13", value: "9780000000001" }
    ])

    assert_equal 2, book.book_identifiers.count
  end

  test "attach_identifiers skips entries with blank kind or value" do
    book = make_book

    BookIngester.new("/ignored").send(:attach_identifiers, book, [
      { kind: "uuid", value: "" },
      { kind: "",     value: "something" },
      { kind: nil,    value: nil },
      { kind: "uuid", value: "urn:uuid:keep" }
    ])

    assert_equal [ [ "uuid", "urn:uuid:keep" ] ], book.book_identifiers.pluck(:kind, :value)
  end

  private

  def make_book
    Book.create!(
      title:       "Test",
      path:        "test/book-#{SecureRandom.hex(4)}",
      file_name:   "test",
      file_format: "EPUB",
      imported_at: Time.current
    )
  end
end
