class ListsController < ApplicationController
  before_action :require_admin!, only: [ :new, :create, :edit, :update, :reimport, :destroy ]
  before_action :set_list, only: [ :show, :edit, :update, :reimport, :destroy ]

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

  def edit
  end

  def update
    if @list.update(list_params)
      redirect_to @list, notice: "List updated."
    else
      flash.now[:alert] = @list.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  # GET: shows the paste form. POST without confirm: parse + preview the
  # diff. POST with confirm=1: rebuild entries from the paste (delete all
  # existing + recreate from the new parse with fresh book-matching).
  def reimport
    if request.post?
      @entries_text = params.dig(:list, :entries_text).to_s
      @parsed = ListEntryParser.parse(@entries_text)

      if @parsed.empty?
        flash.now[:alert] = "No entries could be parsed from that input."
        render :reimport, status: :unprocessable_content
        return
      end

      @diff = ListReimportDiff.new(@list, @parsed)

      if params[:confirm] == "1"
        apply_reimport!(@parsed)
        redirect_to @list, notice: "Re-imported '#{@list.name}' — +#{@diff.added.size} added, -#{@diff.removed.size} removed, #{@diff.unchanged_count} unchanged."
        return
      end

      render :reimport_preview
    end
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

  # Rebuild this list's entries from a parsed array. Deletes existing
  # entries and recreates them in the order of the parsed input, running
  # BookMatcher on each to attempt local-library matching. Simpler than
  # preserving entries across the re-import — there's no per-entry data
  # worth saving today (no notes, no manual overrides). If we ever add
  # local edits per entry, switch to update-in-place.
  def apply_reimport!(parsed)
    List.transaction do
      @list.list_entries.destroy_all
      parsed.each_with_index do |entry, i|
        book = BookMatcher.match(title: entry[:title], author: entry[:author])
        @list.list_entries.create!(
          position: i,
          title: entry[:title],
          author_name: entry[:author],
          book: book
        )
      end
      @list.touch
    end
  end
end
