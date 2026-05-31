require "test_helper"

class BookTest < ActiveSupport::TestCase
  # set_kobo_uuid — runs on every save (not just :create on validation)
  # so callers that do Book.new(...).save!(validate: false) — notably
  # BookIngester, which persists a placeholder row before move_file knows
  # the final path — still end up with a populated kobo_uuid before any
  # subsequent validated save runs.

  test "kobo_uuid is auto-populated on a normal save" do
    book = Book.new(
      title:       "Test Book",
      path:        "test/auto-uuid",
      file_name:   "auto-uuid",
      file_format: "EPUB",
      imported_at: Time.current
    )
    book.save!
    assert_not_nil book.kobo_uuid
  end

  test "kobo_uuid is auto-populated even when validation is skipped" do
    # Regression: BookIngester.create_book persists a placeholder via
    # save!(validate: false) and then runs a validated update! to fill
    # in path. If the UUID isn't set by that first save, the validated
    # update fails with "Kobo uuid can't be blank".
    book = Book.new(
      title:       "Test Book",
      path:        "",
      file_name:   "",
      file_format: "EPUB",
      imported_at: Time.current
    )
    book.save!(validate: false)
    assert_not_nil book.kobo_uuid

    assert_nothing_raised do
      book.update!(path: "test/post-update", file_name: "post-update")
    end
  end

  test "kobo_uuid adopts the Calibre uuid when present" do
    calibre_uuid = SecureRandom.uuid
    book = Book.new(
      title:       "Calibre Book",
      path:        "test/calibre-uuid",
      file_name:   "calibre-uuid",
      file_format: "EPUB",
      imported_at: Time.current,
      uuid:        calibre_uuid
    )
    book.save!
    assert_equal calibre_uuid, book.kobo_uuid
  end

  test "set_kobo_uuid does not overwrite an existing value on update" do
    book = Book.create!(
      title:       "Existing",
      path:        "test/existing",
      file_name:   "existing",
      file_format: "EPUB",
      imported_at: Time.current
    )
    original = book.kobo_uuid
    book.update!(title: "Renamed")
    assert_equal original, book.reload.kobo_uuid
  end

  # match_pending_list_entries — runs on after_commit :create. The motivating
  # case is auto-ingest: a list entry was unmatched at import time because
  # the book wasn't in the library; Shelfmark drops the file later; this
  # hook closes the loop so the list shows "In library" without a manual
  # Re-import.

  test "creating a book back-fills an unmatched list entry with the same title and author" do
    user  = users(:reader)
    list  = user.lists.create!(name: "Pending")
    entry = list.list_entries.create!(position: 0, title: "The Catcher in the Rye", author_name: "J. D. Salinger")
    assert_nil entry.book_id

    # Real ingest attaches authors inside the create transaction so the
    # after_commit hook sees them. Transactional tests don't fire the
    # after_commit (test transaction is rolled back), so we exercise the
    # private method directly.
    book = make_book(title: "The Catcher in the Rye")
    book.book_authors.create!(author: Author.create!(name: "J. D. Salinger"), position: 0)
    book.send(:match_pending_list_entries)

    assert_equal book.id, entry.reload.book_id
  end

  test "creating a book does not touch entries that already have a different book_id" do
    user        = users(:reader)
    other_book  = make_book(title: "Some Other Title")
    list        = user.lists.create!(name: "Already matched")
    entry       = list.list_entries.create!(position: 0, title: "The Great Gatsby", book: other_book)

    new_book = make_book(title: "The Great Gatsby")
    new_book.book_authors.create!(author: Author.create!(name: "F. Scott Fitzgerald"), position: 0)
    new_book.send(:match_pending_list_entries)

    assert_equal other_book.id, entry.reload.book_id
  end

  test "creating a book does not touch entries that resolve to a different book" do
    # Two unmatched entries with the same common title but different
    # author hints. The "popular" candidate book exists already; BookMatcher
    # picks it for both entries (single exact-title match wins regardless
    # of author). When a *new* book with the same title commits, its hook
    # asks BookMatcher who should match — gets the existing book's id,
    # not its own — and correctly leaves both entries alone.
    existing = make_book(title: "Foundation")
    existing.book_authors.create!(author: Author.create!(name: "Isaac Asimov"), position: 0)

    user  = users(:reader)
    list  = user.lists.create!(name: "Mixed")
    entry = list.list_entries.create!(position: 0, title: "Foundation", author_name: "Isaac Asimov", book: existing)

    new_book = make_book(title: "Foundation")
    new_book.book_authors.create!(author: Author.create!(name: "Someone Else"), position: 0)
    new_book.send(:match_pending_list_entries)

    assert_equal existing.id, entry.reload.book_id
  end

  private

  def make_book(title:)
    slug = title.parameterize.first(40)
    Book.create!(
      title:       title,
      path:        "test/#{slug}-#{SecureRandom.hex(4)}",
      file_name:   slug,
      file_format: "EPUB",
      imported_at: Time.current
    )
  end
end
