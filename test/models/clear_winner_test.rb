require "test_helper"

class ClearWinnerTest < ActiveSupport::TestCase
  def hit(id, title, authors, users: 100, compilation: false, alternative_titles: [])
    HardcoverHit.new(id: id, title: title, author_names: authors, users_count: users,
                     compilation: compilation, alternative_titles: alternative_titles)
  end

  test "a single title match wins" do
    hits = [ hit(1, "Project Hail Mary", [ "Andy Weir" ]), hit(2, "The Martian", [ "Andy Weir" ]) ]
    assert_equal 1, ClearWinner.new(hits, title: "project hail mary").hit.id
  end

  test "title matching ignores punctuation and subtitles on either side" do
    hits = [ hit(1, "Accelerate: Building and Scaling High Performing Technology Organizations", [ "Nicole Forsgren" ]) ]
    assert_equal 1, ClearWinner.new(hits, title: "Accelerate").hit.id

    hits = [ hit(2, "Dont Make Me Think", [ "Steve Krug" ]) ]
    assert_equal 2, ClearWinner.new(hits, title: "Don't Make Me Think: Revisited").hit.id
  end

  test "an alternative title counts" do
    hits = [ hit(1, "Harry Potter and the Sorcerer's Stone", [ "J.K. Rowling" ], alternative_titles: [ "Harry Potter and the Philosopher's Stone" ]) ]
    assert_equal 1, ClearWinner.new(hits, title: "Harry Potter and the Philosopher's Stone").hit.id
  end

  test "a typed author must match, by full name or surname" do
    hits = [ hit(1, "Project Hail Mary", [ "Andy Weir" ]), hit(2, "Project Hail Mary", [ "Good Reads Publishing" ], users: 5000) ]
    assert_equal 1, ClearWinner.new(hits, title: "Project Hail Mary", author: "Andy Weir").hit.id
    assert_equal 1, ClearWinner.new(hits, title: "Project Hail Mary", author: "Weir").hit.id
  end

  test "an exact title beats a series prefix in an alternative title" do
    hits = [ hit(1, "Dune", [ "Frank Herbert" ], users: 15000),
             hit(2, "Dune Messiah", [ "Frank Herbert" ], users: 5000, alternative_titles: [ "Dune: Bagian 2" ]) ]
    assert_equal 1, ClearWinner.new(hits, title: "Dune").hit.id
  end

  test "an exact-titled knockoff doesn't beat the real book's subtitled title" do
    hits = [ hit(1, "Atomic Habits: An Easy & Proven Way to Build Good Habits", [ "James Clear" ], users: 6000),
             hit(2, "Atomic Habits", [ "Good Reads Publishing" ], users: 30) ]
    assert_equal 1, ClearWinner.new(hits, title: "Atomic Habits").hit.id
  end

  test "compilations never win" do
    hits = [ hit(1, "Project Hail Mary", [ "Andy Weir" ], compilation: true) ]
    assert_nil ClearWinner.new(hits, title: "Project Hail Mary").hit
    assert_empty ClearWinner.new(hits, title: "Project Hail Mary").suggestions
  end

  test "the most-read candidate wins only with a clear margin" do
    clear = [ hit(1, "The Road", [ "Cormac McCarthy" ], users: 6000), hit(2, "The Road", [ "Someone Else" ], users: 40) ]
    assert_equal 1, ClearWinner.new(clear, title: "The Road").hit.id

    close = [ hit(1, "Common Title", [ "A Writer" ], users: 300), hit(2, "Common Title", [ "B Writer" ], users: 200) ]
    pick = ClearWinner.new(close, title: "Common Title")
    assert_nil pick.hit
    assert_equal [ 1, 2 ], pick.suggestions.map(&:id)
  end

  test "with no title match, the search's own top hits are suggested" do
    hits = (1..5).map { |i| hit(i, "Something #{i}", [ "Writer" ]) }
    pick = ClearWinner.new(hits, title: "Somthing")
    assert_nil pick.hit
    assert_equal [ 1, 2, 3 ], pick.suggestions.map(&:id)
  end
end
