# 20260530 — Enrich books with no ISBN via title+author search

## Context

`BookEnricher` originally gated all Hardcover lookups on
`@book.isbn.present?` (and `IngestFileJob` made the same check before
even enqueueing the enrichment task). That worked for Calibre imports
and modern Hardcover-aware ingests, where ISBNs are usually present in
the OPF.

It broke for public-domain classics ingested via Shelfmark — Standard
Ebooks editions, ePubLibre's catalog, and similar sources frequently
ship without an `<dc:identifier>` carrying an ISBN. Hardcover often has
the book anyway (Catcher in the Rye, for example, lives at
hardcover.app/books/the-catcher-in-the-rye), so the gate was leaving
real enrichment data on the table.

The fix has to keep the user in control — auto-applying a Hardcover
match without confirmation risks pulling in the wrong edition
(translation, abridged, alternate cover). Tsundoku already has the
review-then-apply flow on the edit form; this just needs another way
to *propose*.

## Decision

Add a title+author search path to `HardcoverClient` and wire
`BookEnricher` to fall through to it when no ISBN is available. The
proposal goes through the same review-and-accept flow as ISBN-matched
enrichment — nothing applies until the user clicks through the
metadata edit form.

### `HardcoverClient`

Two new methods plus a shared GraphQL fragment:

- `BOOK_PAYLOAD_GQL` — the book-record selection set that
  `BookEnricher` consumes. Already nested under `edition.book` in
  `find_edition_by_isbn`; extracted here so the two paths produce
  identical downstream shapes.
- `find_book_by_search(title:, author:)` — runs `search_books` (the
  existing Typesense-backed search), filters hits by bidirectional
  title containment, takes the first surviving hit, and fetches the
  full book payload by id. Wraps the result in the same
  edition-shaped hash that `find_edition_by_isbn` returns; the
  `isbn_13`/`isbn_10`/`asin` fields are nil (by definition of this
  path) and the `id` and `cached_image` come from the book's
  `default_cover_edition`.
- `find_book_by_id(book_id)` — straight fetch by Hardcover book id.

### `BookEnricher`

`build_proposal` keeps its early-return on
`HardcoverClient.available?`, then branches:

```ruby
edition = if @book.isbn.present?
  client.find_edition_by_isbn(@book.isbn)
else
  client.find_book_by_search(title: @book.title, author: clean_author_name(...))
end
```

The downstream proposal-building logic is unchanged. ISBN/ASIN
identifiers won't be proposed on the search path (we don't have them),
but `hardcover_book` and `hardcover_edition` still are, and so are
description, headline, rating, subtitle, pubdate, cover, and
author/series slug stamping.

### `IngestFileJob`

The `if result.book.isbn.present?` gate around the enrichment-task
enqueue is removed. Every successful ingest now enqueues an
enrichment task. If nothing matches, the task auto-clears via
`EnrichBookJob#proposal_actionable?` and the user never sees it.

## Consequences

- ISBN-less ingests (Standard Ebooks, ePubLibre, etc.) now get the
  same enrichment proposal flow as everything else.
- Wrong-edition risk is bounded by the existing review step. A
  mismatch shows up on the edit form, the user rejects per-field or
  declines the whole proposal.
- The bidirectional title-containment filter in
  `HardcoverClient#first_title_matching_hit` mirrors the one
  `BookEnricher#matching_search_hits` already uses for cover
  harvesting. The duplication is intentional — they're applied to
  different result sets (the full search vs. the cover-only search)
  and at different layers; refactoring to a shared helper would mean
  threading filtered hits through both call sites without a
  meaningful win.
- The search path makes one extra GraphQL request per ingest (search
  + fetch). Hardcover allows 60 req/min and ingests are infrequent;
  no rate-limit concern.
- ISBN-less books still won't get `isbn13`/`isbn10` identifiers from
  Hardcover, since neither the search nor the by-id fetch returns
  that data. If a future change wants those, the path would be to
  extend `find_book_by_id` to also return a representative edition's
  ISBN fields (or pick one from the `editions` list returned today).
