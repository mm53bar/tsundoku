require "fileutils"
require "pathname"

# Ingest one EPUB file: parse its OPF metadata, dedupe by ISBN against
# what we already have, create Book + Authors + BookIdentifiers + (best-
# effort) Publisher + Series, and move the file from /ingest into the
# Calibre-style layout under /library:
#
#   <library_path>/<Author>/<Title (book.id)>/<title>.epub
#
# Returns a Result struct with:
#   status: :ingested | :duplicate | :failed
#   book: the created Book (or matching existing book on :duplicate)
#   reason: short string when :failed (for surfacing in the Task error)
#
# Designed to be called from IngestFileJob. Does not handle enrichment —
# the job enqueues that separately after a successful ingest.
class BookIngester
  Result = Struct.new(:status, :book, :reason, keyword_init: true)

  MAX_PATH_SEGMENT = 100

  def self.ingest(file_path)
    new(file_path).ingest
  end

  def initialize(file_path)
    @file_path = file_path.to_s
  end

  def ingest
    return Result.new(status: :failed, reason: "File does not exist") unless File.exist?(@file_path)
    return Result.new(status: :failed, reason: "Not a .epub file") unless @file_path.downcase.end_with?(".epub")

    metadata = EpubParser.parse(@file_path)
    return Result.new(status: :failed, reason: "Could not parse EPUB metadata") unless metadata

    if (existing = duplicate_book_for(metadata))
      Rails.logger.info("BookIngester: skipping #{@file_path} — duplicate of book ##{existing.id} (#{existing.title})")
      return Result.new(status: :duplicate, book: existing)
    end

    # Atomic across DB + filesystem: open one transaction wrapping the
    # book create, author/identifier attach, file move, and the path
    # back-fill update. If anything raises, the transaction rolls back
    # and the rescue block moves the file back to /ingest — preventing
    # the orphan-row class of bugs (row committed with path: "" because
    # a later step in the chain blew up).
    book = nil
    moved = nil

    Book.transaction do
      book  = build_book_record(metadata)
      moved = move_file_into_library(book, metadata)
      book.update!(path: moved[:relative_dir], file_name: moved[:file_basename])
      extract_cover(book)
    end

    Result.new(status: :ingested, book: book)
  rescue => e
    restore_file_if_moved(moved)
    Rails.logger.error("BookIngester: #{e.class} on #{@file_path}: #{e.message}\n#{e.backtrace.first(8).join("\n")}")
    Result.new(status: :failed, reason: "#{e.class}: #{e.message}")
  end

  private

  # Match on any ISBN-shaped identifier already in our DB. ISBN values are
  # normalized to digits-only in the parser; we compare to existing
  # book_identifiers of any ISBN kind.
  def duplicate_book_for(metadata)
    isbn_values = metadata.identifiers
      .select { |i| i[:kind].to_s.start_with?("isbn") }
      .map { |i| i[:value] }
      .compact
      .reject(&:empty?)

    return nil if isbn_values.empty?

    BookIdentifier
      .where(kind: BookIdentifier::ISBN_KINDS)
      .where(value: isbn_values)
      .includes(:book)
      .first
      &.book
  end

  # Persist a Book row with placeholder path/file_name (back-filled
  # after the move into the library), then attach authors and
  # identifiers. Runs inside the caller's transaction — if anything
  # downstream fails, the row is rolled back along with the move.
  def build_book_record(metadata)
    publisher = ensure_publisher(metadata.publisher)
    series    = ensure_series(metadata.series)

    book = Book.new(
      title: metadata.title.presence || File.basename(@file_path, ".epub"),
      description: metadata.description,
      publisher: publisher,
      series: series,
      series_index: metadata.series_index,
      pubdate: metadata.pubdate,
      path: "", # back-filled after move
      file_name: "", # back-filled after move
      file_format: "EPUB",
      added_at: Time.current,
      imported_at: Time.current,
      last_modified: Time.current,
      calibre_id: nil
    )
    book.save!(validate: false) # path/file_name are placeholders here

    attach_authors(book, metadata.authors)
    attach_identifiers(book, metadata.identifiers)

    book
  end

  # Each raw name from the OPF gets passed through AuthorNameNormalizer
  # first — OPF strings are commonly dirty (multi-author joined by `|`
  # or `;`, surname-first as "Bock| Laszlo", trailing punctuation,
  # placeholders like "Unknown Author"). The normalizer can return zero
  # (placeholder → dropped), one, or multiple names per raw input; we
  # flatten and dedupe before linking.
  def attach_authors(book, raw_names)
    return if raw_names.empty?

    cleaned = raw_names.flat_map { |raw| AuthorNameNormalizer.normalize(raw) }.uniq
    return if cleaned.empty?

    normalized_to_author = Author.all.index_by { |a| Author.normalize_name(a.name) }

    cleaned.each_with_index do |name, position|
      key = Author.normalize_name(name)
      author = normalized_to_author[key] || Author.create!(name: name).tap { |a| normalized_to_author[key] = a }
      book.book_authors.create!(author: author, position: position)
    end
  end

  # find_or_create — some OPF files (notably ePubLibre's) carry the same
  # identifier twice under different scheme tags that classify to the same
  # (kind, value) pair, or carry a raw and a hyphenated ISBN that normalize
  # to the same digits. BookIdentifier has uniqueness scoped on
  # [book_id, kind, value], so a plain create! would blow up the ingest.
  def attach_identifiers(book, identifiers)
    identifiers.each do |id|
      next if id[:kind].blank? || id[:value].blank?
      book.book_identifiers.find_or_create_by!(kind: id[:kind], value: id[:value])
    end
  end

  def ensure_publisher(name)
    return nil if name.blank?
    Publisher.find_or_create_by!(name: name.strip)
  end

  def ensure_series(name)
    return nil if name.blank?
    Series.find_or_create_by!(name: name.strip)
  end

  # Move the EPUB out of /ingest and into the library's Calibre-style
  # layout. Returns a record of the move so the caller can roll back the
  # filesystem half if the DB transaction later rolls back.
  def move_file_into_library(book, metadata)
    library_root = Pathname.new(Rails.configuration.x.library_path)
    author_dir   = filename_safe(metadata.authors.first.presence || "Unknown Author")
    title_dir    = "#{filename_safe(book.title)} (#{book.id})"
    file_basename = filename_safe(book.title)

    target_dir  = library_root.join(author_dir, title_dir)
    target_path = target_dir.join("#{file_basename}.epub")

    FileUtils.mkdir_p(target_dir)
    FileUtils.mv(@file_path, target_path)

    {
      source:        @file_path,
      target:        target_path.to_s,
      relative_dir:  target_dir.relative_path_from(library_root).to_s,
      file_basename: file_basename
    }
  end

  # Roll back a successful filesystem move when the surrounding DB
  # transaction has rolled back. Best-effort — if restore itself fails
  # we log and move on; the operator can clean up by hand. Guards so we
  # don't clobber a file that's already at the source or move from a
  # target that doesn't exist.
  def restore_file_if_moved(moved)
    return unless moved.is_a?(Hash) && moved[:source].present? && moved[:target].present?
    return if File.exist?(moved[:source])
    return unless File.exist?(moved[:target])

    FileUtils.mv(moved[:target], moved[:source])
    Rails.logger.info("BookIngester: restored #{moved[:target]} → #{moved[:source]} after rollback")
  rescue => e
    Rails.logger.warn("BookIngester: file restore failed (#{moved[:target]} → #{moved[:source]}): #{e.class}: #{e.message}")
  end

  # Pull the cover image out of the EPUB and save it next to the book file
  # in Calibre style. Set book.cover_path so Book#cover_full_path finds it
  # via the library bind-mount. Silent on failure — books without a
  # parseable cover are ingested without one; enrichment will fill in the
  # gap when it finds a match.
  def extract_cover(book)
    library_root = Pathname.new(Rails.configuration.x.library_path)
    epub_path = library_root.join(book.path, "#{book.file_name}.epub").to_s
    cover = EpubParser.extract_cover(epub_path)
    return unless cover

    cover_filename = "cover.#{cover.extension}"
    cover_path = library_root.join(book.path, cover_filename)
    File.binwrite(cover_path, cover.bytes)

    relative_cover = cover_path.relative_path_from(library_root).to_s
    book.update!(cover_path: relative_cover)
  rescue => e
    Rails.logger.warn("BookIngester: cover extract failed for book ##{book.id} (#{book.title}): #{e.class}: #{e.message}")
  end

  # Replace path-hostile characters and trim to a sensible length so we
  # don't generate filenames the host filesystem chokes on.
  def filename_safe(text)
    cleaned = text.to_s.gsub(%r{[/\\:*?"<>| -]}, "_").gsub(/\s+/, " ").strip
    cleaned = "Untitled" if cleaned.empty?
    cleaned[0, MAX_PATH_SEGMENT]
  end
end
