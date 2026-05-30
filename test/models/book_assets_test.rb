require "test_helper"
require "fileutils"
require "tmpdir"

class BookAssetsTest < ActiveSupport::TestCase
  # Filesystem-backed test: the path-safety invariants are the point of
  # this class, so we exercise them against real directories rather than
  # mocking File.exist?. Each test re-roots Rails.configuration.x.library_path
  # at a fresh tmpdir and restores it on teardown.
  setup do
    @tmp = Dir.mktmpdir("book_assets_test")
    @original_library = Rails.configuration.x.library_path
    Rails.configuration.x.library_path = @tmp
  end

  teardown do
    Rails.configuration.x.library_path = @original_library
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
  end

  def make_book(**attrs)
    defaults = {
      path:        "Some Author/Some Book (1)",
      file_name:   "Some Book - Some Author",
      file_format: "EPUB",
      cover_path:  "Some Author/Some Book (1)/cover.jpg"
    }
    Book.new(**defaults.merge(attrs))
  end

  test "epub_full_path resolves under library root" do
    b = make_book
    assert b.assets.epub_full_path.start_with?(@tmp + File::SEPARATOR)
    assert b.assets.epub_full_path.end_with?("Some Book - Some Author.epub")
  end

  test "epub_full_path returns nil when file_name is blank" do
    b = make_book(file_name: nil)
    assert_nil b.assets.epub_full_path
  end

  test "epub_full_path returns nil when file_format is blank" do
    b = make_book(file_format: nil)
    assert_nil b.assets.epub_full_path
  end

  test "kepub_path is a sibling of the EPUB with kepubify naming" do
    b = make_book
    assert_equal File.dirname(b.assets.epub_full_path),
                 File.dirname(b.assets.kepub_path)
    assert b.assets.kepub_path.end_with?(".kepub.epub")
  end

  test "epub_downloadable? is false when file doesn't exist" do
    b = make_book
    refute b.assets.epub_downloadable?
  end

  test "epub_downloadable? is true once the file is on disk" do
    b = make_book
    FileUtils.mkdir_p(File.join(@tmp, b.path))
    File.write(b.assets.epub_full_path, "fake epub")
    assert b.assets.epub_downloadable?
  end

  test "cover_full_path prefers enriched cover when it exists" do
    b = make_book(enriched_cover_path: "covers/book_1.jpg")
    storage = Rails.root.join("storage").to_s
    FileUtils.mkdir_p(File.join(storage, "covers"))
    enriched = File.join(storage, "covers/book_1.jpg")
    File.write(enriched, "fake enriched")
    begin
      assert_equal enriched, b.assets.cover_full_path
    ensure
      File.delete(enriched) if File.exist?(enriched)
    end
  end

  test "cover_full_path falls back to library cover_path when enriched is missing" do
    b = make_book(enriched_cover_path: "covers/missing.jpg")
    assert b.assets.cover_full_path.end_with?("Some Book (1)/cover.jpg")
  end

  test "cover_mime_type maps common extensions" do
    cases = {
      "cover.jpg"  => "image/jpeg",
      "cover.jpeg" => "image/jpeg",
      "cover.png"  => "image/png",
      "cover.gif"  => "image/gif",
      "cover.webp" => "image/webp",
      "cover.xyz"  => "application/octet-stream"
    }
    cases.each do |fname, expected|
      b = make_book(cover_path: "Some Author/Some Book (1)/#{fname}",
                    enriched_cover_path: nil)
      assert_equal expected, b.assets.cover_mime_type, "for #{fname}"
    end
  end

  # The point of the safety check: a malicious or corrupted column can't
  # cause us to read or delete files outside the library root, even with
  # `..` segments or absolute paths.
  test "path traversal via .. is refused" do
    b = make_book(path: "../../etc")
    assert_nil b.assets.epub_full_path
    assert_nil b.assets.kepub_path
  end

  test "absolute path components are refused" do
    b = make_book(path: "/etc/passwd")
    assert_nil b.assets.epub_full_path
  end

  test "embedded .. that escapes the root is refused" do
    b = make_book(path: "Author/../../etc")
    assert_nil b.assets.epub_full_path
  end

  test "sibling-prefix attack is refused" do
    # If we naively checked `start_with?(library_root)` without the
    # File::SEPARATOR, a sibling like `/tmp_evil` next to `/tmp` would
    # pass — but Pathname.expand_path + the separator suffix catches it.
    Rails.configuration.x.library_path = "#{@tmp}/library"
    FileUtils.mkdir_p("#{@tmp}/library_evil")
    b = make_book(path: "../library_evil")
    assert_nil b.assets.epub_full_path
  end

  test "cover_path that escapes the root is refused" do
    b = make_book(cover_path: "../../etc/passwd",
                  enriched_cover_path: nil)
    assert_nil b.assets.cover_full_path
  end

  test "enriched_cover_path that escapes storage is refused" do
    b = make_book(enriched_cover_path: "../../../etc/passwd",
                  cover_path: nil)
    assert_nil b.assets.cover_full_path
  end

  test "delete_all! removes EPUB, KEPUB, and library cover" do
    b = make_book
    FileUtils.mkdir_p(File.join(@tmp, b.path))
    File.write(b.assets.epub_full_path,  "epub")
    File.write(b.assets.kepub_path,      "kepub")
    File.write(b.assets.cover_full_path, "cover")

    b.assets.delete_all!

    refute File.exist?(b.assets.epub_full_path)
    refute File.exist?(b.assets.kepub_path)
    refute File.exist?(File.join(@tmp, b.cover_path))
  end

  test "delete_all! removes the book directory when it becomes empty" do
    b = make_book
    book_dir = File.join(@tmp, b.path)
    FileUtils.mkdir_p(book_dir)
    File.write(b.assets.epub_full_path, "epub")

    b.assets.delete_all!

    refute File.directory?(book_dir)
  end

  test "delete_all! preserves the book directory when other files remain" do
    b = make_book
    book_dir = File.join(@tmp, b.path)
    FileUtils.mkdir_p(book_dir)
    File.write(b.assets.epub_full_path, "epub")
    File.write(File.join(book_dir, "notes.txt"), "user note")

    b.assets.delete_all!

    assert File.directory?(book_dir)
    assert File.exist?(File.join(book_dir, "notes.txt"))
  end
end
