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

  # Loaded lazily by the Turbo Frame on the show page. Hits Hardcover for
  # books in this series and filters out any we already have in the local
  # library (matched by stored hardcover_book identifier). Result cached
  # in Solid Cache for 24 hours.
  def more_books
    @series = Series.find(params[:id])

    @books = []
    if @series.hardcover_slug.present?
      hc_books = Rails.cache.fetch("hardcover:series_books:#{@series.hardcover_slug}", expires_in: 24.hours) do
        HardcoverClient.new.books_in_series_slug(@series.hardcover_slug)
      end

      local_ids = BookIdentifier.where(kind: "hardcover_book").pluck(:value).to_set
      @books = hc_books.reject { |b| local_ids.include?(b["id"].to_s) }
    end
  end
end
