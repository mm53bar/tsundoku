require "test_helper"
require "zip"

# EpubParser cracks EPUBs (ZIP archives) open with rubyzip. There were no tests
# here, so this builds a minimal EPUB in a temp dir and exercises the full read
# path — guarding the rubyzip dependency across upgrades.
class EpubParserTest < ActiveSupport::TestCase
  setup    { @dir = Dir.mktmpdir }
  teardown { FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir) }

  test "parse extracts Dublin Core metadata" do
    result = EpubParser.parse(build_epub)

    assert_equal "Test Title", result.title
    assert_equal [ "Test Author" ], result.authors
    assert_equal "Test Publisher", result.publisher
    assert_equal "en", result.language
    assert_equal "Test Series", result.series
    assert(result.identifiers.any? { |i| i[:value] == "9781234567897" },
           "expected the ISBN identifier to be parsed")
  end

  test "extract_cover returns the cover image bytes" do
    cover = EpubParser.extract_cover(build_epub)

    assert_not_nil cover
    assert_equal "jpg", cover.extension
    assert_equal "image/jpeg", cover.media_type
    assert cover.bytes.start_with?("\xFF\xD8\xFF".b), "expected JPEG magic bytes"
  end

  test "returns nil on a non-EPUB file instead of raising" do
    bad = File.join(@dir, "not.epub")
    File.write(bad, "this is plainly not a zip archive")

    assert_nil EpubParser.parse(bad)
    assert_nil EpubParser.extract_cover(bad)
  end

  private

  def build_epub
    path = File.join(@dir, "book.epub")
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream("META-INF/container.xml") { |o| o.write(CONTAINER_XML) }
      zip.get_output_stream("OEBPS/content.opf")      { |o| o.write(OPF_XML) }
      zip.get_output_stream("OEBPS/cover.jpg")        { |o| o.write("\xFF\xD8\xFF".b + "fakecover".b) }
    end
    path
  end

  CONTAINER_XML = <<~XML
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
  XML

  OPF_XML = <<~XML
    <?xml version="1.0"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
        <dc:title>Test Title</dc:title>
        <dc:creator opf:role="aut">Test Author</dc:creator>
        <dc:identifier id="bookid" opf:scheme="ISBN">9781234567897</dc:identifier>
        <dc:publisher>Test Publisher</dc:publisher>
        <dc:date>2020-01-01</dc:date>
        <dc:language>en</dc:language>
        <meta name="calibre:series" content="Test Series"/>
      </metadata>
      <manifest>
        <item id="cover" href="cover.jpg" media-type="image/jpeg" properties="cover-image"/>
      </manifest>
    </package>
  XML
end
