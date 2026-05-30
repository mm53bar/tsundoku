# Tsundoku Rails-Oriented Code Review

Last updated: 2026-05-30

## Purpose

This document captures a Rails-oriented code review of the current codebase, with emphasis on:

- whether the app feels "Rails-y"
- where it follows or deviates from typical Rails conventions
- code smells and OO concerns
- architectural direction that stays close to Rails norms
- guidance for future implementation agents

This review intentionally prefers:

- rich domain models over generic service objects
- POROs with domain names over procedural "verb classes"
- simple authorization predicates and ownership scoping over policy gems
- Rails conventions over architecture-heavy patterns

---

## Executive summary

Overall, this codebase is **mostly Rails-y and structurally healthy**.

The strongest parts are:

- conventional Rails app structure
- sensible Active Record modeling
- good use of join models
- pragmatic Hotwire/Turbo usage
- clear comments explaining domain quirks
- a generally coherent domain around books, shelves, readings, lists, and Kobo sync

The main risks are:

1. **controllers accumulating domain/process logic**
2. **authorization rules being scattered and ad hoc**
3. **filesystem and external integration rules split across layers**
4. **very light test coverage relative to the amount of custom behavior**
5. **some "service object" style classes that should eventually be reconsidered as richer domain concepts or POROs**

The newer features reviewed here — **KEPUB conversion** and **navbar search** — are both reasonable additions. The search feature is fairly idiomatic. The KEPUB feature is useful and pragmatic, but it increases the need for a clearer home for book file/path concerns.

---

## What is working well

### Conventional Rails structure

The app uses familiar Rails structure:

- `app/models`
- `app/controllers`
- `app/jobs`
- `app/views`
- `app/helpers`

That makes the codebase approachable to a Rails developer.

### Domain modeling is generally good

The core entities are sensible and well separated:

- `Book`
- `Author`
- `Series`
- `Publisher`
- `Reading`
- `Shelf` / `ShelfEntry`
- `List` / `ListEntry`
- `Task`
- Kobo-specific sync models

This is a good sign. The app is not trying to flatten everything into one giant table or one giant model.

### Good use of join models

Using explicit join models like:

- `BookAuthor`
- `ShelfEntry`
- `ListEntry`

is very Rails-y and gives room for ordering and future metadata. This is preferable to `has_and_belongs_to_many`.

### Hotwire/Turbo usage is pragmatic

Turbo streams for task updates and shelf toggles are reasonable and fit Rails well.

The navbar search using a debounced Stimulus controller plus a Turbo Frame is also a good Rails-native approach. It avoids overengineering and keeps the interaction simple.

### Comments explain important invariants

There are many comments that explain *why* something exists, especially around:

- proxy auth behavior
- Kobo quirks
- sync/tombstone behavior
- Turbo frame behavior

That is valuable in a codebase with external-system constraints.

---

## Overall Rails-ness

### Feels Rails-y

The codebase generally feels like a Rails app, not a framework-agnostic architecture exercise.

Good examples:

- Active Record associations and scopes doing real work
- controllers handling request/response concerns
- jobs for background work
- ERB partials and helpers
- resourceful routes for most core resources

### Where it drifts from the Rails happy path

The main drift is not structure, but **placement of behavior**.

A fair amount of business/process logic currently lives in:

- controllers
- "service object" style classes
- models that mix persistence, workflow, and presentation concerns

That is common in growing Rails apps, but it is where the codebase is most likely to become less idiomatic over time.

---

## Architectural direction recommended

This review recommends the following direction:

- prefer **rich domain models**
- prefer **POROs with domain names** over generic service objects
- prefer **simple authorization predicates on `User`**
- prefer **ownership scoping and model scopes** over policy gems
- extract **nouns, not verbs**

Examples of good extraction targets:

- a book asset/path concept
- a metadata proposal concept
- Kobo payload/domain objects if that area grows
- model-level query scopes for visibility/ownership

This review does **not** recommend introducing:

- Pundit
- CanCan
- a generic "service layer"
- clean architecture style indirection

unless the app becomes much more complex than it is today.

---

## Main review findings

## 1. Controllers are carrying too much domain/process logic

This is the biggest structural concern.

### `BooksController`

`BooksController` currently owns a lot of behavior beyond request orchestration:

- task review consumption
- publisher application
- author parsing and rebuilding
- accepted identifier validation
- cover download
- safe path resolution
- MIME type logic
- EPUB path resolution

This is not ideal Rails controller shape.

A Rails controller is healthiest when it mostly:

- loads records
- checks permissions
- delegates to domain behavior
- chooses the response

