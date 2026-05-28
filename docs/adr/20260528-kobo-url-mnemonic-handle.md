# 20260528 — Mnemonic word as the Kobo sync URL credential

## Context

The Kobo's "Sync" button hits a server-configured URL on every sync. We
spoof that server, so our URL is what the device sends. The URL needs a
path segment that identifies which user the sync is for — multi-user
homelab, one Kobo per person.

Calibre-web's convention is `/kobo/<32-hex-token>/...`, with the token
generated server-side and stored in a `RemoteAuthToken` table. The token
is treated like a password: cryptographically random, single-use,
revocable.

That's overkill for our deployment:

- `tsundoku.backson.boo` resolves only on the LAN. The endpoint isn't
  internet-reachable. The realistic attackers are "a houseguest on the
  WiFi" and "a malware'd IoT device" — neither is running a brute-force
  script.
- The worst-case leak is "an attacker discovers what books are in the
  library." Not credential-tier sensitive.
- A 32-hex token is unreadable in NPM logs, unverifiable by eye in
  `eReader.conf`, and requires a generation/revocation UI.

Two simpler alternatives were considered:

- **Username (or username slug) as the path segment.** Zero overhead, but
  trivially probed by a houseguest who knows Mike's name. Removes the
  obscurity layer entirely.
- **Short mnemonic word from a curated wordlist.** Adds a tiny obscurity
  layer (a guest has to guess one of ~1626 words, not one of two known
  usernames) at the cost of one column + one settings page. The word is
  independent of identity, so it can be rotated without renaming the
  user.

## Decision

A `kobo_handle` column on `User`, populated by random selection from the
[Oren Tirosh mnemonic wordlist](https://github.com/nerab/wordlist) (1626
phonetically-distinct English words, 4–7 letters). The wordlist ships in
the repo at `lib/data/mnemonic_wordlist.txt`.

The URL is `https://tsundoku.backson.boo/kobo/<handle>` — e.g.
`/kobo/violin`. The handle is generated lazily on first visit to the
user's "Sync with Kobo" settings page, and regenerable via a button on
the same page.

Lookup is `User.find_by!(kobo_handle: params[:handle])` — one indexed hit.

## Consequences

- Defeats the realistic threat (casual probing by anyone on the LAN who
  knows a username) without adding a high-entropy credential's worth of
  friction.
- Trivially brute-forced by a determined attacker running a script — but
  that attacker doesn't exist for a LAN-only homelab endpoint that
  surfaces only book metadata.
- Regenerating the handle invalidates the device URL — the user has to
  re-edit `eReader.conf` over USB (~30 seconds). That's the revocation
  mechanism; acceptable because revocation is rare.
- Readable in NPM logs (`kobo/violin` is meaningful where `kobo/<32 hex>`
  is not).
- We carry a ~25KB wordlist file in the repo forever. Worth it.
- This decision is specific to the LAN-only deployment shape. If
  Tsundoku ever gets exposed to the internet, this ADR needs revisiting
  — a mnemonic word is not strong enough for an internet-facing endpoint.
