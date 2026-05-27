class BooksController < ApplicationController
  before_action :set_book

  def show
  end

  def cover
    path = safe_cover_path
    return head :not_found unless path

    send_file path, type: "image/jpeg", disposition: "inline"
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end

  # Resolve the cover path under the library root and refuse anything that
  # tries to escape it. Calibre's metadata.db is trusted today, but a hostile
  # cover_path value (".." segments, absolute paths) shouldn't be able to
  # exfiltrate files outside the library bind-mount.
  def safe_cover_path
    return nil if @book.cover_path.blank?

    base = Pathname.new(Rails.configuration.x.library_path).expand_path
    candidate = base.join(@book.cover_path).expand_path

    return nil unless candidate.to_s.start_with?(base.to_s + File::SEPARATOR)
    return nil unless candidate.file?

    candidate.to_s
  end
end
