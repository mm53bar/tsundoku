class ListsController < ApplicationController
  before_action :require_admin!, only: [ :new, :create, :destroy ]
  before_action :set_list, only: [ :show, :destroy ]

  def index
    @lists = List.by_name
  end

  def show
    @entries = @list.list_entries.includes(book: [ :authors, :series ])
  end

  def new
    @list = List.new
  end

  def create
    @list = List.new(list_params)
    entries_text = params.dig(:list, :entries_text).to_s

    parsed = ListEntryParser.parse(entries_text)
    if parsed.empty?
      flash.now[:alert] = "No entries could be parsed from that input."
      render :new, status: :unprocessable_content
      return
    end

    List.transaction do
      @list.save!
      parsed.each_with_index do |entry, index|
        book = BookMatcher.match(entry)
        @list.list_entries.create!(
          position: index,
          title: entry[:title],
          author_name: entry[:author],
          book: book
        )
      end
    end

    matched = @list.matched_count
    total = @list.total_count
    redirect_to @list, notice: "Created '#{@list.name}' — #{matched} of #{total} matched to your library."
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Couldn't save: #{e.message}"
    render :new, status: :unprocessable_content
  end

  def destroy
    @list.destroy
    redirect_to lists_path, notice: "Deleted '#{@list.name}'."
  end

  private

  def set_list
    @list = List.find(params[:id])
  end

  def require_admin!
    return if current_user&.admin?
    redirect_to lists_path, alert: "Admins only."
  end

  def list_params
    params.require(:list).permit(:name, :description, :source_url)
  end
end
