require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

  setup do
    @owner = users(:admin)
    @other = users(:reader)
    # Names avoid characters that get HTML-escaped so assertions can
    # match the rendered body directly.
    @private_list = @owner.lists.create!(name: "Owner private list", shared: false)
    @shared_list  = @owner.lists.create!(name: "Owner shared list",  shared: true)
  end

  teardown do
    List.destroy_all
  end

  # Visibility — `List.for(user)` scopes index/show.

  test "index shows the user's own lists" do
    get lists_path, headers: headers_for(@owner)
    assert_response :success
    assert response.body.include?("Owner private list")
    assert response.body.include?("Owner shared list")
  end

  test "index shows other users' shared lists but not private ones" do
    get lists_path, headers: headers_for(@other)
    assert_response :success
    assert response.body.include?("Owner shared list")
    refute response.body.include?("Owner private list")
  end

  test "show works for the owner on their own private list" do
    get list_path(@private_list), headers: headers_for(@owner)
    assert_response :success
  end

  test "show works for non-owner on a shared list" do
    get list_path(@shared_list), headers: headers_for(@other)
    assert_response :success
  end

  test "show 404s for a non-owner on a private list" do
    get list_path(@private_list), headers: headers_for(@other)
    assert_response :not_found
  end

  # Write authority — owner only, regardless of sharing.

  test "edit works for the owner" do
    get edit_list_path(@shared_list), headers: headers_for(@owner)
    assert_response :success
  end

  test "edit 404s for a non-owner even on a shared list" do
    get edit_list_path(@shared_list), headers: headers_for(@other)
    assert_response :not_found
  end

  test "update 404s for a non-owner even on a shared list" do
    patch list_path(@shared_list),
          params:  { list: { name: "Hacked" } },
          headers: headers_for(@other)
    assert_response :not_found
    assert_equal "Owner shared list", @shared_list.reload.name
  end

  test "destroy 404s for a non-owner even on a shared list" do
    delete list_path(@shared_list), headers: headers_for(@other)
    assert_response :not_found
    assert List.exists?(@shared_list.id)
  end

  # Creation — any signed-in user can create their own lists.

  test "any signed-in user can create a list, and it's theirs" do
    assert_difference -> { @other.lists.count }, 1 do
      post lists_path,
           params:  { list: { name: "Reader's list", entries_text: "Test Book by Test Author" } },
           headers: headers_for(@other)
    end
    assert_equal @other.id, List.order(:created_at).last.user_id
  end

  test "share flag round-trips through update" do
    @private_list.update!(shared: false)
    patch list_path(@private_list),
          params:  { list: { shared: "1" } },
          headers: headers_for(@owner)
    assert @private_list.reload.shared?
  end
end
