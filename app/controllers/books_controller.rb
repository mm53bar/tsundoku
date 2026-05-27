class BooksController < ApplicationController
  before_action :set_book
  before_action :require_admin!, only: :enrich

  def show
  end

  def cover
    path = safe_cover_path
    return head :not_found unless path

    send_file path, type: "image/jpeg", disposition: "inline"
  end

  def enrich
    if Task.active.where(kind: "metadata_enrichment", subject: @book).exists?
      redirect_to @book, alert: "An enrichment is already running for this book."
      return
    end

    task = Task.create!(kind: "metadata_enrichment", subject: @book, status: :queued)
    EnrichBookJob.perform_later(task.id)
    redirect_to @book, notice: "Enrichment started — progress will appear in the banner above."
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end

  def require_admin!
    return if current_user&.admin?
    redirect_to @book, alert: "Admins only."
  end

  # Resolve a cover path and refuse anything that tries to escape its
  # expected root directory. Enriched covers live under Rails.root/storage,
  # Calibre covers live under the library bind-mount.
  def safe_cover_path
    if @book.enriched_cover_path.present?
      enriched = safe_path_under(Rails.root.join("storage"), @book.enriched_cover_path)
      return enriched if enriched
    end

    return nil if @book.cover_path.blank?
    safe_path_under(Rails.configuration.x.library_path, @book.cover_path)
  end

  def safe_path_under(root, relative)
    base = Pathname.new(root).expand_path
    candidate = base.join(relative).expand_path
    return nil unless candidate.to_s.start_with?(base.to_s + File::SEPARATOR)
    return nil unless candidate.file?
    candidate.to_s
  end
end
