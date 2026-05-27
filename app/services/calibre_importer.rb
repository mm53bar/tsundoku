require "sqlite3"

# Reads a Calibre library's metadata.db and upserts Tsundoku records keyed on
# Calibre's primary keys. Re-running picks up changes Calibre made since the
# last run; nothing is deleted (Calibre stays the source of truth until we add
# our own management UI).
#
# EPUB-only by design: books that don't have an EPUB format in Calibre are
# skipped and counted. Mobi/PDF/etc. can be added to Calibre as EPUB versions
# and re-imported if desired.
class CalibreImporter
  class MissingDatabase < StandardError; end

  Stats = Struct.new(
    :authors_seen,    :authors_created,
    :series_seen,     :series_created,
    :tags_seen,       :tags_created,
    :publishers_seen, :publishers_created,
    :books_seen,      :books_created, :books_updated, :books_skipped_no_epub,
    keyword_init: true
  )

  attr_reader :library_path, :db_path, :stats

  def initialize(library_path: Rails.configuration.x.library_path)
    @library_path = library_path
    @db_path = File.join(library_path, "metadata.db")
    @stats = Stats.new(
      authors_seen: 0,    authors_created: 0,
      series_seen: 0,     series_created: 0,
      tags_seen: 0,       tags_created: 0,
      publishers_seen: 0, publishers_created: 0,
      books_seen: 0,      books_created: 0, books_updated: 0, books_skipped_no_epub: 0
    )
  end

  def self.available?(library_path: Rails.configuration.x.library_path)
    File.exist?(File.join(library_path, "metadata.db"))
  end

  # Optionally yields (current, total) after each book is processed so the
  # caller can update a progress indicator. Callers should throttle their
  # block; the importer yields every book unconditionally.
  def import!(&progress_block)
    raise MissingDatabase, "metadata.db not found at #{db_path}" unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path, readonly: true, results_as_hash: true)
    begin
      author_id_map    = import_authors(db)
      series_id_map    = import_series(db)
      tag_id_map       = import_tags(db)
      publisher_id_map = import_publishers(db)
      import_books(db, author_id_map, series_id_map, tag_id_map, publisher_id_map, &progress_block)
    ensure
      db.close
    end
    stats
  end

  private

  def import_authors(db)
    map = {}
    db.execute("SELECT id, name, sort FROM authors").each do |row|
      stats.authors_seen += 1
      author = Author.find_or_initialize_by(calibre_id: row["id"])
      created = author.new_record?
      author.name = row["name"]
      author.sort_name = row["sort"]
      author.save!
      stats.authors_created += 1 if created
      map[row["id"]] = author.id
    end
    map
  end

  def import_series(db)
    map = {}
    db.execute("SELECT id, name, sort FROM series").each do |row|
      stats.series_seen += 1
      series = Series.find_or_initialize_by(calibre_id: row["id"])
      created = series.new_record?
      series.name = row["name"]
      series.sort_name = row["sort"]
      series.save!
      stats.series_created += 1 if created
      map[row["id"]] = series.id
    end
    map
  end

  def import_tags(db)
    map = {}
    db.execute("SELECT id, name FROM tags").each do |row|
      stats.tags_seen += 1
      tag = Tag.find_or_initialize_by(calibre_id: row["id"])
      created = tag.new_record?
      tag.name = row["name"]
      tag.save!
      stats.tags_created += 1 if created
      map[row["id"]] = tag.id
    end
    map
  end

  def import_publishers(db)
    map = {}
    db.execute("SELECT id, name, sort FROM publishers").each do |row|
      stats.publishers_seen += 1
      publisher = Publisher.find_or_initialize_by(calibre_id: row["id"])
      created = publisher.new_record?
      publisher.name = row["name"]
      publisher.sort_name = row["sort"]
      publisher.save!
      stats.publishers_created += 1 if created
      map[row["id"]] = publisher.id
    end
    map
  end

  def import_books(db, author_id_map, series_id_map, tag_id_map, publisher_id_map, &progress_block)
    rows = db.execute(<<~SQL).to_a
      SELECT id, title, sort, timestamp, pubdate, series_index, uuid, path, has_cover, last_modified
      FROM books
    SQL
    total = rows.size

    rows.each_with_index do |row, index|
      stats.books_seen += 1
      calibre_id = row["id"]

      data_row = db.execute(<<~SQL, calibre_id).first
        SELECT format, name FROM data WHERE book = ? AND UPPER(format) = 'EPUB' LIMIT 1
      SQL

      unless data_row
        stats.books_skipped_no_epub += 1
        Rails.logger.info("CalibreImporter: skipping book ##{calibre_id} (#{row['title']}) — no EPUB format")
        progress_block&.call(index + 1, total)
        next
      end

      authors_for_book = db.execute(<<~SQL, calibre_id).map { |r| author_id_map[r["author"]] }.compact
        SELECT author FROM books_authors_link WHERE book = ? ORDER BY id
      SQL

      series_row = db.execute(<<~SQL, calibre_id).first
        SELECT series FROM books_series_link WHERE book = ? LIMIT 1
      SQL
      series_rails_id = series_row && series_id_map[series_row["series"]]

      tags_for_book = db.execute(<<~SQL, calibre_id).map { |r| tag_id_map[r["tag"]] }.compact
        SELECT tag FROM books_tags_link WHERE book = ?
      SQL

      publisher_row = db.execute(<<~SQL, calibre_id).first
        SELECT publisher FROM books_publishers_link WHERE book = ? LIMIT 1
      SQL
      publisher_rails_id = publisher_row && publisher_id_map[publisher_row["publisher"]]

      identifiers_for_book = db.execute(<<~SQL, calibre_id).map { |r| [ r["type"], r["val"] ] }
        SELECT type, val FROM identifiers WHERE book = ?
      SQL

      description = db.execute("SELECT text FROM comments WHERE book = ? LIMIT 1", calibre_id).first&.dig("text")

      book = Book.find_or_initialize_by(calibre_id: calibre_id)
      created = book.new_record?

      book.assign_attributes(
        title: row["title"],
        sort_title: row["sort"],
        series_id: series_rails_id,
        series_index: row["series_index"],
        publisher_id: publisher_rails_id,
        added_at: parse_calibre_time(row["timestamp"]),
        pubdate: parse_calibre_time(row["pubdate"]),
        uuid: row["uuid"],
        description: description,
        path: row["path"],
        cover_path: row["has_cover"].to_i == 1 ? File.join(row["path"], "cover.jpg") : nil,
        file_name: data_row["name"],
        file_format: data_row["format"],
        last_modified: parse_calibre_time(row["last_modified"]),
        imported_at: Time.current
      )
      book.save!

      sync_book_authors(book, authors_for_book)
      sync_book_tags(book, tags_for_book)
      sync_book_identifiers(book, identifiers_for_book)

      if created
        stats.books_created += 1
      else
        stats.books_updated += 1
      end

      progress_block&.call(index + 1, total)
    end
  end

  def sync_book_authors(book, author_ids)
    existing = book.book_authors.index_by(&:author_id)
    author_ids.each_with_index do |author_id, position|
      ba = existing.delete(author_id) || book.book_authors.build(author_id: author_id)
      ba.position = position
      ba.save! if ba.changed? || ba.new_record?
    end
    existing.each_value(&:destroy)
  end

  def sync_book_tags(book, tag_ids)
    existing_ids = book.book_tags.pluck(:tag_id)
    (tag_ids - existing_ids).each { |tag_id| book.book_tags.create!(tag_id: tag_id) }
    (existing_ids - tag_ids).each { |tag_id| book.book_tags.where(tag_id: tag_id).destroy_all }
  end

  def sync_book_identifiers(book, identifiers)
    existing = book.book_identifiers.index_by { |bi| [ bi.kind, bi.value ] }
    identifiers.each do |kind, value|
      next if kind.blank? || value.blank?
      key = [ kind, value ]
      next if existing.delete(key)
      book.book_identifiers.create!(kind: kind, value: value)
    end
    existing.each_value(&:destroy)
  end

  def parse_calibre_time(value)
    return nil if value.blank?
    Time.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
