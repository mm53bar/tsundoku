# 20260528 — Hardcover as primary metadata source

## Context

The ingest pipeline needs to enrich locally-imported EPUBs with reliable
metadata: descriptions, ISBNs, release dates, covers, genres. Several
free sources exist; each has its own quirks under real-world volume from
a homelab IP. The relevant question is not "which has the best data" in
the abstract — it's "which works reliably from a homelab IP, at the
volumes a one-household library generates."

Tested sources, in order of how they shook out:

- **Hardcover.app** — GraphQL API. Reliable from a homelab IP. Covers
  descriptions, ISBNs, release dates, ratings, genres, covers in one
  query. ~80% match rate on a real library. Authentication is a long-
  lived JWT from Settings → API.
- **Wikidata** — only structured source for awards and curated lists
  ("won the Pulitzer," "on Oprah's list"). SPARQL endpoint, slow,
  fuzzier matching. Useful for a narrow purpose, not as a workhorse.
- **Open Library** — spotty. 403s `node` and `undici` user agents
  (fingerprinting) while still answering `curl`. Usable with Faraday + a
  real User-Agent and paced requests, but unreliable enough to be a
  fallback only.
- **Google Books** — HTTP 429 from homelab IPs almost immediately, even
  unauthenticated. Effectively unusable for batch enrichment from a
  residential connection.

## Decision

Hardcover is the **primary** enrichment source. The match flow runs
against Hardcover first, accepts a result when one is found, and only
falls through to others when Hardcover has no match.

Wikidata is used for **awards and curated lists** only, not for the main
enrichment fields.

Open Library is a **fallback** for the cases where Hardcover finds
nothing. Used with explicit pacing and a real User-Agent.

Google Books is **not used at all.**

The full source-by-source recipe (queries, normalization, quirks
encountered) is documented in `docs/metadata-acquisition.md`. This ADR
records the priority decision; that doc records the empirical recipe.

## Consequences

- The match rate is good but not 100% — books not on Hardcover (small
  presses, older editions, non-English titles) get a no-match outcome
  rather than a wrong-match. The pipeline bias is "no match over a wrong
  match" everywhere; this priority order respects that.
- We depend on Hardcover staying free and stable. If they ever close the
  API or require payment, the pipeline degrades to "Open Library
  fallback only," which is a significant quality hit. Mitigation: store
  raw fetched data so re-enrichment from a new source is possible.
- The Google Books rejection is a homelab-specific call. From a non-
  residential IP they're usable; we'd reconsider if the deployment shape
  ever changed.
