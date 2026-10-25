require "test_helper"

class ListEntryTest < ActiveSupport::TestCase
  setup do
    @list = users(:admin).lists.create!(name: "Resolution test list")
  end

  teardown do
    List.destroy_all
    Book.where(title: "Leviathan Wakes").destroy_all
  end

  def hit(id, title, authors, users: 100)
    HardcoverHit.new(id: id, title: title, author_names: authors, users_count: users,
                     release_year: 2011, cover_url: "https://assets.hardcover.app/x.jpg")
  end

  test "resolve_with! stores a clear winner without touching what was typed" do
    entry = @list.list_entries.create!(title: "leviathan wakes")
    entry.resolve_with!([ hit(42, "Leviathan Wakes", [ "James S.A. Corey" ]) ])

    assert entry.resolved?
    assert_equal "leviathan wakes", entry.title
    assert_nil entry.author_name
    assert_equal 42, entry.hardcover_book_id
    assert_equal "Leviathan Wakes", entry.display_title
    assert_equal "James S.A. Corey", entry.display_author
    assert_equal 2011, entry.release_year
  end

  test "resolve_with! keeps suggestions when there's no clear winner" do
    entry = @list.list_entries.create!(title: "Common Title")
    entry.resolve_with!([ hit(1, "Common Title", [ "A Writer" ], users: 300), hit(2, "Common Title", [ "B Writer" ], users: 200) ])

    assert entry.ambiguous?
    assert_equal [ 1, 2 ], entry.reload.candidates.map(&:id)
    assert_nil entry.hardcover_book_id
  end

  test "resolve_with! with no hits marks the entry unresolved" do
    entry = @list.list_entries.create!(title: "Nothing Like This")
    entry.resolve_with!([])
    assert_equal "unresolved", entry.resolution_status
  end

  test "choosing a candidate resolves it and clears the suggestions" do
    entry = @list.list_entries.create!(title: "Common Title")
    entry.resolve_with!([ hit(1, "Common Title", [ "A Writer" ], users: 300), hit(2, "Common Title", [ "B Writer" ], users: 200) ])
    entry.choose!(entry.candidates.last)

    assert entry.reload.resolved?
    assert_equal 2, entry.hardcover_book_id
    assert_nil entry.resolution_candidates
  end

  test "resolving matches the library through the hardcover_book identifier" do
    book = Book.create!(title: "Leviathan Wakes", path: "test/leviathan", file_name: "leviathan",
                        file_format: "EPUB", imported_at: Time.current)
    book.book_identifiers.create!(kind: "hardcover_book", value: "42")
    entry = @list.list_entries.create!(title: "Expanse 1")

    entry.choose!(hit(42, "Leviathan Wakes", [ "James S.A. Corey" ]))
    assert_equal book, entry.reload.book
  end

  test "cover_url must be http(s)" do
    entry = @list.list_entries.new(title: "X", cover_url: "javascript:alert(1)")
    refute entry.valid?
  end

  test "Hardcover hits credit only the authors, not forewords or cover art" do
    hit = HardcoverHit.from_document(
      "id" => 1, "title" => "1984", "author_names" => [ "George Orwell", "Peter Davison", "Shepard Fairey" ],
      "contributions" => [
        { "author" => { "name" => "George Orwell" }, "contribution" => "Author" },
        { "author" => { "name" => "Peter Davison" }, "contribution" => "Foreword" },
        { "author" => { "name" => "Shepard Fairey" }, "contribution" => "Cover Artist" }
      ]
    )
    assert_equal [ "George Orwell" ], hit.author_names
  end
end
