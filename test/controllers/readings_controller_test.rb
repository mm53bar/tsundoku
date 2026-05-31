require "test_helper"

class ReadingsControllerTest < ActionDispatch::IntegrationTest
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

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
    @user.readings.where(book: @book).destroy_all
    @book.destroy
  end

  # Mark finished.

  test "mark_finished=1 forces progress to 100 and stamps finished_at" do
    @user.readings.create!(book: @book, progress_percent: 30)
    patch book_reading_path(@book),
          params:  { reading: { mark_finished: "1" } },
          headers: headers_for(@user)
    r = @user.readings.find_by(book: @book)
    assert_equal 100, r.progress_percent
    assert_not_nil r.finished_at
    assert r.finished?
  end

  test "mark_finished=1 works for a book with no prior reading record" do
    # "I read this on paper" case.
    assert_difference -> { @user.readings.where(book: @book).count }, 1 do
      patch book_reading_path(@book),
            params:  { reading: { mark_finished: "1" } },
            headers: headers_for(@user)
    end
    r = @user.readings.find_by(book: @book)
    assert r.finished?
  end

  test "mark_finished=0 clears finished_at without touching progress" do
    @user.readings.create!(book: @book, progress_percent: 100, finished_at: 1.day.ago)
    patch book_reading_path(@book),
          params:  { reading: { mark_finished: "0" } },
          headers: headers_for(@user)
    r = @user.readings.find_by(book: @book)
    assert_nil r.finished_at
    # Progress stays — the next sync from the device will overwrite if
    # the user opened the book again.
    assert_equal 100, r.progress_percent
  end

  # Destroy.

  test "destroy removes the Reading record" do
    @user.readings.create!(book: @book, progress_percent: 30)
    delete book_reading_path(@book), headers: headers_for(@user)
    assert_nil @user.readings.find_by(book: @book)
  end

  test "destroy is idempotent when there's no Reading" do
    assert_nothing_raised do
      delete book_reading_path(@book), headers: headers_for(@user)
    end
  end
end
