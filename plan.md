# Tsundoku — Rails book-management app

Self-hosted replacement for most of Calibre-Web-Automated. Rails 8 / SQLite, deployed via Docker Compose on Synology. Family of 3, ~300 books, OIDC via Authelia, Kobo cloud-sync emulation deferred to a later phase.

> 積ん読 — *tsundoku*: the practice of acquiring books and letting them pile up unread.

## Decisions locked in

- **Stack:** Rails 8.1 on Ruby 3.4.7 (pinned via `.mise.toml`). SQLite (WAL mode). Tailwind CSS v4 with the Tailwind Plus "Oatmeal" template (taupe_instrument). Hotwire (Turbo/Stimulus). Importmap. SolidQueue/SolidCache/SolidCable for background jobs and cache (no Redis container).
- **View layer:** Rails partials + helpers + Stimulus controllers. No ViewComponent.
- **Testing:** Minitest with fixtures. No RSpec. No factories. No mocks.
- **Auth:** Forward-auth via Nginx Proxy Manager + Authelia. The app trusts `Remote-User` / `Remote-Email` / `Remote-Name` request headers injected by the proxy and auto-provisions users keyed on `Remote-User`. First user gets `admin`; subsequent users default to `reader`. The app never speaks OIDC itself — no client registration, no client secret. In development, `/dev_login` bypasses auth via session cookie. **Note:** `Remote-User` collides with the CGI standard `REMOTE_USER` env var, so the controller reads it via `request.headers["HTTP_REMOTE_USER"]` directly, not the friendly `request.headers["Remote-User"]` lookup (which returns nil).
- **Deployment:** `compose build: <github-url>` from this repo. GitHub repo will be public from day one. No GHCR publish (door left open via build-args pattern but not used).
- **UID/GID handling:** `ARG UID=1000 / ARG GID=1000` in Dockerfile, overridden per-host via compose build args. Mike's Synology overrides to `1027:100`.
- **Library access:** Rails owns its own SQLite DB. Reads Calibre `metadata.db` read-only during bulk import. Never writes to `metadata.db`. EPUB files on disk are the source of truth for content; Rails DB is the source of truth for metadata.
- **Filesystem layout in container:** `/library` (Calibre tree, RW), `/ingest` (Shelfmark drop, RW), `/rails/storage` (Rails SQLite + Active Storage + caches).
- **Networking:** Local domain `backson.boo`. Nginx Proxy Manager (`npm.backson.boo`) fronts the app, terminates TLS, forwards plain HTTP to the container.
- **Kobo sync:** out of MVP. CWA stays running headless on the same library volume during phases 1–3. Port from `cps/kobo.py` in phase 4.
- **In-browser reader:** out of scope.

## Open items before deployment

1. **Shelfmark ingest path** on Synology — host path that will mount to `/ingest`. Set as `INGEST_DIR` in `.env`.
2. **UID/GID on the library volume** — confirmed `1027:100` for Mike's Synology.
3. **NPM forward-auth config** — configure `tsundoku.backson.boo` proxy host to require Authelia via forward-auth, injecting `Remote-User` / `Remote-Email` / `Remote-Name` headers. Same template the rest of the homelab uses.
4. **Oatmeal template** — unpack `oatmeal-taupe-instrument.zip` and integrate components (deferred to Phase 1 styling pass).

## Phase 0 — Spike — DONE (locally)

Skeleton complete. Remaining work is operational: register the Authelia client, set up the GitHub repo, deploy to Synology.

What's in place:

