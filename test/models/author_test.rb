require "test_helper"

class AuthorTest < ActiveSupport::TestCase
  # normalize_name is the canonical form used by BookEnricher, BookMatcher,
  # and BooksController#update to dedupe authors across sources. The cases
  # below are the ones the comment on Author.normalize_name calls out, plus
  # a handful of regression-bait variants.
  test "different spacings of the same initials hash identically" do
    a = Author.normalize_name("James S.A. Corey")
    b = Author.normalize_name("James S. A. Corey")
    c = Author.normalize_name("James S A Corey")
    assert_equal a, b
    assert_equal b, c
    assert_equal "james sa corey", a
  end

  test "strips trailing PhD honorific (without a comma)" do
    assert_equal "jane goodall", Author.normalize_name("Jane Goodall Ph.D.")
  end

  test "strips trailing honorific even with a preceding comma" do
    assert_equal "jane goodall", Author.normalize_name("Jane Goodall, Ph.D.")
    assert_equal "homer s",      Author.normalize_name("Homer S, Jr.")
  end

  test "strips trailing Jr/Sr/II/III/IV" do
    assert_equal "homer s",   Author.normalize_name("Homer S Jr.")
    assert_equal "homer s",   Author.normalize_name("Homer S Sr.")
    assert_equal "homer",     Author.normalize_name("Homer III")
    assert_equal "homer",     Author.normalize_name("Homer IV")
  end

  test "handles nil and blank input" do
    assert_equal "", Author.normalize_name(nil)
    assert_equal "", Author.normalize_name("")
    assert_equal "", Author.normalize_name("   ")
  end

  test "lowercases and collapses whitespace" do
    assert_equal "george orwell",
                 Author.normalize_name("  George   Orwell  ")
  end

  test "names with no initials are unchanged apart from case/whitespace" do
    assert_equal "ursula k le guin",
                 Author.normalize_name("Ursula K. Le Guin")
  end

  test "single-letter prefix and surname are kept separate" do
    # K LeGuin only has one initial, so it should remain as its own token,
    # not merge with anything (no neighbouring initials to absorb).
    assert_equal "k leguin", Author.normalize_name("K. LeGuin")
  end

  test "normalized_name delegates to the class method" do
    a = Author.new(name: "James S.A. Corey")
    assert_equal Author.normalize_name(a.name), a.normalized_name
  end
end
