# 20260528 — Per-user `Reading` model with a three-state status enum

> **Partially superseded by `20260530-reading-sync-intent-split.md`.**
> The decision to use `SYNCABLE_STATUSES` to drive Kobo sync inclusion
> no longer holds — sync intent now lives in a dedicated
> `sync_to_device` boolean. The rest of this ADR (separate model per
> user, three-state status, lazy timestamps, Kobo wire mapping) still
> applies.

## Context

Tsundoku is multi-user. Each user needs to track which books they want to
read, are reading, and have finished — independently of every other
user. Two model shapes were plausible:

1. A `status` column on `Book` itself. Simple, but global: there's only
   one status per book, which makes no sense in a household where Alex
   has finished a book and his son is just starting it.
2. A separate join model between `User` and `Book` carrying the status.

For the status vocabulary, the candidates were:

- **Goodreads/Hardcover's five states** — `want_to_read`,
  `currently_reading`, `paused`, `read`, `did_not_finish`. Familiar to
  readers, expressive.
- **Kobo's three states** — `ReadyToRead` / `Reading` / `Finished`.
  Fewer moving parts. Maps trivially to the device.

We initially shipped five. After using the app for a while, the two
extra states (`paused`, `did_not_finish`) turned out to be theoretical:
Alex never reached for them, and the Kobo's own behaviour ("switch to
another book mid-read, the first stays `Reading`") already covers the
"I'm not actively on this right now" case without a new state. The
extra vocabulary was carrying cost (every Kobo↔Tsundoku mapping needed
a collapse rule, the UI had five buttons instead of three) for no
benefit anyone reached for.

## Decision

Separate model (`Reading`), one record per `(user, book)` pair, with a
three-state enum: `want_to_read`, `currently_reading`, `read`. UI labels
are "Want to Read" / "Currently Reading" / "Read."

Mapping to Kobo's three states is 1:1, no logic.

The "not on my list" case is the absence of a `Reading` row, not a null
status — destroying the row when the user picks "Not on my list" keeps
absence-vs-presence semantics clean.

Timestamps (`started_at`, `finished_at`) are **lazy** — stamped only on
the transition into a state that warrants them, and never overwritten
by later edits. Reading status has a uniqueness constraint:
`unique(user_id, book_id)`.

A `SYNCABLE_STATUSES` constant on the model captures the
`want_to_read | currently_reading` set that drives default Kobo sync
inclusion. See ADR 20260528-shelf-wins-sync-conflict.md for how this
interacts with shelves.

## Consequences

- Multi-user is correct from day one — no migration to add per-user
  state later.
- Kobo↔Tsundoku state mapping is trivial. No lossy collapse, no
  asymmetric rules.
- We lost the ability to express "paused with intent to resume" and
  "actively given up on this" as first-class states. Acceptable: the
  device's natural behaviour covers the first case, and the second can
  be expressed by removing the book from the syncable set (mark `read`
  or remove from shelf) without needing dedicated vocabulary.
- The earlier 5-state shipped briefly. If the dev DB has rows with
  `paused` or `did_not_finish`, the follow-up migration needs to
  collapse them (`paused → currently_reading`, `did_not_finish → read`)
  before dropping the enum values.
- Lazy timestamps mean `finished_at` can be wrong if a user toggles a
  book to `read` years after actually finishing it. Acceptable — better
  than overwriting a deliberately-set value on every save.
