require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  # Proxy auth: the controller stack expects Remote-User to identify the
  # signed-in user. Tests authenticate by injecting that header.
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

  setup do
    @user = users(:reader)
    Book.destroy_all  # start with a clean library

    @hobbit = Book.create!(
      title:       "The Hobbit",
      path:        "tolkien/hobbit",
      file_name:   "hobbit",
      file_format: "EPUB",
      imported_at: Time.current
    )
    tolkien = Author.create!(name: "J.R.R. Tolkien")
    @hobbit.book_authors.create!(author: tolkien, position: 0)
  end

  teardown do
    Book.destroy_all
    Author.where(name: "J.R.R. Tolkien").destroy_all
  end

  test "queries shorter than MIN_QUERY_LEN return an empty frame" do
    get search_path, params: { q: "a" }, headers: headers_for(@user)
    assert_response :success
    # Frame is rendered but contains no results and no empty-state message.
    refute response.body.include?("hobbit")
    refute response.body.include?("No matches")
  end

  test "title match returns the book" do
    get search_path, params: { q: "hobbit" }, headers: headers_for(@user)
    assert_response :success
    assert response.body.include?("The Hobbit")
  end

  test "author match returns the book" do
    get search_path, params: { q: "tolkien" }, headers: headers_for(@user)
    assert_response :success
    assert response.body.include?("The Hobbit")
  end

  test "no-match query shows the empty state" do
    get search_path, params: { q: "xyzzy_nope" }, headers: headers_for(@user)
    assert_response :success
    assert response.body.include?("No matches")
  end

  test "results are capped at RESULT_LIMIT" do
    # Create more books than the limit and confirm the response includes
    # at most RESULT_LIMIT of them (here, all sharing a matchable title
    # word).
    (1..(SearchController::RESULT_LIMIT + 5)).each do |i|
      Book.create!(
        title:       "Catchphrase #{i}",
        path:        "catch/#{i}",
        file_name:   "catch_#{i}",
        file_format: "EPUB",
        imported_at: Time.current
      )
    end

    get search_path, params: { q: "catchphrase" }, headers: headers_for(@user)
    assert_response :success

    rendered_titles = response.body.scan(/Catchphrase \d+/).uniq
    assert rendered_titles.length <= SearchController::RESULT_LIMIT,
           "expected at most #{SearchController::RESULT_LIMIT} matches, got #{rendered_titles.length}"
  end

  test "LIKE wildcards in user input are escaped, not interpreted" do
    # If we didn't sanitize, `%` would match everything and `_` would
    # match any single char. Confirm a literal `%` doesn't accidentally
    # turn into a wildcard.
    get search_path, params: { q: "%%%%" }, headers: headers_for(@user)
    assert_response :success
    refute response.body.include?("The Hobbit"),
           "wildcard injection succeeded — sanitize_sql_like is bypassed"
  end
end
