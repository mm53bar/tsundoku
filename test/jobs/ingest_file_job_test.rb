require "test_helper"
require "zip"
require "fileutils"

class IngestFileJobTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("ingest")
    @prev_ingest = Rails.configuration.x.ingest_path
    Rails.configuration.x.ingest_path = @root
  end

  teardown do
    Rails.configuration.x.ingest_path = @prev_ingest
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  test "a duplicate drop is parked in .duplicates and leaves the scan path" do
    # A book with the ISBN the dropped file carries already exists.
    book = Book.create!(title: "The Correspondent", path: "p", file_name: "f",
                        file_format: "EPUB", imported_at: Time.current)
    book.book_identifiers.create!(kind: "isbn13", value: "9781234567897")

    epub = File.join(@root, "dropped.epub")
    write_epub(epub, isbn: "9781234567897")

    task = Task.create!(kind: "book_ingest", status: :queued, result: { "file_path" => epub })
    IngestFileJob.perform_now(task.id, epub)

    refute File.exist?(epub), "source file should be moved out of the active scan path"
    parked = Dir.glob(File.join(@root, ".duplicates", "*.epub"))
    assert_equal 1, parked.length, "duplicate should be parked under .duplicates/"

    # The exact behavior that was looping: the recurring scan must not re-find it.
    assert_empty Dir.glob(File.join(@root, "**/*.epub")),
                 "the recurring scan glob must not see parked files"

    task.reload
    assert task.succeeded?
    assert_equal "duplicate", task.result["status"]
    assert_equal book.id, task.result["book_id"]
  end

  test "an unparseable file is parked in .failed" do
    bad = File.join(@root, "broken.epub")
    File.write(bad, "this is not a zip archive")

    task = Task.create!(kind: "book_ingest", status: :queued, result: { "file_path" => bad })
    IngestFileJob.perform_now(task.id, bad)

    refute File.exist?(bad), "failed file should be moved out of the scan path"
    assert_equal 1, Dir.glob(File.join(@root, ".failed", "*.epub")).length
    assert_empty Dir.glob(File.join(@root, "**/*.epub"))
    assert task.reload.failed?
  end

  private

  def write_epub(path, isbn:)
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream("META-INF/container.xml") { |o| o.write(CONTAINER) }
      zip.get_output_stream("OEBPS/content.opf")      { |o| o.write(opf(isbn)) }
    end
  end

  CONTAINER = <<~XML
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
  XML

  def opf(isbn)
    <<~XML
      <?xml version="1.0"?>
      <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
          <dc:title>The Correspondent</dc:title>
          <dc:creator opf:role="aut">Virginia Evans</dc:creator>
          <dc:identifier id="bookid" opf:scheme="ISBN">#{isbn}</dc:identifier>
          <dc:language>en</dc:language>
        </metadata>
        <manifest/>
      </package>
    XML
  end
end
