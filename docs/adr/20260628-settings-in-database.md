# 20260628 — Operator settings live in the database, not just env

## Context

A handful of per-deployment integration values — the Shelfmark base URL and
the Authelia logout URL — were read straight from environment variables
(`config.x.shelfmark_url` ← `SHELFMARK_URL`; `ENV["AUTHELIA_LOGOUT_URL"]`).
Changing either meant editing the compose/stack and redeploying. For a
self-hosted app whose operator is also a normal user, that's heavier than it
should be: these are runtime configuration, not secrets or boot-time infra
(unlike `RAILS_MASTER_KEY` or the library bind-mount path, which must exist
before the app runs).

## Decision

Introduce a single-row `Setting` model that holds operator-editable
configuration, surfaced through an in-app settings screen.

- `Setting.current` returns the one settings row (`first_or_create!`). Call
  sites go through it; nobody queries `Setting` directly. It's an explicit
  noun with named columns (`shelfmark_url`, `authelia_logout_url`), not a
  generic key/value store or settings DSL — consistent with the
  rich-model / no-generic-indirection principles.
- `effective_*` accessors fall back to the legacy env vars when the stored
  value is blank, so existing env-based deployments keep working unchanged.
  Once values are saved in the UI, the env vars can be dropped.
- Editing is gated by `User#can_edit_settings?`, a **passive** predicate that
  returns `true` today (every signed-in household member is trusted — see
  `docs/architecture-principles.md` §3). It exists so a future, less-trusted
  deployment can restrict settings editing in one place, without introducing
  an admin-role assumption now.

## Consequences

- Operators change these values in the app, no redeploy.
- The transition is safe: blank setting → env fallback → unset disables the
  feature (Shelfmark links hide; logout returns to home), preserving today's
  behavior.
- The model is the home for future operator settings. Resist turning it into
  a generic settings framework — add typed columns for real, named settings.

## Alternatives considered

- **Keep env-only.** Rejected: requires a redeploy for a runtime value, and
  this operator's stack tooling (Arcane) has been unreliable about env vars.
- **Generic key/value settings table + DSL.** Rejected per the architecture
  principles (no generic indirection); typed columns are clearer and
  type-safe for a small, known set.
- **Boot-time config (`config.x`) only.** That's right for infra that must
  exist before the app runs; these values don't qualify.
