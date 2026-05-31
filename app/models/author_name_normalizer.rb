# Cleans up raw author-name strings coming out of OPF metadata and
# Calibre imports. OPF in the wild is dirty: multiple authors get
# joined with `|` or `;`, surname-first names get joined with `|` too,
# trailing punctuation lingers, and Calibre-style "Last, First" sneaks
# through. This PORO is the single place that turns a raw string into
# an array of clean "First Last" display names.
#
# Used at two call sites:
#   - BookIngester#attach_authors at ingest time (prevents new dirty
#     rows from landing).
#   - The on-demand authors-cleanup job (re-runs against existing rows
#     to catch the backlog before AuthorNameNormalizer existed).
class AuthorNameNormalizer
  # Tokens we never want trailing on a name. Calibre sometimes leaves
  # them when concatenating multi-author fields ("Andy Weir;",
  # "Owen| Peter;").
  TRAILING_JUNK = /[\s;,]+\z/.freeze

  # Comma-pair form: a single "Last, First" entry with no separators
  # we'd otherwise split on. Detected after the split-on-pipe pass.
  COMMA_LAST_FIRST = /\A([^,]+),\s+([^,]+)\z/.freeze

  # Empty / placeholder names that should be filtered out entirely.
  # OPF files sometimes carry "Unknown Author" or a language-specific
  # equivalent; better to drop than to keep a fake author row.
  PLACEHOLDER_NAMES = %w[
    unknown
    desconocido
    n/a
  ].freeze

  def self.normalize(raw)
    new(raw).normalize
  end

  def initialize(raw)
    @raw = raw.to_s
  end

  # Returns an array of cleaned "First Last" display names. The array
  # has at least zero entries (empty input or all-placeholder → []).
  def normalize
    return [] if @raw.strip.empty?

    parts = split_on_separators(@raw).map { |p| strip_junk(p) }.reject(&:empty?)
    return [] if parts.empty?

    interpreted = interpret_parts(parts)
    interpreted.map { |n| reverse_comma_pair(n) }
               .reject { |n| placeholder?(n) }
               .uniq
  end

  private

  # Split on `|` or `;` and trim each token's whitespace.
  def split_on_separators(raw)
    raw.split(/[|;]/).map(&:strip)
  end

  # Drop trailing junk (`;`, `,`, whitespace) that hangs off a name.
  # Internal punctuation (J.D., O'Brien) is preserved.
  def strip_junk(part)
    part.sub(TRAILING_JUNK, "").strip
  end

  # The hard part. Once split on `|`, we have N tokens. We need to
  # decide whether they're:
  #   (a) N independent authors:
  #         "Eric Freeman | Elisabeth Robson | Bert Bates" → 3 authors
  #   (b) one "Last| First" pair to flip:
  #         "Bock | Laszlo" → ["Laszlo Bock"]
  #   (c) M paired "Last| First" entries (even count, every token
  #       single-word):
  #         "Ignatieff | Michael | Hardy | Henry | Berlin | Isaiah"
  #         → ["Michael Ignatieff", "Henry Hardy", "Isaiah Berlin"]
  #
  # Heuristic: if *every* token is a single word AND there's an even
  # number of tokens, it's case (b) or (c) — pair them up and flip.
  # Otherwise treat as case (a). This is good enough for the dirty
  # data observed in Sheila's library; the cases that fool it are rare
  # enough that the cleanup-button manual override is fine.
  def interpret_parts(parts)
    return parts if parts.size == 1
    return parts if parts.size.odd?
    return parts unless parts.all? { |p| single_word?(p) }

    parts.each_slice(2).map { |last, first| "#{first} #{last}" }
  end

  def single_word?(name)
    !name.include?(" ")
  end

  # "Last, First" → "First Last" when no other separators were present.
  # Skip if the name already contains a comma we don't recognize (e.g.,
  # "Smith, John, MD" — a degree suffix we don't want to flip).
  def reverse_comma_pair(name)
    if (m = name.match(COMMA_LAST_FIRST))
      "#{m[2].strip} #{m[1].strip}"
    else
      name
    end
  end

  def placeholder?(name)
    cleaned = name.downcase.strip
    PLACEHOLDER_NAMES.include?(cleaned) || cleaned == "unknown author"
  end
end
