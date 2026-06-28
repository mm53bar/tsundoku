# 20260530 — Auto-ingest via Solid Queue recurring job

## Context

The existing ingest flow required a person to visit `/ingest` and click
"Scan." Files dropped into `INGEST_PATH` (by Shelfmark, by manual
copy, by anything that writes there) sat untouched until someone
remembered to scan. For a household where one user drops books and a
different user reads them, that's a coordination problem — Robin
shouldn't have to ask "did the book I added show up in Tsundoku yet?"

Three implementation strategies were on the table:

1. **Filesystem watcher (inotify, fswatch)** — runs continuously,
   reacts to filesystem events. Most "real time" but requires a
   long-running watcher process outside the Rails stack. Operational
   overhead.
2. **Container-level cron** — a cron daemon inside the container
   running `bin/rails ingest:scan` periodically. Lower-level than
   Rails idioms, splits the schedule definition outside the codebase.
3. **Solid Queue recurring job** — Rails-native, schedule lives in
   `config/recurring.yml` next to the existing
   `clear_solid_queue_finished_jobs` entry, runs in the existing
   queue worker. Same operational footprint as the rest of the app.

## Decision

Option 3. `AutoIngestScanJob` runs every 2 minutes, walks
`INGEST_PATH` for `.epub` files, and queues an `IngestFileJob` per
file — the same handoff the manual `/ingest/scan` button has always
used. The downstream flow (`BookIngester` → optional auto-enrichment
→ KEPUB conversion) is unchanged.

### Task tray surfaces only when work happened

The Task model's existing visibility rules (`Task.visible` =
`active.or(pending_review).or(recently_settled)`) drive how the tray
behaves on each kind. Non-reviewable tasks marked succeeded settle
within ~30 seconds via `recently_settled`. Reviewable tasks (the
`metadata_enrichment` ones spawned by ingest) stay as `pending_review`
until the user opens the edit form.

To keep the tray quiet on empty scans:

- **Empty scan → no task created.** The job runs silently every 2
  minutes whether or not there's anything in the directory; that
  noise shouldn't appear in the tray or the logs.
- **Work happened → one summary task.** A single `auto_ingest_scan`
  task is created and immediately marked succeeded (the actual work
  is the spawned per-file `IngestFileJob`s). The summary appears
  briefly — "Auto-ingest: queued N files" — then settles. The
  per-file `book_ingest` tasks follow the same lifecycle; the
  downstream `metadata_enrichment` tasks land in `pending_review`
  and stay visible until the user reviews them.

### Idempotency

The recurring scan can race with itself or with the manual `Scan`
button if a file's still being processed. The job checks for any
in-flight (`queued` or `running`) `book_ingest` task with a matching
`result["file_path"]` before queueing a duplicate. Files with a
prior `failed` or `succeeded` task aren't filtered — the recurring
scan effectively becomes the retry mechanism for transient failures.

`IngestFileJob` moves the file out of `INGEST_PATH` on success, so
under steady-state no in-flight check would even be needed —
subsequent scans see nothing because the file is gone. The check
guards the mid-flight window.

## Consequences

- Robin drops a book into Shelfmark; within ~2 minutes it's in the
  Tsundoku library with an enrichment proposal queued.
- The manual `/ingest` page stays as-is, both for the "do it now"
  case and for visibility into what's pending.
- One extra log line per active scan: `AutoIngestScanJob queued N
  of M pending files`. Empty scans log nothing.
- Failed ingests retry on the next scan window (every 2 minutes
  until `IngestFileJob`'s `retry_on` exhausts attempts, then
  effectively forever until the file is removed or fixed). For the
  homelab "I dropped a corrupt EPUB" case that's acceptable; the
  Task lifecycle surfaces the failure in the tray.

## Alternatives considered (not chosen)

- **Inotify watcher** — would react instantly but adds an
  always-running process outside the Rails stack. Operational
  cost > UX benefit at homelab scale.
- **Schedule every 30 seconds instead of 2 minutes** — would
  shorten the "I just dropped a book" delay. Tradeoff: more wakeups
  for the queue worker, more empty `Dir.glob`s on the bind-mounted
  filesystem. 2 minutes is a reasonable middle ground.
- **Roll the per-file ingest tasks into the summary as sub-tasks**
  — would require a parent-child relationship on Task. Existing
  flat task model already surfaces per-file outcomes in the tray;
  collapsing them would obscure individual failures.
