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

  # restore_file_if_moved — the filesystem half of the
  # create+move atomicity guarantee. When the DB transaction rolls
  # back, the file we moved from /ingest into the library has to come
  # back out so AutoIngestScanJob's next tick can retry. Each branch
  # below pins one of the conditions under which restore should or
  # should not move the file.

  test "restore_file_if_moved moves target back to source when source is gone and target exists" do
    Dir.mktmpdir("ingester_restore") do |dir|
      source = File.join(dir, "ingest", "book.epub")
      target = File.join(dir, "library", "Author", "Book", "book.epub")
      FileUtils.mkdir_p(File.dirname(source))
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "fake epub bytes")

      BookIngester.new("/ignored").send(:restore_file_if_moved,
        { source: source, target: target, relative_dir: "Author/Book", file_basename: "book" })

      assert File.exist?(source), "expected source to be restored"
      refute File.exist?(target), "expected target to be removed"
    end
  end

  test "restore_file_if_moved is a no-op when source still exists (move never happened)" do
    Dir.mktmpdir("ingester_restore_noop") do |dir|
      source = File.join(dir, "ingest", "book.epub")
      target = File.join(dir, "library", "Author", "Book", "book.epub")
      FileUtils.mkdir_p(File.dirname(source))
      File.write(source, "still here")

      BookIngester.new("/ignored").send(:restore_file_if_moved,
        { source: source, target: target, relative_dir: "Author/Book", file_basename: "book" })

      assert File.exist?(source), "source should be left alone"
      refute File.exist?(target), "target shouldn't have been created"
    end
  end

  test "restore_file_if_moved is a no-op when target doesn't exist (mv never completed)" do
    Dir.mktmpdir("ingester_restore_no_target") do |dir|
      source = File.join(dir, "ingest", "book.epub")
      target = File.join(dir, "library", "Author", "Book", "book.epub")

      BookIngester.new("/ignored").send(:restore_file_if_moved,
        { source: source, target: target, relative_dir: "Author/Book", file_basename: "book" })

      refute File.exist?(source)
      refute File.exist?(target)
    end
  end

  test "restore_file_if_moved tolerates nil / missing fields" do
    ingester = BookIngester.new("/ignored")
    assert_nothing_raised do
      ingester.send(:restore_file_if_moved, nil)
      ingester.send(:restore_file_if_moved, {})
      ingester.send(:restore_file_if_moved, { source: "/tmp/a" })
      ingester.send(:restore_file_if_moved, { target: "/tmp/b" })
    end
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
