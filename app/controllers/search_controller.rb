class SearchController < ApplicationController
  RESULT_LIMIT = 10
  MIN_QUERY_LEN = 2

  def show
    @query = params[:q].to_s.strip
    @books = if @query.length < MIN_QUERY_LEN
      Book.none
    else
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      Book.left_joins(:authors)
          .where("LOWER(books.title) LIKE :q OR LOWER(authors.name) LIKE :q", q: pattern)
          .includes(:authors)
          .distinct
          .by_title
          .limit(RESULT_LIMIT)
    end
    render layout: false
  end
end
