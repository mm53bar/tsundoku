# 20260530 — Split sync intent from reading progress on `Reading`

Amends 20260528-reading-state-model.md (the `SYNCABLE_STATUSES` rule
described there is replaced by what follows).

> **Further extended by `20260530-reading-status-derived-from-progress.md`.**
> This ADR introduced `sync_to_device` and kept `status` as a manual
> progress signal. The follow-up ADR drops the `status` enum entirely
> and derives state from `progress_percent` + `finished_at`. The split
> recorded here still holds; the "transitional callback" and "status
> picker UI" pieces no longer apply.

## Context

The original `Reading` model conflated two orthogonal concepts into the
single `status` enum:

- **sync intent** — "I want this book on my Kobo"
- **reading progress** — "I'm 12% through this book"

The three statuses mapped to fixed points on both axes:

```
want_to_read       = sync + not started
currently_reading  = sync + in progress
read               = don't sync + finished
```

That left three combinations inexpressible:

- finished, keep on device (re-read material, references)
- in progress, not synced to Kobo (reading on phone, audiobook in
  parallel, etc.)
- not started, on device, not actively wanted (CWA imports — books the
  device has but the user hasn't classified)

The CWA migration is where this stopped being theoretical. Books CWA
had synced needed `sync_to_device = true` regardless of their progress
percentage. Picking `want_to_read` vs `currently_reading` based on
CWA's progress data felt like lying about the user's intent.

## Decision

Add a `sync_to_device` boolean column to `Reading`. Keep `status` as a
*progress* signal. Each is independent.

```
sync_to_device:  boolean — explicit "I want this on my Kobo"
status:          want_to_read | currently_reading | read
                 — progress: not started / in middle / finished
```

`Kobo::BaseController#syncable_books` now keys on `sync_to_device =
true`, not on a status whitelist. The `SYNCABLE_STATUSES` constant is
removed.

A `before_save` callback bridges the old UI: when `status` changes and
the caller has not explicitly set `sync_to_device`, the legacy mapping
applies (`want_to_read | currently_reading → true`, `read → false`).
Explicit `sync_to_device` assignments win — the CWA import sets the
flag directly and the callback leaves it alone.

The `kobo_status` wire mapping (Tsundoku status ↔ Kobo's `ReadyToRead /
Reading / Finished`) keeps working unchanged — the device's sense of
status is still progress, not sync.

## Consequences

- All six combinations are expressible. The UI still only exposes the
  status picker, so today's user-visible behavior is unchanged. A later
  PR can split the UI into a separate sync toggle + progress chip
  without further model changes.
- Existing rows migrate cleanly: `want_to_read | currently_reading →
  sync_to_device: true`, `read → sync_to_device: false`. Backfilled by
  the migration; no data-loss path.
- Callers that set `sync_to_device` explicitly opt out of the callback.
  The CWA import is the only one today; future code can do the same.
- `SYNCABLE_STATUSES` is gone. Anything that was filtering on it needs
  to switch to `where(sync_to_device: true)`. Caught at compile time.
- The 20260528 ADR's "status drives sync inclusion" rule no longer
  applies and is amended by this one.
