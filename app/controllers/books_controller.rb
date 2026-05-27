class BooksController < ApplicationController
  before_action :set_book

  def show
  end

  def cover
    if @book.cover_available?
      send_file @book.cover_full_path,
                type: "image/jpeg",
                disposition: "inline"
    else
      head :not_found
    end
  end

  private

  def set_book
    @book = Book.find(params[:id])
  end
end
