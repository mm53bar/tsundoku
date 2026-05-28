# Computes a "what would change" view of a re-import: which parsed
# entries are new (not in the list today), which existing entries would
# be removed (not in the new paste), and which match by case-insensitive
# (title, author) and would stay.
#
# Entries are compared on a composite key of normalized title + author.
# Order is intentionally NOT part of the key — re-ordering is treated as
# unchanged. Apply step always re-positions everything by the new paste's
# order anyway, so the diff is purely informational.
class ListReimportDiff
  def initialize(list, parsed_entries)
    @list = list
    @parsed_entries = Array(parsed_entries)
  end

  # ListEntry instances that would be removed (in the list now, not in the paste).
  def removed
    new_keys_set = new_keys.to_set
    existing_entries.reject { |e| new_keys_set.include?(key(e.title, e.author_name)) }
  end

  # Parsed entry hashes that would be added (in the paste, not in the list).
  def added
    existing_keys_set = existing_keys.to_set
    @parsed_entries.reject { |e| existing_keys_set.include?(key(e[:title], e[:author])) }
  end

  # Count of entries present in both (might be re-positioned but not added or removed).
  def unchanged_count
    (existing_keys & new_keys).count
  end

  def total_existing
    existing_entries.length
  end

  def total_new
    @parsed_entries.length
  end

  def empty?
    added.empty? && removed.empty?
  end

  private

  def existing_entries
    @existing_entries ||= @list.list_entries.to_a
  end

  def existing_keys
    @existing_keys ||= existing_entries.map { |e| key(e.title, e.author_name) }
  end

  def new_keys
    @new_keys ||= @parsed_entries.map { |e| key(e[:title], e[:author]) }
  end

  def key(title, author)
    [ title.to_s.downcase.strip, author.to_s.downcase.strip ].join("|")
  end
end
