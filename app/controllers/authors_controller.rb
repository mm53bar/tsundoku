class AuthorsController < ApplicationController
  def index
    @authors = Author.left_joins(:books)
                     .group("authors.id")
                     .select("authors.*, COUNT(books.id) AS books_count")
                     .by_name
  end

  def show
    @author = Author.find(params[:id])
    @books  = @author.books.by_title.includes(:authors, :series, :lists)
    @user_shelves, @shelf_member_ids_by_book, @starred_shelf_id = preload_shelf_membership_for(@books)
  end

  # Loaded lazily by the Turbo Frame on the show page. Hits Hardcover for
  # books linked to this author and filters out any we already have in
  # the local library (matched by stored hardcover_book identifier).
  # Result cached in Solid Cache for 24 hours.
  def more_books
    @author = Author.find(params[:id])

    @books = []
    if @author.hardcover_slug.present?
      hc_books = Rails.cache.fetch("hardcover:author_books:#{@author.hardcover_slug}", expires_in: 24.hours) do
        HardcoverClient.new.books_by_author_slug(@author.hardcover_slug)
      end

      local_ids = BookIdentifier.where(kind: "hardcover_book").pluck(:value).to_set
      @books = hc_books.reject { |b| local_ids.include?(b["id"].to_s) }
    end
  end
end
