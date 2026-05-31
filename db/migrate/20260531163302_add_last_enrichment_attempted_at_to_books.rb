class AddLastEnrichmentAttemptedAtToBooks < ActiveRecord::Migration[8.1]
  # Tracks every BookEnricher#build_proposal attempt, regardless of
  # whether Hardcover returned a match. Separate from last_enriched_at
  # which only stamps on cover acceptance — that column tracks
  # "metadata was applied"; this one tracks "Hardcover was asked."
  #
  # Powers enrichment:backfill_slugs' "skip recently-attempted" filter
  # so re-runs don't burn API calls retrying books with no current
  # Hardcover match. After the cutoff window rolls over, candidates
  # come back into the pool automatically — auto-retry for books that
  # might get matches as Hardcover's catalog grows.
  def change
    add_column :books, :last_enrichment_attempted_at, :datetime
    add_index  :books, :last_enrichment_attempted_at
  end
end
