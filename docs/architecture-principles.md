# Architecture principles

This app prefers Rails conventions and explicit domain modeling over architecture-heavy patterns.

## 1. Prefer Rails over layers

Use normal Rails structure unless there is a strong reason not to:

- models for domain state and rules
- controllers for request/response flow
- jobs for background work
- views/helpers/partials for rendering
- POROs when a real domain/support concept needs a home

Avoid adding abstraction layers just to look "clean".

## 2. Prefer rich models and domain POROs over service objects

Do not default to verb-based service objects.

Bad default shape:

- `DoThingService`
- `BookUpdaterService`
- `MetadataApplierService`

Preferred direction:

- put durable business rules on the model that owns them
- extract a PORO when it represents a real concept with a clear boundary
- name extracted objects as nouns, not verbs

Examples in this app:

- `BookAssets` is a good PORO because "a book's on-disk assets" is a real concept
- a future `MetadataProposal` would be a good PORO because the enrichment flow has a real proposal/review concept

## 3. Authorization should stay simple

This app does not currently need Pundit or CanCan.

Preferred approach:

- use ownership-scoped lookups where that is the natural privacy boundary
  - example: `current_user.shelves.find(...)`
- use `User` predicates for meaningful action permissions
  - example: `can_edit_book?`, `can_manage_lists?`

Guidelines:

- predicates should describe real actions
- avoid predicates for UI fragments or presentation details
- keep authorization readable at the callsite
- if rules become substantially more complex later, revisit — do not prebuild a framework now

## 4. Keep controllers narrow

Controllers should mostly:

- load records
- check permissions
- delegate to domain behavior
- choose the response

If a controller starts owning durable business rules, look for the real concept that should own them.

Do not automatically solve controller bloat with a generic service object.

## 5. `BookAssets` boundary

`BookAssets` exists to centralize book file/path concerns.

It owns:

- safe path resolution under approved roots
- EPUB / KEPUB / cover path lookup
- file availability checks
- cover MIME type
- cleanup of book-owned files on disk

It should not quietly become the home for unrelated behavior such as:

- conversion workflows
- remote downloads
- Kobo sync policy
- protocol payload decisions

If a change pushes beyond file/path ownership, stop and identify the real concept first.

## 6. Protect important invariants with tests

Several behaviors in this app — proxy-auth user provisioning, path safety, Kobo sync and tombstone handling, KEPUB selection, search query semantics, task lifecycle — regress quietly when they break. When changing those areas, add or update tests. CI gates on `bin/rails test`; the operational checklist of risky areas lives in `CLAUDE.md`.

## 7. Explain *why*, not *what*

The "what" is in the code. The "why" disappears with the original author unless captured. When behavior is non-obvious or driven by an external constraint (a Kobo device quirk, a Calibre convention, a security boundary, an empirical workaround), leave a comment explaining the reason. The existing codebase already does this well in the Kobo controllers and a few model methods — keep that habit.

## 8. Record significant decisions as ADRs

Architectural decisions with meaningful alternatives and lasting consequences belong in `docs/adr/` — see the existing ADRs for format and tone. Examples of ADR-worthy decisions: a security boundary, a sync invariant, an authorization strategy, a choice between two model shapes, a deliberate "we picked X over Y" with a non-obvious rationale.

Coding preferences and general principles do *not* need ADRs — they live in this file and in `CLAUDE.md`. The bar for an ADR is "a future reader will need to know why we did it this way, and the answer isn't obvious from the code."
