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

  # progress_state — the core derivation. Pins each cell of the matrix so
  # a regression in the threshold or the precedence rules fails loudly.

  test "progress_state is :not_started when progress is zero or nil" do
    r = @user.readings.create!(book: @book)
    assert_equal :not_started, r.progress_state
    assert r.not_started?
  end

  test "progress_state is :in_progress between 0 and the threshold" do
    r = @user.readings.create!(book: @book, progress_percent: 12)
    assert_equal :in_progress, r.progress_state
    assert r.in_progress?
  end

  test "progress_state is :finished at the threshold" do
    r = @user.readings.create!(book: @book, progress_percent: Reading::FINISHED_THRESHOLD_PCT)
    assert_equal :finished, r.progress_state
    assert r.finished?
  end

  test "progress_state is :finished above the threshold" do
    r = @user.readings.create!(book: @book, progress_percent: 100)
    assert r.finished?
  end

  test "progress_state is :finished when finished_at is set regardless of progress" do
    # "I read this on paper" case — no Kobo progress, but the user
    # marked finished_at explicitly.
    r = @user.readings.create!(book: @book, finished_at: Time.current)
    assert r.finished?
  end

  # stamp_progress_timestamps — automatic via before_save when progress changes.

  test "started_at is stamped the first time progress goes positive" do
    r = @user.readings.create!(book: @book)
    assert_nil r.started_at
    r.update!(progress_percent: 5)
    assert_not_nil r.started_at
  end

  test "started_at is not overwritten on subsequent progress updates" do
    earlier = 2.days.ago
    r = @user.readings.create!(book: @book, progress_percent: 5, started_at: earlier)
    r.update!(progress_percent: 30)
    assert_in_delta earlier.to_i, r.reload.started_at.to_i, 1
  end

  test "finished_at is stamped when progress crosses the threshold" do
    r = @user.readings.create!(book: @book, progress_percent: 10)
    assert_nil r.finished_at
    r.update!(progress_percent: 100)
    assert_not_nil r.finished_at
  end

  test "finished_at is cleared on re-read (progress drops below threshold)" do
    finished = 1.week.ago
    r = @user.readings.create!(book: @book, progress_percent: 100, finished_at: finished)
    r.update!(progress_percent: 12)
    assert_nil r.reload.finished_at
    assert r.in_progress?
  end

  test "started_at survives re-read" do
    earlier = 2.weeks.ago
    r = @user.readings.create!(book: @book, progress_percent: 100, started_at: earlier, finished_at: 1.week.ago)
    r.update!(progress_percent: 12)
    assert_in_delta earlier.to_i, r.reload.started_at.to_i, 1
  end

  # Kobo wire format mapping. Derivation passes through one consistent
  # constant table; tests pin the three states.

  test "kobo_status maps to the device wire format" do
    r = @user.readings.new(book: @book)
    assert_equal "ReadyToRead", r.kobo_status
    r.progress_percent = 12
    assert_equal "Reading", r.kobo_status
    r.progress_percent = 100
    assert_equal "Finished", r.kobo_status
  end

  # SQL scopes mirror progress_state. Pinning prevents a future change to
  # one without the other.

  test "scope :in_progress matches the derivation" do
    in_p     = @user.readings.create!(book: @book, progress_percent: 12)
    not_yet  = @user.readings.create!(book: make_book("Two"))
    finished = @user.readings.create!(book: make_book("Three"), progress_percent: 100)

    ids = Reading.in_progress.pluck(:id)
    assert_includes ids, in_p.id
    assert_not_includes ids, not_yet.id
    assert_not_includes ids, finished.id
  end

  test "scope :finished matches the derivation" do
    in_p     = @user.readings.create!(book: @book, progress_percent: 12)
    finished = @user.readings.create!(book: make_book("Four"), progress_percent: 100)
    by_stamp = @user.readings.create!(book: make_book("Five"), finished_at: Time.current)

    ids = Reading.finished.pluck(:id)
    assert_includes    ids, finished.id
    assert_includes    ids, by_stamp.id
    assert_not_includes ids, in_p.id
  end

  test "scope :not_started matches the derivation" do
    not_yet  = @user.readings.create!(book: @book)
    in_p     = @user.readings.create!(book: make_book("Six"), progress_percent: 12)

    ids = Reading.not_started.pluck(:id)
    assert_includes ids, not_yet.id
    assert_not_includes ids, in_p.id
  end

  # (user, book) uniqueness stays.

  test "(user, book) uniqueness is enforced" do
    @user.readings.create!(book: @book)
    duplicate = @user.readings.build(book: @book)
    refute duplicate.valid?
  end

  # users.in_progress_reading_count — maintained via callbacks. The
  # state machine flips on create/update/destroy according to whether
  # the row's in_progress? value changed. Tests pin each transition so
  # a future refactor of the callback can't silently drift the counter.

  test "creating an in_progress reading increments the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    assert_difference -> { @user.reload.in_progress_reading_count }, 1 do
      @user.readings.create!(book: @book, progress_percent: 50)
    end
  end

  test "creating a not_started reading does not change the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    assert_no_difference -> { @user.reload.in_progress_reading_count } do
      @user.readings.create!(book: @book, progress_percent: 0)
    end
  end

  test "creating a finished reading does not change the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    assert_no_difference -> { @user.reload.in_progress_reading_count } do
      @user.readings.create!(book: @book, finished_at: Time.current)
    end
  end

  test "transitioning to finished decrements the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 50)
    assert_equal 1, @user.reload.in_progress_reading_count

    r.update!(progress_percent: 100)
    assert_equal 0, @user.reload.in_progress_reading_count
  end

  test "re-read (progress drops back) increments the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 100)
    assert_equal 0, @user.reload.in_progress_reading_count

    # The before_save :stamp_progress_timestamps callback clears
    # finished_at on this transition; the counter callback sees both
    # the percent drop and the finished_at clear and increments.
    r.update!(progress_percent: 30)
    assert_equal 1, @user.reload.in_progress_reading_count
  end

  test "progress update within the in_progress range does not double-count" do
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 30)
    r.update!(progress_percent: 60)
    assert_equal 1, @user.reload.in_progress_reading_count
  end

  test "destroying an in_progress reading decrements the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 50)
    assert_equal 1, @user.reload.in_progress_reading_count

    r.destroy
    assert_equal 0, @user.reload.in_progress_reading_count
  end

  test "destroying a not_started reading does not change the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 0)
    assert_no_difference -> { @user.reload.in_progress_reading_count } do
      r.destroy
    end
  end

  test "destroying a finished reading does not change the user counter" do
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 100)
    assert_no_difference -> { @user.reload.in_progress_reading_count } do
      r.destroy
    end
  end

  test "marking finished without a progress change decrements the counter" do
    # Manual "mark finished" — finished_at is set, progress already 50%.
    # Counter should drop from 1 to 0.
    @user.update_columns(in_progress_reading_count: 0)
    r = @user.readings.create!(book: @book, progress_percent: 50)
    assert_equal 1, @user.reload.in_progress_reading_count

    r.update!(finished_at: Time.current, progress_percent: 100)
    assert_equal 0, @user.reload.in_progress_reading_count
  end

  # Display label — derives from progress_state.

  test "status_label maps to friendly text" do
    r = @user.readings.new(book: @book)
    assert_equal "Not started", r.status_label
    r.progress_percent = 30
    assert_equal "Reading", r.status_label
    r.progress_percent = 100
    assert_equal "Finished", r.status_label
  end

  private

  def make_book(label)
    Book.create!(
      title:       "Book #{label}",
      path:        "test/book-#{label.downcase}",
      file_name:   "book-#{label.downcase}",
      file_format: "EPUB",
      imported_at: Time.current
    )
  end
end
