class LibraryController < ApplicationController
  def index
    root = Pathname.new(Rails.configuration.x.library_path)
    @library_path = root.to_s
    @files = if root.directory?
      Dir.glob(root.join("**", "*.epub")).map { |f| Pathname.new(f).relative_path_from(root).to_s }.sort
    else
      []
    end
  end
end
