# Tsundoku

A self-hosted Rails app for managing a family ebook library — browse, search, ingest, curate, and sync to Kobo e-readers.

> 積ん読 — *tsundoku*: the practice of acquiring books and letting them pile up unread.

## Status

Active. Imports from a Calibre library, enriches metadata via Hardcover, syncs to Kobo devices (entitlements, covers, KEPUB downloads, shelves, reading state with progress + bookmarks), and supports CWA migration. Multi-user via forward-auth. See [plan.md](plan.md) for the build plan and [docs/](#docs) for the design records.

## Local development

```bash
# Install Ruby and Node via mise (versions pinned in .mise.toml)
mise install

# Install gems
bundle install

# Set up the database
bin/rails db:prepare

# Drop a few test EPUBs into storage/library_dev/ for the index page to find

# Start the dev server
bin/rails server
```

Visit `http://localhost:3000`. You'll be redirected to `/dev_login` — sign in as any username. The first user created gets the `admin` role; everyone after that defaults to `reader`.

Run the test suite:

```bash
bin/rails test
```

## Production deployment (Docker Compose)

Tsundoku expects to live behind a reverse proxy that handles authentication and injects identity headers (`Remote-User`, `Remote-Email`, `Remote-Name`). **It must not be exposed directly to clients** — anyone reaching the container directly can spoof the headers. See [`docs/adr/20260530-proxy-auth-trust-model.md`](docs/adr/20260530-proxy-auth-trust-model.md).

1. Copy `.env.example` to `.env` and fill in the values (host paths, UID/GID matching your library volume owner, Rails master key).
2. Configure your reverse proxy (NPM, Caddy, Traefik) to authenticate the host and forward the `Remote-*` headers. With Authelia, forward-auth via the proxy is the typical setup.
3. `docker compose up -d`.

The image is built by GitHub Actions and published to `ghcr.io/mm53bar/tsundoku:latest` (and `:<short-sha>` for pinning). If you're running a fork, point the `image:` line in `compose.yaml` at your own registry.

## Migrating from Calibre-Web-Automated

If you're coming from CWA, two rake tasks handle the handoff:

```bash
# 1. Adopt Calibre's books.uuid as kobo_uuid so the device de-dupes
#    against entitlements CWA already pushed.
bin/rails kobo:migrate_from_cwa

# 2. Import CWA's per-user sync state and reading progress.
#    Optional: mount your CWA config dir as /cwa-config (see compose.yaml).
bin/rails 'kobo:import_sync_state_from_cwa[<cwa_user>,<tsundoku_user>]'
```

After both, trigger a sync from your Kobo — the device should keep the books it already has, drop the orphans, and gain any books that were imported but not yet on the device.

## Stack

Rails 8.1 · Ruby 3.4 · SQLite (WAL) · Tailwind v4 · Hotwire (Turbo + Stimulus) · SolidQueue / SolidCache / SolidCable · `kepubify` (EPUB→KEPUB conversion) · Forward-auth (no OIDC client in-app).

## Docs

- [`CLAUDE.md`](CLAUDE.md) — short, agent-facing implementation rules
- [`docs/architecture-principles.md`](docs/architecture-principles.md) — durable architectural philosophy and boundaries
- [`docs/reviews/rails-code-review.md`](docs/reviews/rails-code-review.md) — historical Rails-oriented code review snapshot
- [`docs/kobo-sync-design.md`](docs/kobo-sync-design.md) — the Kobo sync protocol and Tsundoku's implementation
- [`docs/metadata-acquisition.md`](docs/metadata-acquisition.md) — the metadata enrichment design
- [`docs/adr/`](docs/adr/) — architectural decision records:
  - [`20260528-kobo-url-mnemonic-handle.md`](docs/adr/20260528-kobo-url-mnemonic-handle.md) — Kobo URL credential
  - [`20260528-metadata-source-priority.md`](docs/adr/20260528-metadata-source-priority.md) — Hardcover as primary metadata source
  - [`20260528-reading-state-model.md`](docs/adr/20260528-reading-state-model.md) — `Reading` model + three-state status (partially superseded)
  - [`20260528-shelf-wins-sync-conflict.md`](docs/adr/20260528-shelf-wins-sync-conflict.md) — shelves win on sync conflicts
  - [`20260528-shelves-as-parallel-curation.md`](docs/adr/20260528-shelves-as-parallel-curation.md) — shelves alongside readings
  - [`20260530-reading-sync-intent-split.md`](docs/adr/20260530-reading-sync-intent-split.md) — `sync_to_device` separated from progress
  - [`20260530-kobo-tombstone-strategy.md`](docs/adr/20260530-kobo-tombstone-strategy.md) — tombstones survive `Book#destroy`
  - [`20260530-book-assets-boundary.md`](docs/adr/20260530-book-assets-boundary.md) — `BookAssets` PORO as the file/path boundary
  - [`20260530-proxy-auth-trust-model.md`](docs/adr/20260530-proxy-auth-trust-model.md) — forward-auth via proxy headers
  - [`20260530-passive-authorization-and-list-ownership.md`](docs/adr/20260530-passive-authorization-and-list-ownership.md) — passive predicates + list ownership
  - [`20260530-reading-status-derived-from-progress.md`](docs/adr/20260530-reading-status-derived-from-progress.md) — drop the status enum, derive from progress
