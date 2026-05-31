class CleanupAuthorsJob < ApplicationJob
  queue_as :default

  # Walk every Author row through AuthorNameNormalizer (the same PORO
  # BookIngester now uses at ingest) and reshape the dirty ones.
  #
  # The normalizer returns 0, 1, or many cleaned names per input. We
  # act on each case:
  #
  #   - 0 names (the row was a placeholder like "Unknown" / "Desconocido")
  #     → drop the author; book_authors cascade away via dependent: :destroy.
  #   - 1 name, unchanged → no-op.
  #   - 1 name, different → rename if no other author normalizes to the
  #     same key, MERGE into that other author if one already exists.
  #   - many names → split: the original author's books get linked to
  #     each of the cleaned authors (find_or_create_by); the original
  #     row is destroyed.
  #
  # Merging happens via Author.normalize_name so "James S.A. Corey" and
  # "James S. A. Corey" collapse to one row — same key BookEnricher and
  # BookMatcher already use for cross-source matching.
  def perform(task_id)
    task = Task.find(task_id)
    task.mark_running!

    stats = { renamed: 0, merged: 0, split: 0, dropped: 0, unchanged: 0 }
    authors = Author.order(:id).to_a
    total   = authors.size

    authors.each_with_index do |author, i|
      handle(author, stats)
      task.update_progress!(i + 1, total) if ((i + 1) % 25).zero? || (i + 1) == total
    end

    task.mark_succeeded!(result_data: stats.stringify_keys)
    task.mark_reviewed! # nothing to review; auto-clear from the tray
  end

  private

  def handle(author, stats)
    cleaned = AuthorNameNormalizer.normalize(author.name)

    if cleaned.empty?
      author.destroy
      stats[:dropped] += 1
    elsif cleaned.size == 1
      apply_single_name(author, cleaned.first, stats)
    else
      apply_split(author, cleaned, stats)
    end
  end

  # Rename in place if no other author normalizes to the cleaned name;
  # otherwise merge: move this author's book_authors into the other and
  # destroy this row.
  def apply_single_name(author, cleaned_name, stats)
    if author.name == cleaned_name
      stats[:unchanged] += 1
      return
    end

    target = find_existing(cleaned_name, exclude_id: author.id)
    if target
      merge_into(author, target)
      stats[:merged] += 1
    else
      author.update!(name: cleaned_name)
      stats[:renamed] += 1
    end
  end

  # Each cleaned name becomes (or matches) its own Author. The original
  # author's book_authors are rewritten to point at the new set: the
  # first new author replaces the original position, the rest are
  # appended at the end of each book.
  def apply_split(author, cleaned_names, stats)
    Author.transaction do
      targets = cleaned_names.map { |name| find_existing(name) || Author.create!(name: name) }
      targets.reject! { |t| t.id == author.id } # don't link to self twice

      author.book_authors.includes(:book).each do |link|
        book = link.book
        existing_ids = book.book_authors.where.not(id: link.id).pluck(:author_id).to_set
        first_target, *rest = targets

        if first_target && !existing_ids.include?(first_target.id)
          link.update!(author: first_target)
          existing_ids << first_target.id
        else
          link.destroy
        end

        next_position = (book.book_authors.maximum(:position) || -1) + 1
        rest.each do |t|
          next if existing_ids.include?(t.id)
          book.book_authors.create!(author: t, position: next_position)
          existing_ids << t.id
          next_position += 1
        end
      end

      author.destroy if author.book_authors.reload.empty?
    end

    stats[:split] += 1
  end

  # Move every book_author from `source` to `target` (skipping duplicates
  # where the book is already linked to target), then destroy source.
  def merge_into(source, target)
    Author.transaction do
      source.book_authors.each do |link|
        already = target.book_authors.exists?(book_id: link.book_id)
        if already
          link.destroy
        else
          link.update!(author: target)
        end
      end
      source.destroy if source.book_authors.reload.empty?
    end
  end

  def find_existing(name, exclude_id: nil)
    key        = Author.normalize_name(name)
    candidates = exclude_id ? Author.where.not(id: exclude_id) : Author.all
    candidates.find { |a| Author.normalize_name(a.name) == key }
  end
end
