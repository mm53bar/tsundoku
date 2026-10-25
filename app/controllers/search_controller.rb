class SearchController < ApplicationController
  RESULT_LIMIT = 10
  MIN_QUERY_LEN = 2

  def show
    @query = params[:q].to_s.strip
    @books = if @query.length < MIN_QUERY_LEN
      Book.none
    else
      Book.matching(@query).limit(RESULT_LIMIT)
    end
    render layout: false
  end
end
