class ListEntriesController < ApplicationController
  SEARCH_LIMIT = 8
  HARDCOVER_FETCH = 20
  MIN_QUERY_LEN = 2

  before_action :set_owned_list

  def search
    @query = params[:q].to_s.strip
    if @query.length < MIN_QUERY_LEN
      @books = Book.none
      @hits = []
    else
      @books = Book.matching(@query).limit(SEARCH_LIMIT)
      @hits = hardcover_hits(@query, exclude: @books)
    end
    render layout: false
  end

  def create
    attrs = entry_attributes
    if attrs[:title].blank?
      redirect_to @list, alert: "Title is required."
      return
    end

    position = (@list.list_entries.maximum(:position) || -1) + 1
    entry = @list.list_entries.create!(attrs.merge(position: position))
    entry.rematch!
    ResolveListEntriesJob.perform_later(@list) unless entry.resolution_status

    flash_message = if entry.matched?
      "Added '#{entry.display_title}' — matched to your library."
    else
      "Added '#{entry.display_title}' — not in your library."
    end
    redirect_to @list, notice: flash_message
  end

  # Resolves an ambiguous entry to one of its stored candidates, or with no
  # candidate id, gives up on it.
  def choose
    entry = @list.list_entries.find(params[:id])
    hit = entry.candidates.find { |c| c.id == params[:hardcover_book_id].to_i }

    if hit
      entry.choose!(hit)
      redirect_to @list, notice: "Set '#{entry.title}' to #{hit.title}."
    else
      entry.update!(resolution_status: "unresolved", resolution_candidates: nil)
      redirect_to @list, notice: "Left '#{entry.title}' as typed."
    end
  end

  def destroy
    entry = @list.list_entries.find(params[:id])
    entry.destroy
    redirect_to @list, notice: "Removed '#{entry.title}'."
  end

  private

  # Entries are an owner-only concern. Scoping the lookup through
  # `current_user.lists` means non-owners 404 here rather than landing
  # on a "not allowed" redirect — matches the rest of the app.
  def set_owned_list
    @list = current_user.lists.find(params[:list_id])
  end

  # Three ways in, from the search dropdown or the plain form:
  #   book_id            — a library book was picked
  #   hardcover_book_id  — a Hardcover search hit was picked
  #   query / title      — free text, "Title by Author" allowed
  def entry_attributes
    p = params.fetch(:list_entry, {}).permit(
      :book_id, :hardcover_book_id, :title, :author_name, :release_year, :cover_url, :query
    )

    if p[:book_id].present?
      book = Book.find(p[:book_id])
      {
        title: book.title, author_name: book.author_names.presence, book: book,
        resolved_title: book.title, resolved_author: book.author_names.presence,
        hardcover_book_id: book.book_identifiers.find_by(kind: "hardcover_book")&.value,
        resolution_status: "resolved"
      }
    elsif p[:hardcover_book_id].present?
      {
        title: p[:title].to_s.strip, author_name: p[:author_name].presence,
        hardcover_book_id: p[:hardcover_book_id], release_year: p[:release_year].presence,
        cover_url: p[:cover_url].presence,
        resolved_title: p[:title].to_s.strip, resolved_author: p[:author_name].presence,
        resolution_status: "resolved"
      }
    elsif p[:query].present?
      parsed = ListEntryParser.parse(p[:query]).first || {}
      { title: parsed[:title].to_s, author_name: parsed[:author] }
    else
      { title: p[:title].to_s.strip, author_name: p[:author_name].to_s.strip.presence }
    end
  end

  def hardcover_hits(query, exclude:)
    return [] unless HardcoverClient.available?

    docs = Rails.cache.fetch([ "list-entry-search", query.downcase ], expires_in: 10.minutes, skip_nil: true) do
      HardcoverClient.new.search_books(query, per_page: HARDCOVER_FETCH).presence
    end
    owned_ids = BookIdentifier.where(kind: "hardcover_book", book_id: exclude.map(&:id)).pluck(:value).map(&:to_i)
    owned_titles = exclude.map { |book| ClearWinner.normalize_title(book.title) }
    Array(docs).map { |doc| HardcoverHit.from_document(doc) }
        .reject { |hit| hit.compilation? || owned_ids.include?(hit.id) || owned_titles.include?(ClearWinner.normalize_title(hit.title)) }
        .sort_by { |hit| -hit.users_count }
        .first(SEARCH_LIMIT)
  end
end
