# 20260531 — Unify sync intent on shelves; introduce the Starred default

**Supersedes the sync-intent half of `20260530-reading-sync-intent-split.md`.**
That ADR added `Reading.sync_to_device` as a separate dimension from
shelves. This one drops the column and routes everything through shelf
membership.

## Context

After `20260530-reading-sync-intent-split.md`, books reached the Kobo
through one of two paths:

- A `Reading` with `sync_to_device: true` — the per-book toggle on
  book#show.
- Membership in a `Shelf` with `sync_to_kobo: true` — the
  shelf-curation path.

Both worked; either-or for any given book. `User#on_kobo_books` was
their union.

The split was honest about the underlying intents but turned out to be
confusing in practice. Robin landed on the per-book toggle (it was
right there on the book page) for almost every book she wanted on her
Kobo — 41 of 43, in the production data at the time of this writing.
Only 3 books were on a syncing shelf, all because she'd explicitly
created one. When she synced and looked at her Kobo's collections,
they were nearly empty — the device only forms a collection from a
syncing shelf, and almost nothing was on one.

Two ways to express the same intent, with different downstream
consequences (one creates a collection on the device, one doesn't),
that the user can't easily tell apart from the UI: a forking path with
no visible signpost.

## Decision

**Books reach the Kobo only via shelf membership.** Drop
`Reading.sync_to_device`. `User#on_kobo_books` becomes "books on any
of my syncing shelves."

To preserve the per-book quick-action UX (Robin's reach for the
status-picker toggle was a real preference, not just an accident),
introduce a **default Starred shelf** per user:

- `Shelf.default_for_star: boolean` — at most one true per user
  (enforced by a partial unique index).
- Created lazily on first use via `User#starred_shelf`.
- `sync_to_kobo` is locked to `true` (model `before_save` snaps it
  back if a UI edit tries to flip it off).
- Can't be destroyed (model `before_destroy` aborts).
- Name and description are freely editable.

A star icon at the top-left of every book card toggles the book's
membership in the Starred shelf. The existing `+` button at the
top-right opens the shelf picker for any of the user's shelves
(including Starred). Two corners, two clearly-different operations.

**Tag-emission split from sync intent.** The Starred shelf is a
syncing shelf for purposes of `User#on_kobo_books` (its books reach
the device), but it does *not* emit as a Kobo Tag (collection on the
device). The Kobo's "My Books" view already covers "everything on the
device," so a Starred collection would be a redundant near-duplicate.
New `Shelf.emitting_as_tag` scope: `syncing.where(default_for_star:
false)`. The Kobo sync controller uses it for tag-related diff/emit
logic; `User#on_kobo_books` and the entitlement loop still use the
broader `syncing` scope.

## Consequences

### Model & data

- `readings.sync_to_device` column dropped. Backfill migration
  creates each user's Starred shelf and moves every
  `sync_to_device: true` reading into a `ShelfEntry` on it. Reading
  rows survive — only the sync intent moves; `progress_percent`,
  `finished_at`, etc. stay where they are.
- `Reading` is now purely about reading progress. Closes the
  conflation that ADR 20260530-reading-sync-intent-split.md split
  apart — but solves the conflation by removing the sync axis from
  the model entirely, not by sharing it with the shelf axis.
- The `before_save` callback that bridged the old `status` → sync
  mapping (introduced in 20260530-reading-sync-intent-split.md, then
  effectively neutralized by 20260530-reading-status-derived-from-progress.md)
  is gone for good.

### UI

- Star icon at top-left of every book card. Filled amber when the
  book is on the user's Starred shelf, outline when not. Single tap
  toggles via `POST /books/:id/toggle_star`.
- `+` button at top-right opens the shelf picker. Its amber state
  now means "on at least one non-Starred shelf" — the Starred state
  is signaled by the star, so counting it in the `+` would double-up
  the same signal.
- Picker panel and shelves#index lead with the Starred shelf, then
  alphabetical (`Shelf.by_name` orders `default_for_star: :desc`
  first).
- shelves#show locks the Starred shelf's sync-to-Kobo toggle (renders
  a disabled visual instead of an interactive checkbox; badge reads
  "Default" instead of "Active") and hides the Delete button.
- The book#show `_status_picker` partial drops its sync toggle.
  Progress controls (mark finished / unfinished, remove reading)
  remain.

### Kobo sync protocol

- `Kobo::BaseController#syncable_books` keeps delegating to
  `User#on_kobo_books`. Same set, narrower source.
- `Kobo::SyncController#sync`'s tags loop now reads
  `Shelf.emitting_as_tag`. The Starred shelf still drives book
  entitlements (NewEntitlement / ChangedEntitlement / tombstones)
  but doesn't fire a Tag, so the device gets the books without a
  "Starred" collection mirroring "My Books."

### Migration callers

- `lib/tasks/kobo.rake`'s CWA import action puts each migrated book
  on the user's Starred shelf instead of setting
  `sync_to_device: true`. Same migration intent — opt out
  explicitly, never opt back in.
- `lib/tasks/dev/curation.rb` rewrites the dev seed to use shelf
  memberships (including a populated Starred shelf) instead of
  `sync_to_device` on Reading.

### Tests

- `ReadingsControllerTest` drops the sync-toggle test cases.
- `Kobo::SyncControllerTest` gains a `make_syncable` helper that
  drops a book onto a regular (non-Starred) syncing shelf — the test
  fixture for "this book should reach the Kobo."
- `UserTest` gains coverage for `User#starred_shelf` (lazy create,
  reused, sync_to_kobo locked, can't be destroyed).

## Rejected alternatives

**Keep both paths, surface them better in the UI.** Considered. The
two paths really do have different consequences (Tag-on-device or
not) and you can't paper over that with copy. The straightforward
answer was to collapse them and surface the consequence as a per-
shelf decision instead of a per-book one.

**Star as a per-book flag (separate from shelves entirely).** Would
have meant introducing a third source of truth alongside readings and
shelves. The whole point of this ADR is to reduce the number of
sources, not increase them.

**Auto-create a regular syncing shelf called "Starred" without the
`default_for_star` machinery.** Tempting because it sidesteps the
"locked" semantics, but a user could then delete or rename-away the
shelf and the star icon would silently break. The lock is small (two
`before_*` callbacks); the breakage class it prevents is real.
