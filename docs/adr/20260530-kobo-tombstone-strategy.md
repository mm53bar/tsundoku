# 20260530 — Kobo tombstones survive `Book#destroy`

## Context

When a `Book` is hard-deleted, Kobo sync needs to send a tombstone
(`ChangedEntitlement IsRemoved=true`) on every connected device's next
sync so the device archives the entitlement. Otherwise the book stays
on the device forever as an orphan.

The original `has_many :kobo_synced_books, dependent: :destroy` killed
the per-user sync records along with the book, leaving nothing for the
sync controller to emit against. Three approaches were on the table.

### 1. Soft-delete with `default_scope`

Add `deleted_at` to `books`, `default_scope where(deleted_at: nil)`.
Book stays in the DB but disappears from queries; sync sees it as
dropped from the syncable set and emits a tombstone via the existing
path.

We *tried* this (commit `de40259`) and reverted it (`db54a17`).
Reasons:

- `default_scope` is a known anti-pattern — implicit filter at every
  callsite, surprising joins, hard to reason about `unscoped`.
- Unique-index headaches: `books.calibre_id UNIQUE` rejects re-ingest
  of a previously soft-deleted book because the DB doesn't know about
  the soft-delete column.
- "Soft-deleted forever" rows accumulate. No clear point to GC them.

The review (`docs/reviews/rails-code-review.md` predecessor) flagged
this approach as "the most common way *and* the worst way" to do
soft-delete. We agreed.

### 2. Separate tombstones table

A new table `kobo_pending_tombstones(user_id, kobo_uuid, created_at)`.
On `Book#destroy`, populate one row per affected user. Sync emits from
this table.

Works, but introduces a new table just for this concern. The existing
`KoboSyncedShelf` model already had a `kobo_uuid` column for the
identical use case on shelves — there's a precedent on the existing
table.

### 3. Snapshot `kobo_uuid` on `kobo_synced_books`

Add a `kobo_uuid` column to `kobo_synced_books`, populated at create
time from the book's uuid. Change the association to `dependent:
:nullify`. On `Book#destroy`, `book_id` goes NULL but the row
survives, carrying its UUID snapshot.

## Decision

Option 3. Specifically:

- `kobo_synced_books` gains `kobo_uuid` (string, indexed). A
  `before_validation :snapshot_kobo_uuid, on: :create` populates it
  from `book.kobo_uuid` unless the caller passed an explicit value.
- `book_id` becomes nullable.
- `Book.has_many :kobo_synced_books, dependent: :nullify` (was
  `:destroy`).
- `Kobo::SyncController#sync`'s `removed_book_records` query catches
  both "dropped from syncable set" rows (existing case) and "book is
  gone" rows: `where("book_id IS NULL OR book_id NOT IN (?)", ...)`.
  SQL's `NOT IN` excludes nulls by default — without the explicit
  `IS NULL`, post-destroy rows would never appear.
- `removed_entitlement` reads `record.kobo_uuid` directly, no longer
  goes through `record.book`.
- `Book#before_destroy :broadcast_tombstone_to_kobo_users` iterates
  every `User` with a non-blank `kobo_handle` and creates a
  `kobo_synced_books` row with `book_id: nil, kobo_uuid:
  book.kobo_uuid` for any user that doesn't already have one. This is
  deliberate *over*-broadcast — see below.

## Consequences

- Books can be hard-deleted. The DB stays clean, no soft-delete
  bookkeeping.
- The pattern mirrors `KoboSyncedShelf` (where shelves have had this
  shape since Phase C). Symmetric, less to learn.
- `record.book` may be nil after destroy. Sync code that needs the
  UUID uses `record.kobo_uuid`. Code that needs book metadata (title,
  authors, etc.) for tombstones doesn't exist — tombstones carry only
  the UUID and the Removed flag.
- **Broadcast tombstones over-emit on purpose.** The alternative is
  emitting a tombstone only when the user had a prior
  `kobo_synced_books` row. That misses devices Tsundoku never tracked
  — most importantly, books CWA had pushed to a device before Tsundoku
  existed. Tombstones for entitlements the device doesn't have are
  silently ignored by the firmware; the cost of over-emit is one extra
  row per user per book destroy, which is nothing.
- The `KoboSyncedBook#kobo_uuid` snapshot also enables the CWA
  migration: `kobo:import_sync_state_from_cwa` creates per-user rows
  carrying Calibre's UUID, which is what CWA had emitted to the
  device. The device de-dupes against entitlements it already holds.

## Alternatives considered (not chosen)

- **Defer the tombstone to a job queue** — would let `Book#destroy`
  return faster. Not worth it for a homelab; the inline cost is
  ~milliseconds per Kobo-connected user, and there's a real benefit to
  the tombstone row being in the DB before the destroy transaction
  commits.
- **Periodic reconciliation job** ("on a schedule, compare each
  device's known entitlements with Tsundoku's view and emit
  tombstones for the diff"). Heavier and the device-side state isn't
  easily queryable. The broadcast approach is simpler.
