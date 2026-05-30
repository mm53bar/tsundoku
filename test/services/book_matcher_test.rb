require "test_helper"

class BookMatcherTest < ActiveSupport::TestCase
  setup do
    @corey1 = Author.create!(name: "James S.A. Corey")
    @corey2 = Author.create!(name: "James S. A. Corey") # normalizes to same as @corey1
    @other  = Author.create!(name: "Different Person")

    @accelerate = make_book("Accelerate: Building and Scaling High Performing Technology Organizations", [ @other ])
    @leviathan  = make_book("Leviathan Wakes", [ @corey1 ])
    @abaddon    = make_book("Abaddon's Gate",  [ @corey1 ])
    @same_title_a = make_book("Common Title", [ @other ])
    @same_title_b = make_book("Common Title", [ @corey1 ])
  end

  teardown do
    Book.where(title: [
      "Accelerate: Building and Scaling High Performing Technology Organizations",
      "Leviathan Wakes",
      "Abaddon's Gate",
      "Common Title"
    ]).destroy_all
    Author.where(name: [ "James S.A. Corey", "James S. A. Corey", "Different Person" ]).destroy_all
  end

  # Strategy 1: exact title (case-insensitive), single candidate.

  test "exact title match returns the book" do
    assert_equal @leviathan, BookMatcher.match(title: "Leviathan Wakes", author: nil)
  end

  test "exact title match is case-insensitive" do
    assert_equal @leviathan, BookMatcher.match(title: "leviathan wakes", author: nil)
    assert_equal @leviathan, BookMatcher.match(title: "LEVIATHAN WAKES", author: nil)
  end

  test "exact title with author returns the book" do
    assert_equal @leviathan, BookMatcher.match(title: "Leviathan Wakes", author: "James S.A. Corey")
  end

  # Strategy 1b: ambiguous exact title narrows by normalized author.

  test "ambiguous exact title narrows by author" do
    result = BookMatcher.match(title: "Common Title", author: "James S.A. Corey")
    assert_equal @same_title_b, result
  end

  test "ambiguous exact title narrows by author with different spacing" do
    # @same_title_b's author is "James S.A. Corey"; the query asks for
    # "James S. A. Corey" — both normalize to "james sa corey".
    result = BookMatcher.match(title: "Common Title", author: "James S. A. Corey")
    assert_equal @same_title_b, result
  end

  test "ambiguous exact title without an author returns nil" do
    # Two books with the title "Common Title" and no author hint —
    # don't guess.
    assert_nil BookMatcher.match(title: "Common Title", author: nil)
  end

  test "ambiguous exact title with an unmatched author returns nil" do
    # No candidate has this author, so author narrowing fails, and the
    # title-prefix fallback can't disambiguate either.
    assert_nil BookMatcher.match(title: "Common Title", author: "Nobody Important")
  end

  # Strategy 2: subtitle-tolerant title prefix match. Lists often carry
  # just the main title ("Accelerate") while Calibre has the full
  # title with subtitle ("Accelerate: Building and Scaling...").

  test "subtitle-tolerant prefix match using colon" do
    assert_equal @accelerate, BookMatcher.match(title: "Accelerate", author: nil)
  end

  test "subtitle-tolerant prefix match works with author given" do
    assert_equal @accelerate, BookMatcher.match(title: "Accelerate", author: "Different Person")
  end

  test "subtitle-tolerant prefix refuses bases shorter than 4 chars" do
    # "Lev" alone is too short — prevents false positives from
    # tiny prefixes ("of " would otherwise match a lot of books).
    assert_nil BookMatcher.match(title: "Lev", author: nil)
  end

  test "subtitle-tolerant prefix works with em-dash separator" do
    # Different Person — Hobbies → first segment is "Different Person"
    # Not actually tested against a real em-dash title here; just
    # confirms the regex tolerates the character.
    book = make_book("Bookcraft — Subtitle Here", [ @other ])
    begin
      assert_equal book, BookMatcher.match(title: "Bookcraft", author: nil)
    ensure
      book.destroy
    end
  end

  test "subtitle-tolerant prefix narrows by author when multiple match" do
    extra = make_book("Acceleration: Other Subtitle", [ @corey1 ])
    begin
      # Prefix "Accelerat" matches both @accelerate and extra.
      # With author "James S.A. Corey", only `extra` qualifies.
      result = BookMatcher.match(title: "Acceleration", author: "James S.A. Corey")
      assert_equal extra, result
    ensure
      extra.destroy
    end
  end

  # No match cases.

  test "unknown title returns nil" do
    assert_nil BookMatcher.match(title: "Nonexistent Book", author: nil)
  end

  test "empty title returns nil" do
    assert_nil BookMatcher.match(title: "", author: "Anyone")
    assert_nil BookMatcher.match(title: nil, author: "Anyone")
  end

  test "whitespace-only title returns nil" do
    assert_nil BookMatcher.match(title: "   ", author: nil)
  end

  # Robustness.

  test "leading/trailing whitespace in title is tolerated" do
    assert_equal @leviathan, BookMatcher.match(title: "  Leviathan Wakes  ", author: nil)
  end

  test "leading/trailing whitespace in author is tolerated" do
    result = BookMatcher.match(title: "Common Title", author: "  James S.A. Corey  ")
    assert_equal @same_title_b, result
  end

  private

  def make_book(title, authors)
    book = Book.create!(
      title:       title,
      path:        "test/#{title.parameterize}",
      file_name:   title.parameterize,
      file_format: "EPUB",
      imported_at: Time.current
    )
    authors.each_with_index do |author, i|
      book.book_authors.create!(author: author, position: i)
    end
    book
  end
end
