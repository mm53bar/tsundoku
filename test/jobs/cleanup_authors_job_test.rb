require "test_helper"

class CleanupAuthorsJobTest < ActiveJob::TestCase
  # Each test seeds a few Author + Book rows in one of the dirty
  # shapes the on-demand cleanup is meant to fix, then runs the job
  # and asserts the post-state. The job's responsibility under test is
  # the reshape — drop / rename / merge / split — not the
  # AuthorNameNormalizer itself (covered separately).

  setup do
    Reading.delete_all
    BookAuthor.delete_all
    BookIdentifier.delete_all
    Book.destroy_all
    Author.destroy_all
    Task.delete_all
  end

  test "drops authors that normalize to a placeholder" do
    ghost = Author.create!(name: "Unknown Author")
    book  = make_book("Anonymous")
    book.book_authors.create!(author: ghost, position: 0)

    perform_job

    refute Author.exists?(ghost.id), "placeholder author should be destroyed"
    assert_empty book.reload.book_authors
  end

  test "renames an author whose cleaned name is different but unique" do
    author = Author.create!(name: "Andy Weir;")
    book   = make_book("The Martian")
    book.book_authors.create!(author: author, position: 0)

    perform_job

    assert_equal "Andy Weir", author.reload.name
    assert_equal [ author.id ], book.reload.book_authors.pluck(:author_id)
  end

  test "merges into an existing author when the cleaned name collides" do
    canonical = Author.create!(name: "Andy Weir")
    duplicate = Author.create!(name: "Andy Weir;")
    canonical_book = make_book("Project Hail Mary")
    duplicate_book = make_book("The Martian")
    canonical_book.book_authors.create!(author: canonical, position: 0)
    duplicate_book.book_authors.create!(author: duplicate, position: 0)

    perform_job

    refute Author.exists?(duplicate.id), "duplicate row should be merged away"
    assert_equal [ canonical.id ], canonical_book.reload.book_authors.pluck(:author_id)
    assert_equal [ canonical.id ], duplicate_book.reload.book_authors.pluck(:author_id)
  end

  test "splits a joined-multi-author row into separate authors" do
    joined = Author.create!(name: "Eric Freeman| Elisabeth Robson| Bert Bates")
    book   = make_book("Head First Design Patterns")
    book.book_authors.create!(author: joined, position: 0)

    perform_job

    refute Author.exists?(joined.id), "joined row should be destroyed after split"
    names = book.reload.book_authors.order(:position).map { |ba| ba.author.name }
    assert_equal [ "Eric Freeman", "Elisabeth Robson", "Bert Bates" ], names
  end

  test "splits Last-First paired rows into reversed individual authors" do
    paired = Author.create!(name: "Ignatieff| Michael| Hardy| Henry| Berlin| Isaiah")
    book   = make_book("On Liberty")
    book.book_authors.create!(author: paired, position: 0)

    perform_job

    refute Author.exists?(paired.id)
    names = book.reload.book_authors.order(:position).map { |ba| ba.author.name }
    assert_equal [ "Michael Ignatieff", "Henry Hardy", "Isaiah Berlin" ], names
  end

  test "split doesn't double-link a book already attached to one of the split targets" do
    # Pre-existing canonical row + a dirty row that includes it.
    existing = Author.create!(name: "Sandi Metz")
    joined   = Author.create!(name: "Sandi Metz| Katrina Owen")
    book     = make_book("99 Bottles of OOP")
    book.book_authors.create!(author: existing, position: 0)
    book.book_authors.create!(author: joined,   position: 1)

    perform_job

    refute Author.exists?(joined.id)
    names = book.reload.book_authors.order(:position).map { |ba| ba.author.name }
    assert_equal [ "Sandi Metz", "Katrina Owen" ], names
  end

  test "leaves clean authors unchanged" do
    author = Author.create!(name: "Madeline Miller", hardcover_slug: "madeline-miller")
    book   = make_book("Circe")
    book.book_authors.create!(author: author, position: 0)

    perform_job

    assert_equal "Madeline Miller", author.reload.name
    assert_equal "madeline-miller", author.hardcover_slug
  end

  test "records stats in the Task result_data" do
    Author.create!(name: "Unknown Author")
    Author.create!(name: "Andy Weir;")
    Author.create!(name: "Madeline Miller")

    task = perform_job
    assert_equal "succeeded", task.reload.status
    assert_equal 1, task.result["dropped"]
    assert_equal 1, task.result["renamed"]
    assert_equal 1, task.result["unchanged"]
  end

  private

  def perform_job
    task = Task.create!(kind: "author_cleanup", status: :queued)
    CleanupAuthorsJob.perform_now(task.id)
    task
  end

  def make_book(title)
    Book.create!(
      title:       title,
      path:        "test/#{title.parameterize}-#{SecureRandom.hex(3)}",
      file_name:   title.parameterize,
      file_format: "EPUB",
      imported_at: Time.current
    )
  end
end
