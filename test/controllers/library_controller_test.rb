require "test_helper"

class LibraryControllerTest < ActionDispatch::IntegrationTest
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

  setup do
    @user = users(:admin)
    # Alphabetical order is the opposite of added order, so the two sorts
    # produce visibly different card ordering.
    @older = Book.create!(title: "Aardvark", path: "a", file_name: "a",
                          file_format: "EPUB", imported_at: Time.current, added_at: 2.days.ago)
    @newer = Book.create!(title: "Zucchini", path: "z", file_name: "z",
                          file_format: "EPUB", imported_at: Time.current, added_at: 1.day.ago)
  end

  teardown { Book.destroy_all }

  test "defaults the library sort to recently added (newest first)" do
    get root_path, headers: headers_for(@user)
    assert_response :success
    assert_select "option[selected][value=?]", "recently_added"
    assert_operator response.body.index("Zucchini"), :<, response.body.index("Aardvark"),
                    "newest book should render before the older one by default"
  end

  test "honors an explicit title sort" do
    get root_path(sort: "title"), headers: headers_for(@user)
    assert_response :success
    assert_select "option[selected][value=?]", "title"
    assert_operator response.body.index("Aardvark"), :<, response.body.index("Zucchini"),
                    "title sort should order alphabetically"
  end
end
