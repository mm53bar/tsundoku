require "test_helper"

class ToolsControllerTest < ActionDispatch::IntegrationTest
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

  setup do
    @user = users(:reader)
  end

  test "renders for any signed-in user (no admin gate)" do
    get tools_path, headers: headers_for(@user)
    assert_response :success
  end

  test "links to the ingest page and shows the pending file count" do
    get tools_path, headers: headers_for(@user)
    assert response.body.include?("Ingest")
    assert response.body.include?("waiting")
  end

  test "shows the kepub rake command documentation" do
    get tools_path, headers: headers_for(@user)
    assert response.body.include?("kepub:backfill")
    assert response.body.include?("kepub:reconvert_all")
  end
end