Right now `BooksController` is acting partly as an application service.

### `ListsController`

`ListsController` also contains meaningful workflow logic around:

- parsing entries
- matching books
- reimport preview and apply flow

This is understandable, but it is another sign that process logic is living in controllers.

### `Kobo::SyncController`

This controller is more defensible because it is effectively an integration endpoint, but it also contains a lot of payload-building logic that may eventually want a better home if it grows further.

### Recommendation

Do not replace controller logic with generic service objects.

Instead, look for **domain concepts** hiding inside the workflows.

Likely candidates:

- a metadata proposal object
- a book asset/path object
- Kobo payload objects if needed later

---

## 2. Authorization is scattered, but does not need a policy gem

The app has authorization rules, but they are expressed in several styles:

- `current_user.shelves.find(...)`
- duplicated `require_admin!`
- ad hoc ownership checks
- controller-specific redirect behavior

This is a maintainability issue, but it does **not** justify Pundit or CanCan yet.

### Recommended direction

Use a simple Rails-native split:

#### A. Predicates on `User`

Examples of the style to prefer:

- `user.can_edit?(book)`
- `user.can_manage?(shelf)`
- `user.can_destroy?(list)`
- `user.can_import_library?`

These should stay short, readable, and tied to real domain actions.

#### B. Ownership/visibility scopes on models

Use model scopes for collection loading and visibility boundaries.

Examples conceptually:

- shelves owned by a user
- tasks visible to a user
- books visible in a given context

#### C. Keep ownership-scoped lookups where they are natural

Patterns like:

- `current_user.shelves.find(...)`

are still good Rails and should not be removed just for abstraction's sake.

### Concern or no concern?

Do **not** move authorization predicates into a concern immediately.

Start with methods directly on `User`.

A concern only makes sense if the authorization methods become numerous enough to form a coherent slice of `User` behavior. Otherwise it is just indirection.

---

## 3. "Service objects" should be reconsidered case by case

This codebase already has several classes under `app/services`. Some are reasonable, but the category itself should be treated skeptically.

### Why

A lot of service objects are just procedural code in a class wrapper. That often makes Rails code less expressive, not more.

### Better question

Instead of asking "what should be a service?", ask:

- what is the domain concept?
- who owns this rule?
- is this behavior about a thing or a process?

### Good candidates for eventual PORO/domain extraction

#### Book asset/path concept

This is the clearest candidate.

Right now file/path logic is split across:

- `Book`
- `BooksController`
- Kobo download/sync behavior
- KEPUB conversion behavior

A PORO representing book assets or book files would give one home to invariants like:

- where EPUB lives
- where KEPUB lives
- where cover lives
- what paths are safe
- what is downloadable
- what can be deleted

This is a real concept, not a generic service.

#### Metadata proposal concept

The enrichment flow has a real domain concept hiding inside it:

- proposed fields
- proposed identifiers
- proposed cover
- accepted/rejected pieces
- review lifecycle

That wants to be a named object more than a controller-private workflow.

#### Kobo payload concepts

If Kobo sync grows further, concepts like:

- entitlement
- tag payload
- reading state payload
- metadata payload

may deserve POROs with domain names.

### Classes that are acceptable for now

Some process-oriented classes are understandable even if they are not ideal nouns, especially import/integration code. But they should not become the default pattern for all new behavior.

---

## 4. `Task` is useful, but at risk of becoming a god object

`Task` currently handles:

- workflow state
- progress tracking
- reviewability
- visibility rules
- UI broadcasting
- friendly titles

This is pragmatic and useful, but it mixes several layers:

- persistence
- workflow semantics
- presentation
- UI side effects

That is not a crisis yet, but it is a growth risk.

### Recommendation

Do not refactor aggressively right now.

Just be careful not to keep piling unrelated concerns into `Task`.

If it grows further, likely split points are:

- lifecycle/state behavior
- UI broadcasting
- presentation/title formatting

---

## 5. Filesystem concerns are spread across layers

This is one of the most important design issues in the app.

The app legitimately needs filesystem access, but the rules are currently split across:

- `Book`
- `BooksController`
- Kobo download logic
- KEPUB conversion logic
- deletion callbacks

This makes it harder to see the single source of truth for:

- safe path resolution
- file existence
- file deletion
- file serving
- derived artifacts like KEPUB

### Why this matters

This is both a design concern and a security concern.

The app has important invariants around path safety and allowed roots. Those invariants should ideally have one obvious home.

### Recommendation

Prefer a domain/support PORO around book assets/files rather than continuing to spread this logic across model, controller, and job code.

