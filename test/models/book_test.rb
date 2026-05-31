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
end
