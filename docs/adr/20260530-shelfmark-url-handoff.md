# 20260530 — Shelfmark integration via URL handoff (not server-side API)

## Context

Sheila's primary friction point when adding books to the library is the
"books not in the library" step. The pattern repeats: she sees a title
on a list, on an author page, or in a series block; switches to
Shelfmark in another tab; types the title (and maybe author); confirms
the right edition; downloads. Shelfmark already drops the EPUB into the
shared INGEST path that `AutoIngestScanJob` watches, so once the file
lands the rest is automatic.

The repetition is the typing. Tsundoku already knows the title and (in
most contexts) the author of the book it just told her isn't in the
library. Pre-filling Shelfmark's search from those fields removes the
copy-paste and brings the workflow down to "click → confirm in
Shelfmark → wait two minutes."

Two ways to do it:

**Option A — URL handoff.** Tsundoku links to Shelfmark with the search
fields encoded as query params. Sheila lands on Shelfmark's pre-filled
results page, picks the right edition, downloads. One click before the
human-in-the-loop step.

**Option B — Server-side API integration.** Tsundoku calls Shelfmark's
API, picks a match programmatically, asks Shelfmark to download. No
human-in-the-loop step at all, but only if the auto-pick is reliable.

Shelfmark's search results frequently contain multiple editions for the
same work (regional, large-print, abridged, audiobook, mismatched
metadata). Picking the right one is the part Sheila already does well
and Tsundoku has no signal to do better. Going hands-off would mean
landing wrong editions in the library and cleaning them up after, which
is worse than the current pre-fill friction.

The Shelfmark instance lives on the same LAN
(`shelfmark.backson.boo`), and its frontend already bootstraps a search
from URL query params on mount — see `calibrain/shelfmark`,
`src/frontend/src/utils/parseUrlSearchParams.ts`. No Shelfmark-side
changes are required.

## Decision

Build Option A. Defer Option B until Option A usage shows whether
single-result matches are common enough to justify the auto-pick logic.

### Implementation

`ShelfmarkHelper` (one helper module, two methods):

- `shelfmark_search_url(title:, author: nil, isbn: nil)` builds a
  Shelfmark URL with the fields the frontend parses. Returns `nil` when
  the `SHELFMARK_URL` env var is unset or title is blank, so call sites
  can guard with a simple `if`.
- `shelfmark_link_to(title:, author:, isbn:, **link_options, &block)`
  wraps `link_to` with the URL builder and `target=_blank rel=noopener`.
  Returns `nil` when no URL can be built.

Configured via a single environment variable, `SHELFMARK_URL`. Unset →
no Shelfmark links anywhere. This is the entire feature flag — there is
no in-app toggle and no UI for it.

Query params used:

```
title         (required)
author        (when known)
isbn          (when known — list entries occasionally carry it)
content_type  (always "ebook" — Sheila's universe)
```

### Surfaces

- **`lists/show`** — every unmatched list entry (`entry.matched? ==
  false`) gets a "Find on Shelfmark" link inline with the "Not in
  library" badge. This is the primary surface: lists are how Sheila
  imports recommendations, and the unmatched entries are by definition
  the books she's about to need.
- **`hardcover/_book_thumb`** — the partial used by `authors#more_books`
  and `series#more_books` (the "More by author" / "More in series"
  Turbo Frame). Every thumb gets a Shelfmark link below the cover. The
  partial takes an optional `author_hint` local — the author show page
  passes `@author.name`; the series page leaves it nil because the
  series' books may span multiple authors and the per-book hash from
  Hardcover doesn't carry one cleanly today.

The book detail page intentionally doesn't get a link. The book is
already in the library — there's nothing to fetch.

## Consequences

- The ingest pipeline becomes "click in Tsundoku → confirm in
  Shelfmark → wait ~2 minutes." `AutoIngestScanJob` was already in
  place; this just trims the user's half.
- Sheila stays in the loop for edition selection, which is where she
  already adds the most value.
- The integration is one-way and stateless: Tsundoku doesn't track
  which links were clicked, doesn't know whether Shelfmark downloaded
  anything, doesn't poll for results. The book either shows up in the
  library (because `AutoIngestScanJob` picked up the file) or it
  doesn't — the same surface as a manual drop into the ingest folder.
- The link disappears cleanly when `SHELFMARK_URL` is unset, so the
  feature is opt-in per environment and the test/dev databases stay
  link-free.
- Option B remains available as a future addition. The decision to
  defer it is reversible — we'll have usage data from Option A
  (anecdotal: "how often does Sheila say 'it picked the wrong edition'
  vs 'the first result was right'?") before committing to the
  auto-pick logic.
