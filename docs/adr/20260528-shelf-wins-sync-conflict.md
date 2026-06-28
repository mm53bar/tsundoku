# 20260528 — Shelves win when reading status disagrees about sync

## Context

The syncable set (which books go to the Kobo) is driven by two
independent signals:

- A `Reading` record with status in `SYNCABLE_STATUSES`
  (`want_to_read | currently_reading | paused`).
- Membership in a shelf where `sync_to_kobo = true`.

These can disagree. The interesting case is:

> A book is marked `read` (status says don't sync) AND is on a shelf with
> `sync_to_kobo = true` (shelf says do sync).

Example: Alex finished *Foundation* years ago. He maintains an "All-time
greats" shelf with `sync_to_kobo = true` so he can pick something to
re-read on the Kobo. Marking the book `read` should not silently kick it
off the device — but a naive "status wins" rule would.

The opposite case — a book on a non-syncing shelf but with
`currently_reading` status — is uncontroversial: it syncs (status is the
default mechanism, and the shelf is just an organisational tag).

## Decision

**Shelves win.** A book is in the syncable set if **either**:

- Its `Reading.status` is in `SYNCABLE_STATUSES`, **or**
- It's on at least one shelf where `sync_to_kobo = true`.

Setting `sync_to_kobo = true` on a shelf is an explicit user opt-in to
sync that collection. That intent should not be overridden by a status
that happens to imply "don't sync by default."

The implementation is a `UNION` (or `.uniq` across two Ruby arrays of
book IDs) rather than a filter chain — neither signal can suppress the
other.

## Consequences

- The "All-time greats stays on my Kobo" case works without thought. This
  is the primary user-facing reason for the rule.
- Removing a book from the device requires either changing the shelf
  (removing the book, or unticking `sync_to_kobo`) AND ensuring no
  syncable reading status — i.e. the user has to be deliberate about
  removal. Acceptable; removal is rarer than retention.
- There is no "explicit no-sync" override at the book level. If someone
  ever needs that (e.g. a book is on a syncing shelf but the user
  specifically wants it kept off the device), they have to take it off
  the shelf or untoggle the shelf's sync. We have no use case yet that
  demands a per-book exclusion flag; adding one is reversible if it
  becomes necessary.
