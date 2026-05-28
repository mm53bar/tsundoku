class SeriesController < ApplicationController
  def index
    @series = Series.left_joins(:books)
                    .group("series.id")
                    .select("series.*, COUNT(books.id) AS books_count")
                    .by_name
  end

  def show
    @series = Series.find(params[:id])
    @books  = @series.books.order(Arel.sql("series_index ASC NULLS LAST"), :title).includes(:authors, :series)
  end
end
