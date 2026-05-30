require "test_helper"

# The kobo_uuid snapshot is the linchpin of the post-destroy tombstone
# flow: after Book.destroy nullifies book_id on these rows, the snapshot
# is the only thing that lets SyncController emit a tombstone for the
# device. These tests pin the invariant so a future refactor that
# accidentally clears or skips the snapshot fails loudly.
class KoboSyncedBookTest < ActiveSupport::TestCase
  setup do
    @user = users(:reader)
    @book = Book.create!(
      title:       "Tombstone Test",
      path:        "tombstone/test",
      file_name:   "tombstone",
      file_format: "EPUB",
      imported_at: Time.current
    )
  end

  teardown do
    @user.kobo_synced_books.destroy_all
    @book.destroy if @book.persisted?
  end

  test "kobo_uuid is snapshotted from the book on create" do
    ksb = @user.kobo_synced_books.create!(book: @book)
    assert_equal @book.kobo_uuid, ksb.kobo_uuid
  end

  test "explicit kobo_uuid passed at create wins over the snapshot" do
    ksb = @user.kobo_synced_books.create!(book: @book, kobo_uuid: "explicit-uuid")
    assert_equal "explicit-uuid", ksb.kobo_uuid
  end

  test "kobo_uuid is required" do
    ksb = @user.kobo_synced_books.build(book_id: nil)
    refute ksb.valid?
    assert ksb.errors[:kobo_uuid].present?
  end

  test "book_id can be nil after Book destroy, retaining kobo_uuid" do
    ksb = @user.kobo_synced_books.create!(book: @book)
    snapshot = ksb.kobo_uuid

    @book.destroy
    @book = Book.new # stop teardown from trying to destroy it twice

    ksb.reload
    assert_nil ksb.book_id
    assert_equal snapshot, ksb.kobo_uuid
  end

  test "the belongs_to :book association sees through soft state" do
    # This isn't soft-delete anymore but: the row needs to survive after
    # destroy and reconciliation logic queries `record.book_id` directly,
    # which the test above covers. This test just confirms book is nil
    # (not raising) when book_id is nil.
    ksb = @user.kobo_synced_books.create!(book: @book)
    @book.destroy
    @book = Book.new
    assert_nil ksb.reload.book
  end

  test "uniqueness on (user_id, book_id) is enforced when book_id is set" do
    @user.kobo_synced_books.create!(book: @book)
    dup = @user.kobo_synced_books.build(book: @book)
    refute dup.valid?
  end

  test "multiple tombstone-only rows (book_id NULL) for the same user are allowed" do
    # Two different books destroyed → two different tombstones queued. The
    # uniqueness scope on (user_id, book_id) is skipped when book_id is
    # nil so these don't collide.
    @user.kobo_synced_books.create!(book_id: nil, kobo_uuid: "ghost-1")
    second = @user.kobo_synced_books.build(book_id: nil, kobo_uuid: "ghost-2")
    assert second.valid?
  end
end