- Rails 8.1 app generated with Tailwind v4, Hotwire, importmap, SolidQueue/Cache/Cable.
- `.mise.toml` pinning Ruby 3.4.7 and Node 25.6.1.
- `config/application.rb`: env-driven `LIBRARY_PATH`, `INGEST_PATH`, `TZ` with dev-friendly defaults (`storage/library_dev`, `storage/ingest_dev`).
- `User` model with `oidc_sub`, `email`, `name`, `role` enum (`reader`/`admin`). Migration applied.
- Forward-auth: app reads `Remote-User` / `Remote-Email` / `Remote-Name` from request headers (the proxy gates; the app trusts). `ApplicationController` auto-provisions a `User` on first request.
- `SessionsController#destroy` redirects to `AUTHELIA_LOGOUT_URL` (if set) to end the SSO session. `DevSessionsController` provides `/dev_login?as=<name>` for local work.
- `LibraryController#index` — protected page that lists EPUBs from `config.x.library_path`.
- Application layout with header, current-user/sign-out, flash messages.
- `Dockerfile` with `ARG UID=1000`/`ARG GID=1000` defaults, robust user creation that handles existing GIDs (Synology GID 100 case).
- `compose.yaml` with build args, three bind mounts (library/ingest/config), all OIDC + TZ env vars, `:?required` enforcement for must-have values.
- `.env.example` with sane Synology defaults.

Verified locally: `bin/rails server` boots, `/` redirects unauthed users to `/sign_in`, `/up` returns 200.

**Exit criterion for deployment:** Mike's browser hits `https://tsundoku.backson.boo/`, gets redirected to Authelia, logs in, returns to a page that does a basic `Dir.glob` over `/library` and renders filenames.

## Phase 1 — Library MVP (target: 2–3 weeks evenings)

Goal: family can browse and search the existing 300-book library.

1. **Data model + migrations:** `books`, `authors`, `books_authors`, `series`, `books_series`, `tags` (with `kind`), `books_tags`, `publishers`, `identifiers`, `formats`, `user_books` (incl. `marked_for_sync`, `marked_for_acquisition`).
2. **Calibre importer service:** opens `/library/metadata.db` read-only (sqlite3 gem, side connection), iterates `books`, populates Rails DB, links `data` rows to format file paths under `books.path`. Idempotent (skip-or-update by `calibre_id`).
3. **Rake task / admin button** to run the import. First run = bulk import all 300.
4. **Library index page:** paginated, sortable (title / author / added-at), filter by tag and series.
5. **SQLite FTS5 virtual table** over title + authors + description. Search box on the index page.
6. **Book detail page:** cover (read `cover.jpg` from book dir, cache via Active Storage), metadata, formats list with download links, mark-for-sync toggle (no-op for now, just persists state).
7. **Admin-only metadata editor:** edit title, author links, tags. The single feature CWA does worst.
8. **Authorization:** `admin` can edit; `reader` can read + toggle their own `user_books` flags.

**Exit criterion:** family logs in from their phones, browses the library, searches, downloads an EPUB. CWA still doing Kobo sync, untouched.

## Phase 2 — Ingest + metadata enrichment

Detailed empirical research lives in [`docs/metadata-acquisition.md`](docs/metadata-acquisition.md) — source ranking, the Hardcover GraphQL recipe (including the `_ilike`-is-blocked / use-`_eq` quirk and the title-cleanup it forces), Wikidata SPARQL for awards & curated-list membership, identity-resolution heuristics, and why Google Books / Open Library mostly aren't worth the trouble.

Headline takeaways to build to:

- **Hardcover is the primary source.** `omniauth`-style env var: `HARDCOVER_APP_API_TOKEN`. ~80% match rate. Description, ISBN, release date, rating, cover.
- **Wikidata is the only source for awards and curated-list membership.** Slow but the data exists nowhere else.
- **Identity resolution is the work.** Bias toward no match over a wrong match — bad data is worse than a gap.
- **One-book-at-a-time on ingest**, never bulk. Bulk runs are what trigger rate limits.
- **Don't try to derive audience (kids/YA/adult) from an LLM.** Trust Hardcover's tags or mark for human review.

## Phase 3 — Discoverability

(Deferred detail.)

## Phase 4 — Kobo sync port from `cps/kobo.py`

(Deferred detail. The wild-card phase.)

## Phase 5 — Polish

(Deferred detail.)
