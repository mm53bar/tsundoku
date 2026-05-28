# Kobo cloud-sync — design notes

Phase 3 plan: pretend to be `storeapi.kobo.com` for one Kobo device so the
device's "Sync" button pulls books, covers, shelves, and reading state from
Tsundoku. Built on what calibre-web has been doing in production since 2019;
no firmware hacks, no DNS spoofing — one config line on the device.

Bias toward **make the sync round-trip work end-to-end with EPUB first**.
KEPUB conversion and reading-progress writeback can land later.

## 1. How a Kobo gets pointed at our server

Reader plugs the Kobo into a computer via USB. The Kobo mounts as a normal
disk. Edit one file:

```
/.kobo/Kobo/Kobo eReader.conf
```

Find the `[OneStoreServices]` section and replace one line:

```
[OneStoreServices]
api_endpoint=https://tsundoku.backson.boo/kobo/<handle>
```

Eject the device, tap **Sync** on the home screen. That's it — no factory
reset, no account deregistration, no firmware mods. Reverting is the same
file, replacing the URL with `https://storeapi.kobo.com`.

The path segment after `/kobo/` is a single mnemonic word generated per
user (e.g. `violin`, `tunnel`, `mercury`). See §3 for why a high-entropy
credential isn't worth the friction here, and why we don't just use the
raw username either.

## 2. TLS requirements

The Kobo firmware refuses plain HTTP for `api_endpoint`. It also appears to
validate certs against the system trust store, so:

- **Self-signed certs won't work.** No way to install a root CA on the device
  short of firmware patching.
