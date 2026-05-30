require "test_helper"

class ReadingTest < ActiveSupport::TestCase
  setup do
    @user = users(:reader)
    @book = Book.create!(
      title:       "Test Book",
      path:        "test/test",
      file_name:   "test",
      file_format: "EPUB",
      imported_at: Time.current
    )
  end

  teardown do
    Reading.where(user: @user, book: @book).destroy_all
    @book.destroy
  end

  # The transitional callback is the bridge between the old "status drives
  # sync" UX and the new "sync_to_device is its own field" model. Behavior
  # has to be steady under all four interesting paths.

  test "creating with want_to_read sets sync_to_device true" do
    r = @user.readings.create!(book: @book, status: :want_to_read)
    assert r.sync_to_device?
  end

  test "creating with currently_reading sets sync_to_device true" do
    r = @user.readings.create!(book: @book, status: :currently_reading)
    assert r.sync_to_device?
  end

  test "creating with read sets sync_to_device false" do
    r = @user.readings.create!(book: @book, status: :read)
    refute r.sync_to_device?
  end

  test "explicit sync_to_device wins over the status mapping" do
    # Status says "read" (would map to sync_to_device=false), but the
    # caller asked for sync anyway — respect it. This is the CWA import
    # path: books finished on the device but still wanted on the device.
    r = @user.readings.create!(book: @book, status: :read, sync_to_device: true)
    assert r.sync_to_device?
  end

  test "status change flips sync_to_device along the legacy mapping" do
    r = @user.readings.create!(book: @book, status: :want_to_read)
    assert r.sync_to_device?

    r.update!(status: :read)
    refute r.sync_to_device?

    r.update!(status: :currently_reading)
    assert r.sync_to_device?
  end

  test "kobo_status maps to the device wire format" do
    r = @user.readings.new(book: @book, status: :want_to_read)
    assert_equal "ReadyToRead", r.kobo_status
    r.status = :currently_reading
    assert_equal "Reading", r.kobo_status
    r.status = :read
    assert_equal "Finished", r.kobo_status
  end

  test "tsundoku_status_for reverses kobo_status" do
    assert_equal "want_to_read",      Reading.tsundoku_status_for("ReadyToRead")
    assert_equal "currently_reading", Reading.tsundoku_status_for("Reading")
    assert_equal "read",              Reading.tsundoku_status_for("Finished")
    assert_nil Reading.tsundoku_status_for("Unknown")
  end

  test "(user, book) uniqueness is enforced" do
    @user.readings.create!(book: @book, status: :want_to_read)
    duplicate = @user.readings.build(book: @book, status: :currently_reading)
    refute duplicate.valid?
  end
end
