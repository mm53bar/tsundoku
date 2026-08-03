# 20260803 — Secrets come from the environment; no bespoke `config/secrets/` mount

## Context

The app needs exactly two secrets at runtime:

- `secret_key_base` — Rails' session/cookie signing key. Rails 8.1 resolves it
  as `ENV["SECRET_KEY_BASE"] || credentials.secret_key_base` (see
  `railties.../application/configuration.rb#secret_key_base`), so an env var
  alone satisfies it and the credentials store is never consulted.
- `HARDCOVER_APP_API_TOKEN` — optional; enables Hardcover enrichment.
  `HardcoverClient` reads `credentials.hardcover_app_api_token.presence ||
  ENV["HARDCOVER_APP_API_TOKEN"].presence`.

Nothing else reads from `Rails.application.credentials`. Because this is a
**public template repo**, `credentials.yml.enc` is deliberately never committed
(a committed `secret_key_base` would be shared by every downstream clone), and
`config.require_master_key` is false — so `credentials.foo` returns `nil`
rather than raising when no key/file is present.

To let operators still use Rails' encrypted credentials inside a container, an
earlier design added a probe in `application.rb` that repointed
`config.credentials.{content,key}_path` at a bind-mounted `config/secrets/`
directory. In practice no deployment uses it: the live stack (Jumbo) mounts no
such directory, has no credentials file, and runs fine on `SECRET_KEY_BASE`
from the environment. The probe was unused surface area.

## Decision

Standardize on **environment variables as the secret source** and remove the
`config/secrets/` probe.

- `SECRET_KEY_BASE` (required) and `HARDCOVER_APP_API_TOKEN` (optional) are
  supplied via the environment — directly in the compose file, or via Docker
  secrets for operators who want them off-disk.
- Rails' **conventional** encrypted credentials remain a working escape hatch
  with zero custom code: set `RAILS_MASTER_KEY` and ship a
  `config/credentials.yml.enc`. `.gitignore` keeps both out of git.
- `HardcoverClient`'s `credentials || ENV` fallback stays — it's harmless
  (returns `nil` with no credentials) and is what makes the escape hatch work.

## Consequences

- One less mechanism to document and reason about; the deploy story is "set two
  env vars." Matches what the live deployment already does.
- Operators who preferred the `config/secrets/` bind-mount lose that specific
  path. The conventional Rails credentials location still works, and env is the
  blessed route regardless — an acceptable trade for a template repo.
- No behavior change on existing deployments: they already resolve
  `secret_key_base` from `ENV`.

## Alternatives considered

- **Keep the `config/secrets/` probe as an optional power-user path.** Rejected:
  unused by any real deployment, and the conventional credentials location
  covers the same need without custom initializer code.
- **Move the Hardcover token into the `Setting` model (see
  [`20260628-settings-in-database.md`](20260628-settings-in-database.md)).**
  Rejected: settings hold *non-secret* operator config; a credential in a
  plaintext SQLite column would be a downgrade from env/credentials, and
  encrypting it would pull in Active Record Encryption keys for marginal gain.
- **Adopt Rails 8.2 combined credentials (`Rails.app.creds`).** Deferred: not in
  a released Rails (latest is 8.1.3.x; the feature is on `main`). When we bump
  to 8.2 it can replace the manual `credentials || ENV` line — a drop-in
  ergonomic follow-up, not an architectural change.