---

## 6. Test coverage is far too thin

This is the biggest practical risk in the codebase.

There is already substantial custom behavior around:

- proxy auth and user provisioning
- import
- enrichment proposal generation
- list parsing and matching
- shelf toggling
- reading state transitions
- Kobo sync payloads and tombstones
- file/path safety
- KEPUB conversion
- navbar search query behavior

But there is almost no meaningful test coverage.

### Recommendation

Before adding much more behavior, prioritize tests around the highest-risk invariants.

High-value targets:

- `User.find_or_provision_from_proxy`
- `Author.normalize_name`
- `BookMatcher`
- `Task` lifecycle and visibility
- path traversal / safe file resolution
- Kobo sync payload and tombstone behavior
- KEPUB availability and download selection
- search query behavior and result scoping
- controller request tests for admin/ownership rules

---

## Review of newer feature: KEPUB conversion

## Summary

This feature is useful and pragmatic. It fits the domain and the Kobo integration well.

The implementation is reasonable, but it strengthens the case for a clearer home for book file/path concerns.

## What is good

### Background job is the right shape

Using a background job for conversion is appropriate. Conversion is operational work, not request-cycle work.

### Graceful fallback behavior

The sync/download flow falls back to EPUB when KEPUB is unavailable. That is a good user-facing behavior and keeps the feature additive.

### Atomic-ish output handling

Using a temporary output and rename is a good instinct to avoid serving partial files.

### Sync integration is coherent

Touching the book so Kobo sync emits updated download URLs is a pragmatic solution and makes sense in the current architecture.

## Concerns

### Comment drift / storage location mismatch

The job comment says output is cached in Rails storage, but the implementation writes the KEPUB alongside the EPUB in the library path.

The model comment reflects the actual behavior. The job comment does not.

This is small, but worth fixing because these filesystem decisions matter.

### File/path logic is now even more distributed

KEPUB adds more file behavior to `Book` and Kobo controllers, which increases the need for a single concept around book assets/files.

### Operational dependency on `kepubify`

This is fine, but it is an external runtime dependency. The code should be explicit in docs/setup about that requirement.

### Missing tests

This feature especially wants tests around:

- when conversion runs
- when it is skipped
- KEPUB preferred over EPUB in sync payloads
- fallback to EPUB when KEPUB missing
- deletion cleanup behavior

## Rails-ness assessment

This feature is acceptable and pragmatic in Rails terms. The main issue is not that it is "un-Rails-y", but that it adds more behavior to an already blurry file/path boundary.

---

## Review of newer feature: navbar search

## Summary

This feature is fairly Rails-y and well chosen.

A debounced Stimulus controller plus a Turbo Frame endpoint is a good Rails-native solution for lightweight autocomplete.

## What is good

### Good interaction model

The feature avoids overengineering:

- no SPA complexity
- no custom JSON API needed
- server-rendered fragment
- simple Stimulus behavior

That is very much in the Rails spirit.

### Search endpoint is simple

`SearchController#show` is small and focused. That is good controller shape.

### UI integration is straightforward

The search bar in the header is easy to understand and reasonably isolated.

## Concerns

### Search logic is currently controller-owned

The query itself lives directly in the controller. That is okay for now, but if search grows beyond title/author autocomplete, it may want a better home.

A model scope or named query object would be more Rails-y than letting the controller accumulate search semantics.

### Potential duplication with client-side library filtering

There is already client-side library filtering logic elsewhere. That is not necessarily wrong, but it means there are now multiple search/filter concepts in the app:

- client-side library filtering
- navbar autocomplete search

That is fine if they are intentionally different, but worth keeping conceptually separate.

### Missing tests

This feature wants request/view coverage around:

- minimum query length
- title and author matching
- result limit
- empty-state rendering

## Rails-ness assessment

This is one of the more idiomatic recent additions. It fits Rails well.

---

## Model and OO observations

## Good OO choices

- explicit domain entities
- join models with ordering
- model methods that express domain concepts
- scopes that encode query intent
- comments documenting invariants

## OO concerns

### `Book` is becoming a gravity well

`Book` now touches:

- metadata
- authors/tags/identifiers
- readings
- shelves
- lists
- Kobo UUID and sync behavior
- file paths
- KEPUB availability
- deletion cleanup

That is natural for a central entity, but it means new behavior should be added carefully.

### Hidden invariants

There are important rules enforced mostly by comments and convention:

- safe path resolution under approved roots
- proposal-backed identifier acceptance
- viewing edit form marks enrichment reviewed
- tombstone behavior for Kobo sync
- first user becomes admin
- KEPUB should supersede EPUB for Kobo when available

