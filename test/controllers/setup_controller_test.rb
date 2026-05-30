require "test_helper"
require "fileutils"
require "tmpdir"

class SetupControllerTest < ActionDispatch::IntegrationTest
  def headers_for(user)
    { "HTTP_REMOTE_USER" => user.username }
  end

  setup do
    @user = users(:reader)
    @tmp_library = Dir.mktmpdir("setup_test_library")
    @original_library_path = Rails.configuration.x.library_path
    Rails.configuration.x.library_path = @tmp_library
    Book.destroy_all
  end

  teardown do
    Rails.configuration.x.library_path = @original_library_path
    FileUtils.remove_entry(@tmp_library) if @tmp_library && File.directory?(@tmp_library)
  end

  test "renders for any signed-in user (no admin gate)" do
    get setup_path, headers: headers_for(@user)
    assert_response :success
  end

  test "shows the import button when library is empty and metadata.db is available" do
    # CalibreImporter.available? just checks for metadata.db; create one.
    File.write(File.join(@tmp_library, "metadata.db"), "")
    get setup_path, headers: headers_for(@user)
    assert response.body.include?("Import from Calibre")
  end

  test "shows guidance to drop a library when library is empty and no metadata.db" do
    get setup_path, headers: headers_for(@user)
    assert response.body.include?("Drop a Calibre library")
    refute response.body.include?(">Import from Calibre<")  # no submit button
  end

  test "shows the all-set state when library has books and no CWA mount" do
    Book.create!(title: "Existing", path: "x", file_name: "x", file_format: "EPUB", imported_at: Time.current)
    get setup_path, headers: headers_for(@user)
    assert response.body.include?("all set")
    refute response.body.include?(">Import from Calibre<")
  end
end
