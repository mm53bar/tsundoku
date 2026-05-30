# 20260530 — Forward-auth via proxy headers, no in-app auth stack

## Context

Tsundoku is a multi-user homelab app (one household). It needs to
identify the requesting user — different users have different reading
records, shelves, Kobo handles. It does not want to ship the
operational burden of an in-app auth stack: password storage,
forgotten-password flows, session crypto, OIDC client registration,
secret rotation, etc.

Two trust models were on the table:

1. **Embedded auth.** Tsundoku owns the full login flow. Self-
   sufficient. Heavy to maintain for a one-person operator who
   already runs a household SSO (Authelia) for every other service.
2. **Forward-auth.** A reverse proxy (nginx-proxy-manager in this
   deployment) handles authentication and injects identity headers
   into upstream requests. Tsundoku trusts those headers.

Option 2 is dramatically lighter operationally — no secret to rotate
in the app itself, no password reset code path, no UI for account
management. It's also strictly less safe: it's only sound when the
app is genuinely unreachable except via the proxy.

## Decision

Forward-auth via proxy headers. Specifically:

- `ApplicationController#resolve_current_user` reads the request's
  `HTTP_REMOTE_USER`, `HTTP_REMOTE_EMAIL`, and `HTTP_REMOTE_NAME`
  values (set by the proxy as `Remote-User` / `Remote-Email` /
  `Remote-Name` headers).
- `User.find_or_provision_from_proxy` creates the matching `User` row
  on first sight, updating email/name on subsequent requests if they
  change.
- The first ever provisioned user is auto-assigned the `admin` role;
  later users default to `reader`. Bootstrap convention; matches the
  pattern calibre-web uses.
- Development bypasses forward-auth: `bin/rails server` in dev
  redirects unauthenticated requests to `/dev_login`, which signs in
  as any username without proxy headers. Production absolutely
  depends on the proxy.
- The `/kobo/:handle/*` namespace is the exception. The Kobo device
  can't send `Remote-User`, so authentication for that namespace is
  by the mnemonic handle in the URL itself (see
  `20260528-kobo-url-mnemonic-handle.md`). NPM has a location-block
  carve-out that skips Authelia for those paths.

## Consequences

- **The deployment invariant is non-negotiable: Tsundoku MUST NOT be
  reachable except via the proxy.** If a future deployment exposes
  the container's port directly (without the proxy in front), anyone
  on the network can `curl -H "Remote-User: mike"` and become Mike.
  `compose.yaml` documents this with a comment at the top:
  > Authentication: the app trusts Remote-User / Remote-Email /
  > Remote-Name headers injected by the upstream proxy
  > (nginx-proxy-manager + Authelia forward-auth). It MUST be reached
  > only via the proxy. Do not expose port directly to clients.
  This is fundamentally an operational constraint outside the app's
  ability to enforce.
- No password storage, no session crypto, no OIDC client to rotate.
  Single source of identity is Authelia.
- Users appear in Tsundoku on their first request through the proxy.
  No separate signup or admin-provisioning flow. Onboarding a new
  family member is "Authelia knows about them" + "they visit the
  Tsundoku URL once."
- The first-user-becomes-admin convention is a footgun for empty
  databases. If you re-seed prod and a non-admin user hits the URL
  first, they become admin. Acceptable for a homelab where the
  operator controls who hits the URL first; would be unacceptable
  for a public-facing app.
- The Kobo namespace's mnemonic-handle auth has its own ADR and is
  intentionally separate. Forward-auth doesn't apply to it.
- Tests use the `HTTP_REMOTE_USER` header to authenticate (see
  `test/controllers/search_controller_test.rb#headers_for`).
- `User#find_or_provision_from_proxy` is exercised by tests in
  `test/models/user_test.rb` — first-user-becomes-admin, name
  defaults, email update on re-visit, role doesn't change on
  re-visit, etc.

## Alternatives considered (not chosen)

- **OIDC client in-app** — would let Tsundoku negotiate directly with
  Authelia. More moving parts than forward-auth and Authelia
  recommends forward-auth for upstream services anyway.
- **Basic auth via the proxy** — would still require the proxy in
  front, with worse UX. No reason to take that hit.
- **Trust a JWT in a cookie** — would couple Tsundoku to a specific
  proxy's JWT shape. Forward-auth headers are agnostic.
