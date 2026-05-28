class AuthorsController < ApplicationController
  def index
    @authors = Author.left_joins(:books)
                     .group("authors.id")
                     .select("authors.*, COUNT(books.id) AS books_count")
                     .by_name
  end

  def show
    @author = Author.find(params[:id])
    @books  = @author.books.by_title.includes(:authors, :series)
  end
end
