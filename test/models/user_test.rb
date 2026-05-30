require "test_helper"

class UserTest < ActiveSupport::TestCase
  # Predicates are passive in this homelab deployment — every signed-in
  # household member is trusted (Authelia gates the door). Tests pin
  # "true for any User, falsy via &. for nil" so a future tightening
  # gets a reviewable diff. can_edit_list? becomes a real ownership
  # check when Lists carry user_id (commit 2 of this refactor); the
  # test below currently asserts the passive shape.
  test "any signed-in user can do all currently-gated actions" do
    # can_edit_list? is excluded — it's a real ownership check tested
    # separately. The rest are passive in this homelab deployment.
    [ users(:admin), users(:reader) ].each do |user|
      assert user.can_import_library?, "#{user.username} can_import_library?"
      assert user.can_ingest?,          "#{user.username} can_ingest?"
      assert user.can_edit_book?,       "#{user.username} can_edit_book?"
      assert user.can_destroy_book?,    "#{user.username} can_destroy_book?"
      assert user.can_enrich_book?,     "#{user.username} can_enrich_book?"
      assert user.can_manage_lists?,    "#{user.username} can_manage_lists?"
    end
  end

  test "nil-safe via current_user&.can_X?" do
    # Controllers and views call predicates with `current_user&.can_X?`.
    # Confirm the &. shape returns nil (falsy) for an anonymous request.
    no_user = nil
    refute no_user&.can_import_library?
    refute no_user&.can_edit_book?
  end

  test "book-scoped predicates accept the book argument" do
    admin = users(:admin)
    book = Book.new(title: "T", path: "x", imported_at: Time.current)
    assert admin.can_edit_book?(book)
    assert admin.can_destroy_book?(book)
    assert admin.can_enrich_book?(book)
  end

  test "can_edit_list? is an ownership check" do
    admin  = users(:admin)
    reader = users(:reader)
    admin_list = admin.lists.create!(name: "Admin's list")

    assert admin.can_edit_list?(admin_list),  "owner can edit"
    refute reader.can_edit_list?(admin_list), "non-owner cannot edit"
    refute admin.can_edit_list?(nil),          "nil list is not editable"
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

  # find_or_provision_from_proxy is the identity boundary for the proxy-
  # auth flow: every request injects Remote-User and we look up or create
  # a user. These tests pin the rules so the boundary stays stable.
  test "provisions a new user from proxy headers" do
    User.where(username: "newcomer").destroy_all
    user = User.find_or_provision_from_proxy(
      username: "newcomer",
      email:    "newcomer@example.com",
      name:     "New Comer"
    )
    assert user.persisted?
    assert_equal "newcomer", user.username
    assert_equal "newcomer@example.com", user.email
    assert_equal "New Comer", user.name
  end

  test "first ever provisioned user gets the admin role" do
    User.destroy_all
    user = User.find_or_provision_from_proxy(username: "first", email: nil, name: nil)
    assert user.admin?
  end

  test "subsequent provisioned users default to reader" do
    User.destroy_all
    User.create!(username: "existing", role: :admin)
    user = User.find_or_provision_from_proxy(username: "second", email: nil, name: nil)
    refute user.admin?
    assert user.reader?
  end

  test "name defaults to titleized username when blank" do
    User.where(username: "yetanother").destroy_all
    user = User.find_or_provision_from_proxy(username: "yetanother", email: nil, name: nil)
    assert_equal "Yetanother", user.name
  end

  test "updates email and name on subsequent lookups when they change" do
    User.where(username: "returning").destroy_all
    User.create!(username: "returning", email: "old@example.com", name: "Old Name", role: :reader)
    user = User.find_or_provision_from_proxy(
      username: "returning",
      email:    "new@example.com",
      name:     "New Name"
    )
    assert_equal "new@example.com", user.email
    assert_equal "New Name",        user.name
  end

  test "preserves existing email/name when the proxy doesn't send them" do
    User.where(username: "sticky").destroy_all
    User.create!(username: "sticky", email: "keep@example.com", name: "Keep Me", role: :reader)
    user = User.find_or_provision_from_proxy(username: "sticky", email: nil, name: nil)
    assert_equal "keep@example.com", user.email
    assert_equal "Keep Me",          user.name
  end

  test "does not change the role on subsequent lookups" do
    User.where(username: "rolesticky").destroy_all
    admin = User.create!(username: "rolesticky", role: :admin)
    User.find_or_provision_from_proxy(username: "rolesticky", email: nil, name: nil)
    assert admin.reload.admin?
  end
end
