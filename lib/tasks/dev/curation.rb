# frozen_string_literal: true

module Dev
  module Curation
    class << self
      # User-attached state: readings (progress states), shelves (one
      # syncing), and lists (matched + unmatched). All attached to
      # Sheila so the navbar pill, on_kobo filter, and list page have
      # something to show when the local dev session signs in as her.
      def create_for(sheila, library)
        books = library[:books]

        create_readings(sheila, books)
        create_shelves(sheila, books)
        create_lists(sheila, books)
      end

      private

      def create_readings(sheila, books)
        # Pick a stable set by title so the dev grid has predictable
        # state across runs. Mix of progress states exercises the
        # progress bar on cards and the finished derivation. Sync
        # intent is curated separately via shelf membership (see
        # create_shelves).
        by_title = books.index_by(&:title)

        states = [
          { title: "Project Hail Mary",                   progress_percent: 42 },
          { title: "Circe",                               progress_percent: 87 },
          { title: "The Long Way to a Small Angry Planet", progress_percent: 12 },
          { title: "The Martian",                         progress_percent: 100, finished_at: 1.week.ago },
          { title: "The Song of Achilles",                progress_percent: 100, finished_at: 2.months.ago },
          { title: "Dune",                                progress_percent: 0 },
          { title: "The Catcher in the Rye",              progress_percent: 0 }
        ]

        states.each do |row|
          book = by_title[row[:title]] or next
          sheila.readings.create!(
            book:             book,
            progress_percent: row[:progress_percent],
            finished_at:      row[:finished_at]
          )
        end
      end

      def create_shelves(sheila, books)
        by_title = books.index_by(&:title)

        # Starred — the per-user default shelf the star icon drives.
        # Exists alongside any number of regular shelves; its books
        # reach the Kobo but it doesn't emit a collection.
        [ "Project Hail Mary", "Circe", "The Long Way to a Small Angry Planet", "Dune", "The Catcher in the Rye" ].each do |title|
          next unless (book = by_title[title])
          sheila.starred_shelf.shelf_entries.create!(book: book)
        end

        bedside = sheila.shelves.create!(name: "Bedside", sync_to_kobo: true)
        [ "Project Hail Mary", "Circe", "The Long Way to a Small Angry Planet", "The Fifth Season" ].each_with_index do |title, i|
          next unless (book = by_title[title])
          bedside.shelf_entries.create!(book: book, position: i)
        end

        reread = sheila.shelves.create!(name: "Re-read someday", sync_to_kobo: false)
        [ "The Martian", "The Song of Achilles", "The Left Hand of Darkness" ].each_with_index do |title, i|
          next unless (book = by_title[title])
          reread.shelf_entries.create!(book: book, position: i)
        end

        sheila.shelves.create!(name: "To buy", sync_to_kobo: false) # empty shelf
      end

      def create_lists(sheila, books)
        in_library = books.map(&:title)

        # A list whose entries mostly resolve to local books — exercises
        # the "matched" badge + the back-fill hook.
        sheila.lists.create!(name: "Sci-fi favourites", description: "Hand-picked.", shared: true).tap do |list|
          [
            "Dune",
            "Project Hail Mary",
            "The Long Way to a Small Angry Planet",
            "A book that isn't in the library yet",                # unmatched
            "The Three-Body Problem"                                # unmatched
          ].each_with_index do |title, i|
            book = in_library.include?(title) ? Book.find_by(title: title) : nil
            list.list_entries.create!(position: i, title: title, book: book, author_name: book ? nil : "Various")
          end
        end

        # A list that's all unmatched — exercises the Shelfmark
        # "Find on Shelfmark" links.
        sheila.lists.create!(name: "Booker shortlist (not yet in library)", shared: false).tap do |list|
          [
            { title: "Glory",              author: "NoViolet Bulawayo" },
            { title: "The Trees",          author: "Percival Everett" },
            { title: "Treacle Walker",     author: "Alan Garner" },
            { title: "Small Things Like These", author: "Claire Keegan" }
          ].each_with_index do |row, i|
            list.list_entries.create!(position: i, title: row[:title], author_name: row[:author])
          end
        end
      end
    end
  end
end
