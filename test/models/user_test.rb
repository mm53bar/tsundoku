require "test_helper"

class UserTest < ActiveSupport::TestCase
  # All current authorization rules collapse to `admin?`, but naming each
  # capability separately at the callsite is the point — these tests fix
  # the mapping so a future split (e.g., "editor" role between reader and
  # admin) gets reviewable diffs instead of silent behavior changes.
  test "admin user can do all admin actions" do
    admin = users(:admin)
    assert admin.admin?
    assert admin.can_import_library?
    assert admin.can_ingest?
    assert admin.can_edit_book?
    assert admin.can_destroy_book?
    assert admin.can_enrich_book?
    assert admin.can_manage_lists?
    assert admin.can_edit_list?
  end

  test "reader user is denied admin actions" do
    reader = users(:reader)
    refute reader.admin?
    refute reader.can_import_library?
    refute reader.can_ingest?
    refute reader.can_edit_book?
    refute reader.can_destroy_book?
    refute reader.can_enrich_book?
    refute reader.can_manage_lists?
    refute reader.can_edit_list?
  end

  test "book-scoped predicates accept the book argument" do
    # Today the predicate ignores the argument, but the signature exists
    # so callers can pass a book and we have room to refine per-book
    # ownership later.
    admin = users(:admin)
    book = Book.new(title: "T", path: "x", imported_at: Time.current)
    assert admin.can_edit_book?(book)
    assert admin.can_destroy_book?(book)
    assert admin.can_enrich_book?(book)
  end

  test "list-scoped predicate accepts the list argument" do
    admin = users(:admin)
    list = List.new(name: "Test list")
    assert admin.can_edit_list?(list)
  end

  test "display_name prefers name when set" do
    user = User.new(name: "Mike", username: "mmcclenaghan")
    assert_equal "Mike", user.display_name
  end

  test "display_name falls back to username when name is blank" do
    user = User.new(name: "", username: "mmcclenaghan")
    assert_equal "mmcclenaghan", user.display_name
  end

  test "display_name falls back to username when name is nil" do
    user = User.new(name: nil, username: "mmcclenaghan")
    assert_equal "mmcclenaghan", user.display_name
  end
end