- A **real cert from a public CA** (Let's Encrypt is fine) is required.
- For homelab use that means terminating TLS at the reverse proxy (NPM)
  with a real cert. We already do this; nothing new needed.

Note: the hostname needs a publicly-signed cert, but does **not** need to be
internet-reachable. `tsundoku.backson.boo` resolves only on the LAN — the
public CA cert is what Kobo's TLS validation cares about, not the routability
of the IP. The Kobo only syncs when it's on the home WiFi, which is fine.

## 3. URL layout — mnemonic handle

Calibre-web mounts everything under `/kobo/<auth_token>/...` with a 32-hex
random token. We don't need that. The endpoint is LAN-only, the worst-case
leak is "a guest discovers what books are in the library," and a high-entropy
credential adds friction (unreadable in logs, unverifiable by eye in the conf
file, requires a generation UI and a revocation flow) for security value
that's effectively zero in this deployment.

But we don't want to use the raw username either: a houseguest on the LAN
who knows Mike's username could trivially probe `/kobo/mmcclenaghan` and
pull the library. Slug-of-username doesn't fix that — the obscurity has to
be independent of identity.

The compromise: a **single mnemonic word** from a curated wordlist, stored
on the user, used as the URL path segment.

```ruby
# migration
add_column :users, :kobo_handle, :string
add_index  :users, :kobo_handle, unique: true

# model
class User < ApplicationRecord
  WORDLIST = File.readlines(Rails.root.join("lib/data/mnemonic_wordlist.txt")).map(&:strip).freeze

  def regenerate_kobo_handle!
    loop do
      candidate = WORDLIST.sample
      next if User.exists?(kobo_handle: candidate)  # tiny chance of collision in 1626-word space
      update!(kobo_handle: candidate)
      return candidate
    end
  end
end
```

URL the user puts in `eReader.conf`:

```
api_endpoint=https://tsundoku.backson.boo/kobo/violin
```

Properties:

- **Search space is ~1626 words** (the Tirosh mnemonic wordlist —
  phonetically-distinct, no homophones). ~10.7 bits of entropy. Trivial to
  brute-force with a script, but a houseguest casually probing isn't running
  a script. The point is removing the "guess the user's name and try it"
  attack, not surviving a determined adversary.
- **Revocable.** A "Regenerate" button on the user settings page generates a
  new word; the old URL stops working immediately. Mike re-edits
  `eReader.conf` on the Kobo (USB, 30 seconds).
- **Readable in NPM logs.** `kobo/violin` is meaningful in a way `kobo/<32 hex>`
  is not.
- **Lookup is one index hit.** `User.find_by!(kobo_handle: params[:handle])`.

The wordlist file ships in `lib/data/mnemonic_wordlist.txt` (one word per
line, ~15KB). Source: the Tirosh mnemonic wordlist
(https://web.archive.org/web/20090918202746/http://tothink.com/mnemonic/wordlist.html),
public domain.

Generation strategy: lazy. New users get `kobo_handle = nil`. A user visits
the "Sync with Kobo" settings page → if `kobo_handle.nil?`, we call
`regenerate_kobo_handle!` and show the URL. If a request hits `/kobo/...`
for a user with no handle (because they regenerated and abandoned), it 404s
as expected.

## 4. The wire protocol

All paths below are relative to `https://host/kobo/<token>/`.

### 4.1 Endpoints we must implement

| Method | Path | What it does |
|---|---|---|
| GET | `/` | Top-level. Return `{}`. |
| GET | `v1/library/sync` | **The main one.** Returns new/changed entitlements, reading states, and shelves as a JSON array. |
| GET | `v1/library/<book_uuid>/metadata` | Single-book metadata (re-fetched when device thinks it's stale). |
| GET | `v1/library/<book_uuid>/state` | Returns the current reading state for one book. |
| PUT | `v1/library/<book_uuid>/state` | **Device pushes reading progress here.** |
| DELETE | `v1/library/<book_uuid>` | Device asks to archive (remove from device-side library). |
| GET | `<book_uuid>/<w>/<h>/<grey>/image.jpg` | Cover thumbnail at the requested resolution. |
| GET | `download/<book_id>/<format>` | The actual EPUB download. |
| POST | `v1/library/tags` | Create shelf from device. |
| PUT | `v1/library/tags/<tag_id>` | Rename shelf from device. |
| DELETE | `v1/library/tags/<tag_id>` | Delete shelf from device. |
| POST | `v1/library/tags/<tag_id>/items` | Add book to shelf from device. |
| POST | `v1/library/tags/<tag_id>/items/delete` | Remove book from shelf from device. |

The `v1/user/*`, `v1/products/*`, and `v1/store/*` paths are normally proxied
to the real Kobo store. We will **not** proxy. Anything we don't implement
returns `{}` with 200. Worst-case the device shows an empty "Discover" tab —
no impact on sync.

Why no proxy: Calibre-web has an opt-in proxy mode (`config_kobo_proxy`)
that forwards unhandled requests to `storeapi.kobo.com` so the device's
discovery/wishlist features keep working against the real Kobo store.
Tsundoku doesn't want that — the whole point is to be the library, not
funnel users back to the store — and proxying means forwarding Kobo store
credentials through our server, which adds a risk surface for zero
Tsundoku-side value. Returning `{}` for unimplemented endpoints works
fine in practice. If we ever want to opt into the proxy behaviour, it's
straightforward to add (one Faraday call); leaving it out keeps the
scope honest.

**Firmware updates are unaffected.** The `api_endpoint` we hijack covers
only the store/sync API. Kobo firmware update checks use a separate host
that's not configurable from `eReader.conf` — the device continues to
talk to Kobo directly for update manifests and downloads, and updates
keep arriving normally. Documented Kobo behaviour: a device with a
broken/redirected sync endpoint still checks privately for firmware
updates. We're not a man-in-the-middle for updates, by design or accident.

### 4.2 The sync payload

`GET v1/library/sync` returns a JSON array. Each element is one of:

```json
{ "NewEntitlement":     { "BookEntitlement": {...}, "BookMetadata": {...}, "ReadingState": {...} } }
{ "ChangedEntitlement": { "BookEntitlement": {...}, "BookMetadata": {...}, "ReadingState": {...} } }
{ "ChangedReadingState":{ "ReadingState": {...} } }
{ "NewTag":     { "Tag": {...} } }
{ "ChangedTag": { "Tag": {...} } }
{ "DeletedTag": { "Tag": {...} } }
```

To remove a book, send a `ChangedEntitlement` with `BookEntitlement.IsRemoved: true`.

`BookEntitlement` (the minimum fields the device looks at):

```json
{
  "Accessibility": "Full",
  "ActivePeriod": { "From": "<iso8601>" },
  "Created": "<iso8601>",
  "CrossRevisionId": "<book-uuid>",
  "Id": "<book-uuid>",
  "IsRemoved": false,
  "IsHiddenFromArchive": false,
  "IsLocked": false,
  "LastModified": "<iso8601>",
  "OriginCategory": "Imported",
  "RevisionId": "<book-uuid>",
  "Status": "Active"
}
```

`BookMetadata` (only the fields that actually surface on-device):

```json
{
  "Categories": ["00000000-0000-0000-0000-000000000001"],
  "CoverImageId": "<book-uuid>",
  "CrossRevisionId": "<book-uuid>",
  "DownloadUrls": [
    { "Format": "EPUB3", "Size": <bytes>, "Url": "https://host/kobo/<token>/download/<book_id>/EPUB", "Platform": "Generic" }
  ],
  "EntitlementId": "<book-uuid>",
  "Language": "en",
  "PublicationDate": "<iso8601>",
  "Publisher": { "Imprint": "", "Name": "<publisher>" },
  "RevisionId": "<book-uuid>",
  "Title": "<title>",
  "WorkId": "<book-uuid>",
  "ContributorRoles": [{ "Name": "<author>" }],
  "Contributors": ["<author>"],
  "Series": { "Name": "<series>", "Number": <int>, "NumberFloat": <float>, "Id": "<deterministic-uuid>" }
}
```

The book UUID is **not** our integer `book.id` — it's a stable v5 UUID
derived from `book.id` (so it survives DB rebuilds if we ever re-key the
table). We'll add `book.kobo_uuid` as a generated column or compute it on
the fly with `Digest::UUID.uuid_v5(NAMESPACE, book.id.to_s)`.

### 4.3 SyncToken: how the device avoids re-downloading 1,000 books

The sync endpoint reads two headers and writes the same two back:

```
x-kobo-synctoken: <opaque base64>
x-kobo-sync: "continue"   (only if response was truncated)
```

The synctoken is an opaque cursor — the device just round-trips it. We
control its meaning. The simplest scheme that works:

```ruby
SyncToken = Struct.new(:books_last_modified, :reading_states_last_modified,
                       :tags_last_modified, :archive_last_modified)
```

Encode as JSON → base64. On each sync request:

1. Compute "books changed since `books_last_modified` for this user." That's
   the syncable-set, filtered by (a) reading-state-implied syncing, (b)
   any shelf the user has flagged `sync_to_kobo`.
2. Same for reading states and shelves.
3. Cap at 100 items per response (Kobo's `SYNC_ITEM_LIMIT`). If we hit the
   cap, set `x-kobo-sync: continue` and don't advance the cursor for the
   un-sent items.
4. Bump the cursor to the newest `last_modified` we *did* send.

For the first sync from a given device, the token is empty → everything
in the syncable-set is `NewEntitlement`.

Deletions are the awkward case — a row that's gone has no `last_modified`
to advance past. Two options:

- **Tombstone table** (`kobo_removed_books(user_id, book_uuid, removed_at)`)
  — most correct, lets us correctly send `IsRemoved: true` for books that
  drop out of the syncable set, and prune the table after a long retention
  window (90 days).
- **Compute the diff** between "what we previously sent" and "what we should
  send now" via a `kobo_synced_books(user_id, book_id)` join table. Less
  state, more work per sync.

Calibre-web does the second one (`KoboSyncedBooks`). I'd start there and
add tombstones only if it gets ugly.

## 5. What gets synced — the inclusion rule

This is the meat of the decision Mike already made. Restated for the record:

A book is in user U's syncable set if **any** of:

- User U has a `Reading` record for it with status in
  `[want_to_read, currently_reading]`.
- The book is on at least one of U's shelves where `sync_to_kobo = true`.

A book is **not** in the syncable set if:

- No reading record AND not on any syncing shelf.
- Reading record exists but status is `read`, AND not on any syncing shelf.

The "shelf-wins" case is implicit: if Mike marks a finished book as `read`
AND adds it to a shelf called "All-time greats" with `sync_to_kobo: true`,
the shelf wins. The book syncs. Status doesn't suppress an explicit opt-in.

Concrete query (rough Ruby):

```ruby
def syncable_book_ids_for(user)
  via_reading = user.readings.where(status: Reading::SYNCABLE_STATUSES).pluck(:book_id)
  via_shelves = ShelfEntry.joins(:shelf).where(shelves: { user: user, sync_to_kobo: true }).pluck(:book_id)
  (via_reading + via_shelves).uniq
end
```

## 6. Reading state mapping

Kobo speaks a 3-state model: `ReadyToRead` / `Reading` / `Finished`.
Tsundoku uses the same three states (with reader-friendly names) so the
mapping is 1:1 in both directions:

| Tsundoku `Reading.status` | Kobo `Status` |
|---|---|
| `want_to_read` | `ReadyToRead` |
| `currently_reading` | `Reading` |
| `read` | `Finished` |

**Tsundoku → Kobo**: straight rename, no logic.

**Kobo → Tsundoku** (when device PUTs `/state`): the device is
authoritative for state transitions during active use. The Kobo sees
what the reader is actually doing — when they open a book, when they
finish it — and we trust that signal.

| Kobo `Status` arrives | Action on Reading record |
|---|---|
| `ReadyToRead` | Upsert to `want_to_read` (create row if missing). |
| `Reading` | Upsert to `currently_reading`, stamp `started_at` if not already set. Includes the "user opened a `read` book to re-read it" case — we transition back to `currently_reading` and clear `finished_at`. |
| `Finished` | Upsert to `read`, stamp `finished_at`. |

The "user switches to another book mid-read" case is naturally correct:
the first book's state on the Kobo stays `Reading` (the device just
opened a different file), so no PUT is sent for the first book, so its
Tsundoku state stays `currently_reading`. Matches the way the device
already behaves.

Progress data (`ProgressPercent`, `Location`) is opaque-ish — store it on
the `Reading` record as new columns:

```ruby
add_column :readings, :progress_percent, :integer
add_column :readings, :location, :string        # opaque "Value" from Kobo
add_column :readings, :location_type, :string   # opaque "Type"
add_column :readings, :location_source, :string # opaque "Source"
add_column :readings, :synced_at, :datetime     # last time Kobo pushed
```

We don't render progress in the UI for v1 — just store it round-trip so
"pick up where I left off" works across devices.

## 7. Shelves

Almost 1:1 with our existing model. We already have `Shelf.sync_to_kobo`.
The Kobo side needs:

```json
{
  "Tag": {
    "Created":      "<iso8601>",
    "Id":           "<shelf-uuid>",   // deterministic UUID from shelf.id
    "Items":        [ { "RevisionId": "<book-uuid>", "Type": "ProductRevisionTagItem" } ],
    "LastModified": "<iso8601>",
    "Name":         "<shelf.name>",
    "Type":         "UserTag"
  }
}
```

Items in `Tag.Items` are filtered to **only books that are themselves in
the syncable set**. A book on a syncing shelf but whose row isn't being
sent to the device shouldn't appear in the shelf's items list — that
creates a dangling reference on the device.

When the device creates a shelf locally and pushes it (`POST tags`), we
mirror it as a new `Shelf` owned by the auth-token's user. Mike's call:
new shelves from the device default to `sync_to_kobo: true` (otherwise we'd
create-then-immediately-stop-syncing, which is confusing) but they're
visible in the Tsundoku UI and Mike can untoggle.

## 8. KEPUB vs EPUB

Kobo's native format is KEPUB — same EPUB container but with extra spans
inserted into the XHTML so the firmware can track reading position by
paragraph. EPUB plays on a Kobo but with degraded features (less accurate
progress, no "estimated time left in chapter").

The conversion tool is `kepubify` — Go binary, no deps, fast (a 5MB EPUB
converts in ~200ms). Komga runs it on-the-fly server-side.

**v1 decision: ship EPUB only.** The download endpoint serves the raw EPUB
from disk, format-tagged as `EPUB3` in the sync payload. KEPUB conversion is
a v1.1 feature — add it when reading-progress fidelity actually matters to
someone.

When we do add it, the right shape is:

- A Solid Queue job that converts on demand and caches the result to
  `storage/kepub/<book_uuid>.kepub.epub`.
- Cache invalidates on `book.updated_at` change.
- The download endpoint streams from cache, kicks the job if missing,
  returns 503 with Retry-After if the conversion isn't done yet.

The Kobo retries reliably, so 503-then-200 is fine.

## 9. Implementation phases

Each phase is a coherent slice that can be smoke-tested.

**Phase A — handle + base controller + settings page** (~half a session)
- `kobo_handle` column on `User`, unique index.
- `lib/data/mnemonic_wordlist.txt` checked in (Tirosh wordlist).
- `User#regenerate_kobo_handle!` method.
- "Sync with Kobo" page under user settings: shows the current URL,
  generates a handle on first visit, has a "Regenerate" button.
- `Kobo::BaseController` with `User.find_by!(kobo_handle:)` lookup.
- Route `/kobo/:handle` mounted, bypassing Authelia in NPM.
- One smoke endpoint: `GET /kobo/<handle>/` returns `{}`.
- Test against a real Kobo: visit settings → copy URL → paste into
  `eReader.conf` → sync → confirm "library is empty" (not "sync failed").

**Phase B — read-only library sync** (~one session)
- `GET v1/library/sync` returning entitlements + metadata for the
  syncable set, ignoring shelves and reading state.
- `GET .../image.jpg` for covers (resize on the fly or pre-generate).
- `GET download/.../EPUB` streaming the file from disk.
- SyncToken cursor support (start with timestamp-only; tombstones can wait).
- Smoke test: real device pulls real books, opens one, reads a page.

**Phase C — shelves** (~half a session)
- Shelves in the sync payload, filtered to in-set books only.
- POST/PUT/DELETE on `v1/library/tags*` so device-side shelf edits write
  back to Tsundoku.

**Phase D — reading state** (~half a session)
- Reading state in the sync payload.
- `PUT /state` accepts the device's progress writes, applies the mapping
  rules from §6.
- Progress columns on `Reading`.

**Phase E — KEPUB** (deferred, only if requested)
- Kepubify-based on-demand conversion, cached to disk.

## 10. Decisions log

Resolved during design review:

1. **NPM Authelia bypass for `/kobo/*` — DONE.** Wired on NPM host 51 as
   a `location /kobo/ { ... }` block above the catch-all `location /`,
   with no `auth_request` directive. Verified: `/kobo/v1/whatever` reaches
   Rails directly (returns Rails' 404 page, not openresty's), all other
   paths still 302 to Authelia. The proxy no longer gates `/kobo/*` — the
   app must validate every request itself (handled in phase A).

2. **Auto-sync new books — NO.** Newly-imported books with no reading
   record and no syncing-shelf membership don't sync. Books appear on the
   Kobo only after an explicit action (set a status or add to a syncing
   shelf). Keeps the device's library small and intentional.

3. **Series IDs in payload — YES, deterministic.** Use
   `Digest::UUID.uuid_v5(NAMESPACE, series.id.to_s)` so the device groups
   by series in "My Books." Implement in phase B.

4. **Drop-out behaviour — send `IsRemoved: true`.** When a book leaves
   the syncable set (marked `read`, removed from last syncing shelf), we
   send a `ChangedEntitlement` with `IsRemoved: true`. The device
   archives it. Device is treated as a mirror of the syncable set.

## 11. References

- janeczku/calibre-web — `cps/kobo.py`, `cps/kobo_auth.py`,
  `cps/kobo_sync_status.py`. Original PR #1100 by @shavitmichael.
- Komga's Kobo sync docs — same `[OneStoreServices]` pattern, confirms
  the protocol generalizes.
- Jordan Palmer, "Setting up Kobo sync with Calibre Web" — confirms the
  config-file path and HTTPS-only requirement.
- Maintenance reality: the Kobo protocol is closed-source and Kobo
  periodically changes it. Firmware 4.38.23552 (released 2025-11-13)
  broke calibre-web sync — see calibre-web issue #3492. We inherit the
  same chase: when a future firmware update breaks our sync, the first
  move is to check what fix calibre-web shipped and port it.
- The Kobo firmware itself is closed-source; everything above is from
  observing real device traffic, not from docs Kobo published.
