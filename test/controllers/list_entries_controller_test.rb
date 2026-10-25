require "test_helper"

class ListEntriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = users(:admin)
    @other = users(:reader)
    @list = @owner.lists.create!(name: "Entries test list", shared: true)
    @book = Book.create!(title: "Leviathan Wakes", path: "test/leviathan", file_name: "leviathan",
                         file_format: "EPUB", imported_at: Time.current)
    @book.book_authors.create!(author: Author.create!(name: "James S.A. Corey"), position: 0)
  end

  teardown do
    List.destroy_all
    Book.where(title: "Leviathan Wakes").destroy_all
    Author.where(name: "James S.A. Corey").destroy_all
  end

  test "free text is parsed as Title by Author and queued for lookup" do
    assert_enqueued_with(job: ResolveListEntriesJob) do
      post list_list_entries_path(@list),
           params: { list_entry: { query: "Project Hail Mary by Andy Weir" } },
           headers: headers_for(@owner)
    end
    entry = @list.list_entries.last
    assert_equal "Project Hail Mary", entry.title
    assert_equal "Andy Weir", entry.author_name
    assert_nil entry.resolution_status
  end

  test "picking a library book adds it matched and resolved" do
    assert_no_enqueued_jobs(only: ResolveListEntriesJob) do
      post list_list_entries_path(@list),
           params: { list_entry: { book_id: @book.id } },
           headers: headers_for(@owner)
    end
    entry = @list.list_entries.last
    assert_equal @book, entry.book
    assert_equal "James S.A. Corey", entry.author_name
    assert entry.resolved?
  end

  test "picking a Hardcover hit adds it resolved" do
    post list_list_entries_path(@list),
         params: { list_entry: { hardcover_book_id: 99, title: "Project Hail Mary", author_name: "Andy Weir",
                                 release_year: 2021, cover_url: "https://assets.hardcover.app/x.jpg" } },
         headers: headers_for(@owner)
    entry = @list.list_entries.last
    assert entry.resolved?
    assert_equal 99, entry.hardcover_book_id
    assert_equal 2021, entry.release_year
    assert_not entry.matched?
  end

  test "new entries go to the end of the list" do
    @list.list_entries.create!(title: "First", position: 0)
    post list_list_entries_path(@list), params: { list_entry: { query: "Second" } }, headers: headers_for(@owner)
    assert_equal %w[First Second], @list.list_entries.reload.map(&:title)
  end

  test "choose resolves to a stored candidate" do
    entry = @list.list_entries.create!(title: "Common Title", resolution_status: "ambiguous",
                                       resolution_candidates: [ { "id" => 1, "title" => "Common Title", "author_names" => [ "A Writer" ] },
                                                                { "id" => 2, "title" => "Common Title", "author_names" => [ "B Writer" ] } ])
    patch choose_list_list_entry_path(@list, entry), params: { hardcover_book_id: 2 }, headers: headers_for(@owner)
    entry.reload
    assert entry.resolved?
    assert_equal 2, entry.hardcover_book_id
    assert_equal "B Writer", entry.resolved_author
  end

  test "choose without a known candidate leaves the entry as typed" do
    entry = @list.list_entries.create!(title: "Common Title", resolution_status: "ambiguous",
                                       resolution_candidates: [ { "id" => 1, "title" => "Common Title" } ])
    patch choose_list_list_entry_path(@list, entry), params: { hardcover_book_id: 12345 }, headers: headers_for(@owner)
    entry.reload
    assert_equal "unresolved", entry.resolution_status
    assert_nil entry.hardcover_book_id
  end

  test "search lists library matches and an add-as-typed row" do
    get search_list_list_entries_path(@list, q: "leviathan"), headers: headers_for(@owner)
    assert_response :success
    assert_select "turbo-frame#list-entry-search-results"
    assert_select "button", text: /Leviathan Wakes/
    assert_select "input[name='list_entry[book_id]'][value='#{@book.id}']"
    assert_select "input[name='list_entry[query]'][value='leviathan']"
  end

  test "search matches each word against title or author" do
    get search_list_list_entries_path(@list, q: "leviathan corey"), headers: headers_for(@owner)
    assert_select "input[name='list_entry[book_id]'][value='#{@book.id}']"
  end

  test "the list page shows the picker for ambiguous entries" do
    @list.list_entries.create!(title: "Common Title", resolution_status: "ambiguous",
                               resolution_candidates: [ { "id" => 1, "title" => "Common Title", "author_names" => [ "A Writer" ], "release_year" => 1999 } ])
    get list_path(@list), headers: headers_for(@owner)
    assert_response :success
    assert_select "button", text: /Common Title — A Writer \(1999\)/
    assert_select "button", text: "None of these"
  end

  test "non-owners can't add, search, or choose" do
    entry = @list.list_entries.create!(title: "Common Title")
    post list_list_entries_path(@list), params: { list_entry: { query: "X" } }, headers: headers_for(@other)
    assert_response :not_found
    get search_list_list_entries_path(@list, q: "leviathan"), headers: headers_for(@other)
    assert_response :not_found
    patch choose_list_list_entry_path(@list, entry), headers: headers_for(@other)
    assert_response :not_found
  end
end
