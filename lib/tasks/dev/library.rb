# frozen_string_literal: true

require "fileutils"

module Dev
  module Library
    # Library data structured so the UI surfaces interesting cases:
    #   - some authors have hardcover_slug (drives the "more by author"
    #     Turbo Frame on author#show and book#show), some don't (drives
    #     the bin/rails enrichment:backfill_slugs path)
    #   - books with and without ISBN (drives the two enrichment paths)
    #   - books with and without series membership
    #   - books inside a series so series#show has content
    AUTHORS = [
      { name: "Frank Herbert",            slug: "frank-herbert" },
      { name: "Gabriel García Márquez",   slug: "gabriel-garcia-marquez" },
      { name: "Madeline Miller",          slug: "madeline-miller" },
      { name: "Andy Weir",                slug: "andy-weir" },
      { name: "Becky Chambers",           slug: "becky-chambers" },
      { name: "Brandon Sanderson",        slug: "brandon-sanderson" },
      { name: "J. D. Salinger",           slug: nil },
      { name: "N. K. Jemisin",            slug: nil },
      { name: "Robin Hobb",               slug: nil },
      { name: "Ursula K. Le Guin",        slug: nil }
    ].freeze

    SERIES = [
      { name: "Wayfarers", slug: "wayfarers" },
      { name: "Mistborn",  slug: "mistborn" }
    ].freeze

    # Books — each row references author/series by name. ISBN is optional
    # (lets the no-ISBN enrichment fallback path show up in dev). Series
    # index sorts series#show in reading order.
    BOOKS = [
      { title: "Dune",                                authors: [ "Frank Herbert" ],            isbn: "9780441013593" },
      { title: "One Hundred Years of Solitude",       authors: [ "Gabriel García Márquez" ],   isbn: nil },
      { title: "Love in the Time of Cholera",         authors: [ "Gabriel García Márquez" ],   isbn: "9780307389732" },
      { title: "Circe",                               authors: [ "Madeline Miller" ],          isbn: "9780316556347" },
      { title: "The Song of Achilles",                authors: [ "Madeline Miller" ],          isbn: "9780062060624" },
      { title: "Project Hail Mary",                   authors: [ "Andy Weir" ],                isbn: "9780593135204" },
      { title: "The Martian",                         authors: [ "Andy Weir" ],                isbn: "9780553418026" },
      { title: "The Long Way to a Small Angry Planet", authors: [ "Becky Chambers" ], series: "Wayfarers", series_index: 1, isbn: "9780062444134" },
      { title: "A Closed and Common Orbit",           authors: [ "Becky Chambers" ], series: "Wayfarers", series_index: 2, isbn: "9780062569400" },
      { title: "Record of a Spaceborn Few",           authors: [ "Becky Chambers" ], series: "Wayfarers", series_index: 3, isbn: nil },
      { title: "The Final Empire",                    authors: [ "Brandon Sanderson" ], series: "Mistborn", series_index: 1, isbn: "9780765350381" },
      { title: "The Well of Ascension",               authors: [ "Brandon Sanderson" ], series: "Mistborn", series_index: 2, isbn: "9780765356130" },
      { title: "The Hero of Ages",                    authors: [ "Brandon Sanderson" ], series: "Mistborn", series_index: 3, isbn: "9780765356147" },
      { title: "The Catcher in the Rye",              authors: [ "J. D. Salinger" ],           isbn: nil },
      { title: "The Fifth Season",                    authors: [ "N. K. Jemisin" ],            isbn: "9780316229296" },
      { title: "The Obelisk Gate",                    authors: [ "N. K. Jemisin" ],            isbn: nil },
      { title: "Assassin's Apprentice",               authors: [ "Robin Hobb" ],               isbn: "9780553573398" },
      { title: "Royal Assassin",                      authors: [ "Robin Hobb" ],               isbn: nil },
      { title: "The Left Hand of Darkness",           authors: [ "Ursula K. Le Guin" ],        isbn: "9780441478125" },
      { title: "The Dispossessed",                    authors: [ "Ursula K. Le Guin" ],        isbn: nil }
    ].freeze

    class << self
      def create_library
        Book.destroy_all
        Series.destroy_all
        Author.destroy_all

        authors_by_name = AUTHORS.to_h do |row|
          [ row[:name], Author.create!(name: row[:name], hardcover_slug: row[:slug]) ]
        end

        series_by_name = SERIES.to_h do |row|
          [ row[:name], Series.create!(name: row[:name], hardcover_slug: row[:slug]) ]
        end

        books = BOOKS.map { |row| create_book(row, authors_by_name, series_by_name) }

        { authors: authors_by_name, series: series_by_name, books: books }
      end

      private

      def create_book(row, authors_by_name, series_by_name)
        relative_dir  = File.join(safe(row[:authors].first), "#{safe(row[:title])} (devbook)")
        file_basename = safe(row[:title])
        ensure_epub_stub_on_disk(relative_dir, file_basename)

        book = Book.create!(
          title:        row[:title],
          path:         relative_dir,
          file_name:    file_basename,
          file_format:  "EPUB",
          series:       row[:series] ? series_by_name[row[:series]] : nil,
          series_index: row[:series_index],
          imported_at:  Time.current,
          added_at:     Time.current,
          last_modified: Time.current
        )

        row[:authors].each_with_index do |name, i|
          book.book_authors.create!(author: authors_by_name[name], position: i)
        end

        if row[:isbn]
          book.book_identifiers.create!(kind: "isbn13", value: row[:isbn])
        end

        book
      end

      # Empty placeholder so book.assets.epub_downloadable? returns true —
      # the dev UI can render Download links that resolve to a real file
      # (zero bytes, but the route works). KEPUB stubs aren't needed; the
      # sync path serves EPUB when KEPUB is absent.
      def ensure_epub_stub_on_disk(relative_dir, file_basename)
        library_root = Rails.configuration.x.library_path
        full_dir     = File.join(library_root, relative_dir)
        FileUtils.mkdir_p(full_dir)
        File.write(File.join(full_dir, "#{file_basename}.epub"), "")
      end

      def safe(text)
        text.to_s.gsub(%r{[/\\:*?"<>| -]}, "_").gsub(/\s+/, " ").strip
      end
    end
  end
end