These are exactly the kinds of rules that deserve tests and, where possible, clearer object boundaries.

---

## Security and robustness notes

## Good

- path traversal concerns are clearly on the author's mind
- proxy auth caveat is documented
- Kobo endpoints are isolated from normal auth flow
- accepted identifiers are revalidated against proposal
- search query uses SQL-like sanitization

## Concerns

### Proxy auth trust boundary is critical

The app trusts upstream headers. That is acceptable only if deployment guarantees the app is not directly exposed.

This should remain a first-class deployment invariant.

### Filesystem safety should be centralized

There are multiple places where path safety matters. The more this spreads, the easier it is to accidentally bypass the intended guardrails.

### External fetch/runtime dependencies

The app depends on external systems and tools:

- Hardcover
- `kepubify`
- filesystem mounts
- proxy auth headers

That is fine, but it increases the need for tests, docs, and clear boundaries.

---

## Specific recommendations

## Priority 1: add tests

Highest-value missing tests:

- auth/user provisioning
- ownership/admin request behavior
- Kobo sync/tombstone behavior
- file/path safety
- KEPUB selection/fallback
- search endpoint behavior
- task lifecycle behavior

## Priority 2: centralize authorization in a Rails-native way

Recommended approach:

- add readable permission predicates on `User`
- add model scopes for visibility/ownership where useful
- keep ownership-scoped lookups where natural
- do not add Pundit/CanCan yet

## Priority 3: extract a book asset/path concept

This is the best candidate for a PORO/domain object.

It would reduce duplication and make file-related invariants easier to preserve.

## Priority 4: reduce controller-owned workflow logic

Especially in:

- `BooksController`
- `ListsController`

Do this by extracting domain concepts, not generic service objects.

## Priority 5: watch `Task` and `Book` for overgrowth

No urgent rewrite needed, but both are central enough that new responsibilities should be added carefully.

---

## Things that are fine and should not be "fixed" just for purity

- using background jobs for import/enrichment/conversion
- custom routes where the domain genuinely needs them
- Kobo-specific namespaced controllers
- pragmatic comments explaining weird device behavior
- SQLite for the stated scale
- Stimulus + Turbo for lightweight interactivity

---

## Suggested authorization direction

The preferred direction for this app is:

### On `User`

Use readable predicates such as:

- can import library?
- can edit this book?
- can manage this shelf?
- can edit this list?

These should stay simple and domain-oriented.

### On models

Use scopes for:

- ownership
- visibility
- review queues
- user-specific collections

### In controllers

Use:

- ownership-scoped lookups where natural
- `current_user.can_x?` checks for action permissions

### Avoid for now

- policy gems
- a custom authorization framework
- moving everything into concerns too early

---

## Suggested PORO/domain extraction candidates

These are the best candidates for future extraction without drifting into service-object architecture:

### 1. Book asset/path object

Owns:

- EPUB path
- KEPUB path
- cover path
- safe resolution
- availability
- deletion rules

### 2. Metadata proposal object

Owns:

- proposed fields
- proposed identifiers
- proposed cover
- acceptance validation/application semantics

### 3. Kobo payload objects (only if needed later)

Owns:

- entitlement payload
- tag payload
- metadata payload
- reading state payload

### 4. Search query object or model scope (optional)

Only if navbar search grows beyond its current simple autocomplete role.

---

## Short agent prompt

Use this when handing work to an implementation agent.

### Agent prompt

You are working in a Rails app that prefers Rails conventions over architecture-heavy patterns.

Follow these rules:

- Prefer rich domain models and well-named POROs over generic service objects.
- Do not introduce Pundit, CanCan, or a policy framework unless explicitly requested.
- Prefer simple authorization predicates on `User` plus model scopes and ownership-scoped lookups.
- Keep controllers focused on loading records, checking permissions, and choosing responses.
- If extracting logic, extract nouns/concepts, not verb-based "service" classes.
- Be especially careful with file/path logic, Kobo sync invariants, and task lifecycle behavior.
- Add or suggest tests around important invariants when touching risky areas.

Read this file before making architectural changes:
`docs/reviews/rails-code-review.md`

---

## Bottom line

This is a good Rails codebase with solid domain instincts.

The main goal now is not to replace it with a grand architecture. The goal is to keep it Rails-y as it grows by:

- strengthening domain boundaries
- centralizing authorization simply
- avoiding service-object sprawl
- adding tests around the important invariants
- giving filesystem/integration rules a clearer home
