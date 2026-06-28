# 20260528 — Shelves alongside readings, with explicit sync opt-in

## Context

`Reading` (see ADR 20260528-reading-state-model.md) handles per-user
*status* — "I want to read this," "I finished this." It doesn't cover
*collections* — "These are my all-time favourites," "This is my
sci-fi-for-the-cabin pile."

Calibre and Calibre-web overload a single "shelf" concept to mean both —
a shelf can be a status bucket *and* a curated collection, and the user
has to mentally untangle which is which. That gets worse when shelves
also drive sync: did this book sync because it's on my "Currently
Reading" shelf or my "Favourites" shelf?

We also need a way to opt collections into Kobo sync that's independent
of reading status. A book Alex marked `read` years ago might still belong
on his "All-time greats" shelf and should stay on his Kobo.

## Decision

Two parallel structures:

- `Reading` — structured per-user state, one row per `(user, book)`,
  exactly one of five statuses. Drives **default** sync inclusion via
  `Reading::SYNCABLE_STATUSES`.
- `Shelf` — free-form per-user collection. Has a `sync_to_kobo` boolean
  that's **opt-in per shelf** (default false). A book on a shelf where
  `sync_to_kobo = true` is in the syncable set regardless of its reading
  status.

Shelves and readings are independent. Adding to a shelf does not change
reading status; setting a status does not put a book on any shelf. Users
can use one, the other, or both.

The conflict case — a book is `read` (status would not sync) AND on a
shelf where `sync_to_kobo = true` — is resolved by ADR
20260528-shelf-wins-sync-conflict.md.

## Consequences

- Mental model is clearer than Calibre's: status answers "where am I with
  this book?", shelves answer "what collection does this belong to?".
- The syncable set is the union of two independent queries, not a single
  query. Slightly more code, much less ambiguity.
- Opt-in (rather than opt-out) `sync_to_kobo` means shelves used purely
  for organisation don't accidentally push 200 books to a 4GB device.
  Worth the extra click when creating a sync-intended shelf.
- Two structures with overlapping purpose can confuse new users. The UI
  has to do work to make it obvious when to use which — currently
  addressed by chip rows on the book page that show both.
