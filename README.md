# Tsundoku

A self-hosted Rails app for managing a family ebook library — browse, search, ingest, curate, and (eventually) sync to Kobo e-readers.

> 積ん読 — *tsundoku*: the practice of acquiring books and letting them pile up unread.

## Status

Early. Phase 0 skeleton is in place; not yet doing anything useful. See [plan.md](plan.md) for the build plan.

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

Visit `http://localhost:3000`. You'll be redirected to `/sign_in`. In development, click "Dev login" to bypass OIDC and sign in as any username. The first user created gets the `admin` role; everyone after that defaults to `reader`.

## Production deployment (Docker Compose)

Tsundoku expects to live behind a reverse proxy that handles authentication and injects identity headers (`Remote-User`, `Remote-Email`, `Remote-Name`). It must not be exposed directly to clients.

1. Copy `.env.example` to `.env` and fill in the values (host paths, UID/GID matching your library volume owner, Rails master key).
2. Update `compose.yaml`'s `build.context` to point at your fork's URL.
3. Configure your reverse proxy (NPM, Caddy, Traefik) to authenticate the host and forward `Remote-*` headers. With Authelia, forward-auth via the proxy is the typical setup.
4. `docker compose up -d --build`.

## Stack

Rails 8.1 · Ruby 3.4 · SQLite · Tailwind v4 · Hotwire · SolidQueue/Cache/Cable · Forward-auth (no OIDC client in-app).
