# 20260530 — Reading status derives from progress; the status enum is gone

Extends `20260530-reading-sync-intent-split.md` (which split
`sync_to_device` out of `status`). That ADR kept `status` as an
explicit progress signal driven by the UI; this one removes it as a
stored value entirely. The derivation now happens from
`progress_percent` and `finished_at`.

## Context

After splitting sync intent out into `sync_to_device`, the remaining
`status` enum (`want_to_read`, `currently_reading`, `read`) was a
user-set label that *also* tried to encode progress state. That left
two problems:

1. **It lied about the data.** The Kobo's `PUT /state` carries the
   real progress percentage. If the device says 12% and the user
   manually set status to `read`, the system was internally
   inconsistent. The library "Currently reading" filter and the
   per-book progress strip both keyed off the *manual* status,
   ignoring the actual reading data — exactly backwards.

2. **It made user actions ambiguous.** "Mark as currently reading"
   should be a side effect of opening a book on the Kobo, not a
   thing the user explicitly does. Conversely, "mark as finished"
   needs an explicit affordance for the "I read this on paper"
   case, but the dropdown forced the user to pick a status even
   when no manual override was relevant.

The conversation that led here started when Sheila joined the
household: she expected the "Reading" tab to reflect what she was
actually reading on her Kobo, not whatever status someone had set
in Tsundoku.

## Decision

Drop the `status` enum entirely. Derive progress state from the
fields that carry the actual data:

```ruby
FINISHED_THRESHOLD_PCT = 95

def progress_state
  return :finished    if finished_at.present? || (progress_percent || 0) >= FINISHED_THRESHOLD_PCT
  return :in_progress if (progress_percent || 0).positive?
  :not_started
end
```

Mirror the derivation as SQL scopes on `Reading` (`.in_progress`,
`.finished`, `.not_started`) so the library filter and the navbar
"Reading" pill can query without loading rows into Ruby. The
threshold constant is referenced once per scope.

The Kobo wire format mapping (`ReadyToRead` / `Reading` / `Finished`)
becomes a simple lookup keyed on the derived symbol.

### Timestamp transitions

The model carries a `before_save :stamp_progress_timestamps` callback
that runs whenever `progress_percent` changes:

- `started_at` is stamped the first time progress goes positive
- `finished_at` is stamped when progress crosses
  `FINISHED_THRESHOLD_PCT`
- `finished_at` is *cleared* if progress drops back below the
  threshold (re-read)

That keeps the timestamps honest without any controller code having
to set them explicitly.

### Incoming Kobo `Status` is mostly ignored

The device's `PUT /state` sends both `StatusInfo.Status` and
`CurrentBookmark.ProgressPercent`. Status is informational — our
state is derived from progress. There's one case where the value
matters:

> A user long-presses a book on the device and taps "Mark as
> finished" without reading to the end. The device sends
> `Status: "Finished"` while progress stays at whatever it was.

For that case, `Kobo::ReadingStatesController#apply_status` stamps
`finished_at` and bumps `progress_percent` to 100. Otherwise the
device's Status field gets ignored.

### UI changes

The old status_picker dropdown is replaced. The book show page now
has three controls:

- **Sync toggle** — flips `sync_to_device`. Creating a Reading is a
  side effect of toggling sync on for a book that has none yet.
- **Status chip** — shows the derived state ("Not started" /
  "Reading 12%" / "Finished"). Clickable to flip
  finished/unfinished (manual override).
- **Remove from my list** — destroys the Reading record. Tombstones
  flow via the existing `removed_book_records` sync path.

`ReadingsController#update` accepts `sync_to_device` and
`mark_finished` params; `#destroy` clears the Reading row.

### Migration

A single migration drops the column. Rows with `status=read` get
their `finished_at` and `progress_percent` populated where missing,
so the derivation produces the same observable state on the other
side. `currently_reading` and `want_to_read` rows need no backfill —
their `(progress_percent, started_at, finished_at)` already encode
the right state.

## Consequences

- `Reading.status`, `Reading::KOBO_STATUS_MAP`,
  `Reading.tsundoku_status_for(kobo_status)`, and the transitional
  `default_sync_to_device_from_status` callback are all gone. The
  model carries one constant table (`KOBO_STATUS`) for the wire
  format and one threshold.
- The Library filter and the navbar "Reading" pill key on actual
  progress data — they reflect what the user is reading, not what
  some stored label says.
- A user can mark a finished book "unfinished" without losing
  device-reported progress. A user can mark a paper-read book
  finished without ever opening it on the Kobo.
- `sync_to_device` is now the only thing the user explicitly chooses
  about a Reading record. Everything else flows from progress.
- The `20260530-reading-sync-intent-split.md` ADR is partially
  superseded by this one — its `SYNCABLE_STATUSES` is gone (already
  was, this just removes the wider status concept), and its
  description of the legacy transitional callback no longer applies.
  The "status as progress signal" framing it described has been
  replaced by full derivation.

## Alternatives considered (not chosen)

- **Keep `status` but auto-set it from progress.** A computed column
  or a callback that updates `status` whenever progress changes.
  Adds two-way bookkeeping for no gain — the derived value is what
  it is, no point storing a redundant copy.
- **Use a virtual attribute** (`store_accessor` or similar) for
  `status` to keep the dropdown UI. Same problem — the dropdown was
  the wrong UI, not the storage layer.
- **Keep the dropdown but make it a "progress override" control.**
  Too confusing — most users don't override progress; the dropdown
  would imply they should.
