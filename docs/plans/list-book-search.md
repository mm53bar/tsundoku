# Plan: book search for lists

Goal: keep lists as simple to build as today (type or paste title/author), but
resolve each entry to a real book automatically so lists show covers, fill in
missing authors, and match the library more reliably. The user never types an
ISBN or ID.

## Phase 1 — background resolution of pasted entries

- `list_entries` gains: `hardcover_book_id`, `resolved_title`, `resolved_author`,
  `release_year`, `cover_url`, `resolution_status` (`nil` = pending,
  `resolved`, `ambiguous`, `unresolved`), `resolution_candidates` (JSON, top 3).
- `title` / `author_name` stay exactly as typed. `ListReimportDiff` keys on
  them, so resolution must never rewrite them. Views show the resolved values
  when present.
- `ResolveListEntriesJob(list)` runs after create, re-import, and single add.
  It searches Hardcover (`title author`) for each pending entry, throttled
  under Hardcover's 60 req/min.
- Clear-winner rule (borrowed from bindery's `canonicalMatchIsDecisive`):
  candidates are hits whose normalized title matches (exact, subtitle-stripped,
  or an alternative title) and, when an author was typed, whose author
  matches. Compilations are dropped. Accept one candidate, or the most popular
  when it has at least 5x the runner-up's `users_count`. Otherwise
  `ambiguous` with the top 3 stored for a "Which one?" picker. No hits:
  `unresolved`.
- Re-import carries resolution forward for entries whose (title, author) key
  is unchanged, so picks survive.
- `BookMatcher` matches by `hardcover_book` identifier first, then typed
  title/author, then resolved title/author. A newly resolved entry re-runs
  matching.

## Phase 2 — search box for adding one book

- The list page's title/author fields become one search input (Stimulus,
  shared with the navbar as `search_dropdown_controller.js`).
- `GET /lists/:id/entries/search?q=` renders library hits first, then Hardcover
  hits (cached briefly), each a one-click add. Last row: "Add as typed",
  parsed with `ListEntryParser` so "Title by Author" still works.
- A picked Hardcover hit is saved already resolved; a picked library book is
  saved matched.

## Out of scope for now

- ISBNs on entries (Hardcover hits carry every edition's ISBN; no good pick).
- Drag-to-reorder or insert-at-position for ranked lists; paste order is the
  rank.
