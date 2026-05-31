require "test_helper"
require "fileutils"
require "tmpdir"

# Request-level coverage of the diff-based sync at /kobo/:handle/v1/library/sync
# and the per-book metadata fetch at /kobo/:handle/v1/library/:book_uuid/metadata.
# Each test re-roots LIBRARY_PATH at a fresh tmpdir and lays down a real EPUB
# byte on disk so Book#assets.epub_downloadable? returns true — that filter is
# the most fragile part of the sync path (a book without the file silently
# drops out of the payload) and the easiest one to regress.
class Kobo::SyncControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tmp = Dir.mktmpdir("kobo_sync_test")
    @original_library = Rails.configuration.x.library_path
    Rails.configuration.x.library_path = @tmp

    @user = users(:reader) # kobo_handle: "reader-handle"
  end

  teardown do
    Rails.configuration.x.library_path = @original_library
    FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
    KoboSyncedBook.delete_all
    KoboSyncedShelf.delete_all
    ShelfEntry.delete_all
    Shelf.delete_all
    Reading.delete_all
    Book.destroy_all
  end

  # Auth — kobo routes skip Authelia and use the handle in the URL.

  test "unknown handle returns 401" do
    get "/kobo/no-such-handle/v1/library/sync"
    assert_response :unauthorized
  end

  # New entitlements — book is syncable, no kobo_synced_books row yet.

  test "sync emits NewEntitlement and creates a tracking row for a fresh syncable book" do
    book = downloadable_book(title: "Fresh Book")
    @user.readings.create!(book: book, sync_to_device: true)

    assert_difference -> { @user.kobo_synced_books.count }, 1 do
      get sync_path
    end
    assert_response :success

    payload = response_json
    new_envelopes = payload.filter_map { |entry| entry["NewEntitlement"] }
    assert_equal 1, new_envelopes.size
    assert_equal book.kobo_uuid, new_envelopes.first.dig("BookEntitlement", "Id")
    assert_equal "Active",       new_envelopes.first.dig("BookEntitlement", "Status")
  end

  # Unchanged — already synced and book.updated_at <= record.updated_at.

  test "sync emits nothing for a previously-synced book whose updated_at hasn't moved" do
    book = downloadable_book(title: "Already Synced")
    @user.readings.create!(book: book, sync_to_device: true)
    @user.kobo_synced_books.create!(book: book)
    # Force the snapshot row's updated_at to be after the book's.
    @user.kobo_synced_books.find_by(book: book).touch

    get sync_path
    assert_response :success
    assert_empty response_json
  end

  # Changed — book.updated_at > record.updated_at.

  test "sync emits ChangedEntitlement and touches the snapshot when the book moves forward" do
    book = downloadable_book(title: "Touched")
    @user.readings.create!(book: book, sync_to_device: true)
    record = @user.kobo_synced_books.create!(book: book)
    # Reading is touched on every save and bumps book.updated_at via
    # the touch: true association — simulate that.
    book.touch
    record.update_columns(updated_at: 1.hour.ago)

    get sync_path
    assert_response :success

    payload = response_json
    changed = payload.filter_map { |entry| entry["ChangedEntitlement"] }.find do |envelope|
      envelope.dig("BookEntitlement", "Id") == book.kobo_uuid &&
        envelope.dig("BookEntitlement", "IsRemoved") != true
    end
    assert changed, "expected a non-tombstone ChangedEntitlement for #{book.kobo_uuid}"
  end

  # Tombstone — book is no longer in syncable_books (reading unsynced, removed
  # from shelf, etc.) but the per-user snapshot row still exists.

  test "sync emits a tombstone ChangedEntitlement when a book drops out of syncable_books" do
    book   = downloadable_book(title: "Tombstoned")
    record = @user.kobo_synced_books.create!(book: book)
    # No Reading, no Shelf membership — book is in DB but not syncable.

    assert_difference -> { @user.kobo_synced_books.count }, -1 do
      get sync_path
    end
    assert_response :success

    tombstones = response_json.filter_map { |entry| entry["ChangedEntitlement"] }
                              .select { |env| env.dig("BookEntitlement", "IsRemoved") == true }
    assert_equal 1, tombstones.size
    assert_equal record.kobo_uuid, tombstones.first.dig("BookEntitlement", "Id")
  end

  # Tombstone — book was hard-destroyed; book_id is NULL on the snapshot row.

  test "sync emits a tombstone for a snapshot whose book was destroyed" do
    book = downloadable_book(title: "About to die")
    @user.kobo_synced_books.create!(book: book)
    snapshot_uuid = book.kobo_uuid
    book.destroy # nullifies kobo_synced_books.book_id but leaves the row + snapshot uuid

    get sync_path
    assert_response :success

    tombstones = response_json.filter_map { |entry| entry["ChangedEntitlement"] }
                              .select { |env| env.dig("BookEntitlement", "IsRemoved") == true }
    assert tombstones.any? { |env| env.dig("BookEntitlement", "Id") == snapshot_uuid },
           "expected a tombstone with the snapshot uuid"
  end

  # Filter — books whose EPUB isn't on disk silently drop out (the device
  # would 404 on download otherwise). The point of this test is to make sure
  # that filter never moves to the wrong side of the cache/loader change.

  test "sync excludes a book whose EPUB is not on disk" do
    book = Book.create!(
      title:       "Ghost",
      path:        "Author/Ghost (?)",
      file_name:   "ghost",
      file_format: "EPUB",
      imported_at: Time.current
    )
    @user.readings.create!(book: book, sync_to_device: true)

    get sync_path
    assert_response :success
    payload = response_json
    refute payload.any? { |e| e.dig("NewEntitlement", "BookEntitlement", "Id") == book.kobo_uuid },
           "Ghost book should be excluded — no EPUB on disk"
  end

  # Tags / shelves — same diff shape.

  test "sync emits NewTag for a fresh syncing shelf" do
    shelf = @user.shelves.create!(name: "Bedside", sync_to_kobo: true)

    get sync_path
    assert_response :success

    new_tags = response_json.filter_map { |entry| entry["NewTag"] }
    assert_equal 1, new_tags.size
    assert_equal shelf.kobo_uuid, new_tags.first.dig("Tag", "Id")
    assert_equal "Bedside",       new_tags.first.dig("Tag", "Name")
  end

  test "sync emits DeletedTag when a shelf stops syncing and removes the snapshot" do
    shelf = @user.shelves.create!(name: "Was syncing", sync_to_kobo: true)
    @user.kobo_synced_shelves.create!(shelf_id: shelf.id, kobo_uuid: shelf.kobo_uuid)
    shelf.update!(sync_to_kobo: false)

    assert_difference -> { @user.kobo_synced_shelves.count }, -1 do
      get sync_path
    end
    assert_response :success

    deleted = response_json.filter_map { |entry| entry["DeletedTag"] }
    assert_equal 1, deleted.size
    assert_equal shelf.kobo_uuid, deleted.first.dig("Tag", "Id")
  end

  # Metadata — fetched after sync, before download.

  test "metadata returns the book payload for a syncable book by kobo_uuid" do
    book = downloadable_book(title: "Detail")
    @user.readings.create!(book: book, sync_to_device: true)

    get "/kobo/#{@user.kobo_handle}/v1/library/#{book.kobo_uuid}/metadata"
    assert_response :success

    payload = response_json
    assert_kind_of Array, payload, "metadata response is wrapped in an array (the device errors on a bare object)"
    assert_equal book.kobo_uuid, payload.first["EntitlementId"]
    assert_equal "Detail",       payload.first["Title"]
  end

  test "metadata returns 404 for a kobo_uuid the user does not own" do
    get "/kobo/#{@user.kobo_handle}/v1/library/00000000-0000-0000-0000-000000000000/metadata"
    assert_response :not_found
  end

  # Self-healing for ghost entitlements: the device asks for a book it knows
  # about but we don't currently sync. Track it so the next /sync emits a
  # tombstone and the device archives it.

  test "metadata creates a tracking row for an orphan UUID that exists in DB but isn't syncable" do
    book = downloadable_book(title: "Orphan")
    # Book exists, no Reading and no syncing Shelf entry.

    assert_difference -> { @user.kobo_synced_books.count }, 1 do
      get "/kobo/#{@user.kobo_handle}/v1/library/#{book.kobo_uuid}/metadata"
    end
    assert_response :not_found
  end

  # DELETE /v1/library/:book_uuid — auto-recovery for manual device wipes.
  # The device announces each book it just removed; we remove the matching
  # KoboSyncedBook snapshot so the next sync diff re-emits NewEntitlement
  # for books that are still in syncable_books. Sheila's "I wiped my Kobo
  # and it didn't restore everything" scenario from 2026-05-31 is the
  # motivating case.

  test "DELETE library/:book_uuid removes the snapshot row for that uuid" do
    book = downloadable_book(title: "About to be wiped")
    @user.readings.create!(book: book, sync_to_device: true)
    @user.kobo_synced_books.create!(book: book)

    assert_difference -> { @user.kobo_synced_books.count }, -1 do
      delete "/kobo/#{@user.kobo_handle}/v1/library/#{book.kobo_uuid}"
    end
    assert_response :success
  end

  test "DELETE library/:book_uuid is idempotent for an unknown uuid" do
    # Device sometimes sends DELETEs for UUIDs we never tracked
    # (cross-Kobo state mismatch). Don't 404, don't blow up.
    assert_no_difference -> { @user.kobo_synced_books.count } do
      delete "/kobo/#{@user.kobo_handle}/v1/library/00000000-0000-0000-0000-000000000000"
    end
    assert_response :success
  end

  test "DELETE library/:book_uuid leaves snapshots for other books alone" do
    keep   = downloadable_book(title: "Keep me")
    wipe   = downloadable_book(title: "Wipe me")
    @user.readings.create!(book: keep, sync_to_device: true)
    @user.readings.create!(book: wipe, sync_to_device: true)
    @user.kobo_synced_books.create!(book: keep)
    @user.kobo_synced_books.create!(book: wipe)

    delete "/kobo/#{@user.kobo_handle}/v1/library/#{wipe.kobo_uuid}"
    assert_response :success

    assert @user.kobo_synced_books.exists?(book: keep), "the other snapshot should survive"
    refute @user.kobo_synced_books.exists?(book: wipe)
  end

  test "DELETE then sync emits a NewEntitlement for the still-syncable book (full wipe-recovery loop)" do
    book = downloadable_book(title: "Wipe and restore")
    @user.readings.create!(book: book, sync_to_device: true)
    @user.kobo_synced_books.create!(book: book)

    # Simulate the device wiping the book locally.
    delete "/kobo/#{@user.kobo_handle}/v1/library/#{book.kobo_uuid}"
    assert_response :success

    # The very next sync should re-emit NewEntitlement so the device
    # downloads the book back.
    get sync_path
    assert_response :success

    new_envelopes = response_json.filter_map { |entry| entry["NewEntitlement"] }
    assert new_envelopes.any? { |env| env.dig("BookEntitlement", "Id") == book.kobo_uuid },
           "expected a NewEntitlement for the just-deleted book after the next sync"
  end

  private

  def sync_path
    "/kobo/#{@user.kobo_handle}/v1/library/sync"
  end

  def response_json
    JSON.parse(response.body)
  end

  # Create a Book whose .assets.epub_downloadable? is true — i.e. a real
  # (empty) file sitting at the path the model resolves to.
  def downloadable_book(title:)
    safe = title.gsub(/\W/, "_")
    relative_dir = "Author/#{safe}"
    FileUtils.mkdir_p(File.join(@tmp, relative_dir))
    File.write(File.join(@tmp, relative_dir, "#{safe}.epub"), "fake epub bytes")

    Book.create!(
      title:       title,
      path:        relative_dir,
      file_name:   safe,
      file_format: "EPUB",
      imported_at: Time.current
    )
  end
end
