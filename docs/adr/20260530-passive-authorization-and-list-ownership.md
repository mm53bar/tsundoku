# 20260530 — Passive authorization predicates + per-record ownership for lists

## Context

After the first authorization pass (capability predicates on `User`,
gating actions like book editing and Calibre import on `admin?`), the
app had two failure modes that pulled in opposite directions.

**Failure mode 1: trusted-user friction.** Sheila is a household
member, not an admin. She tried to trigger Hardcover enrichment on a
book she was reading and couldn't — `BooksController#enrich` was
admin-only. The same friction applied to book edits, deletes, and
list management. All of these are normal household-member activity
in this deployment.

**Failure mode 2: no per-record ownership.** Lists were global. Any
admin could edit or destroy any list. "Sheila's want-to-read with
kids" and "Mike's all-time favourites" lived in the same pool with
the same edit authority. The role-based gate didn't capture the
relationship.

The deeper issue is that `admin?` was being used as the primitive
for two questions it isn't:

1. "Is this user trusted enough to take action?" — in a homelab with
   Authelia gating the front door, everyone signed in is trusted.
2. "Does this user own this thing?" — a real per-record question
   that `admin?` can't answer.

## Decision

Two parallel changes.

### Passive predicates for action permissions

`User#can_X?` predicates that previously returned `admin?` now return
`true` for any `User` instance:

```
can_import_library?  can_ingest?           can_edit_book?
can_destroy_book?    can_enrich_book?      can_manage_lists?
```

The named predicates stay so callsites read in terms of capability
(`current_user&.can_edit_book?(book)`, not `current_user&.admin?`).
The names give a future deployment in a less-trusted context one
place to tighten without touching every controller and view.

`current_user&.can_X?` returns nil for anonymous requests
(`current_user` is nil; `nil&.can_X?` is nil; falsy at the callsite).
That's the gate against unsigned-in users — unchanged.

The `require_admin!` before_actions in `BooksController`,
`LibraryController`, and `IngestController` are removed. They were
the wrappers around the predicate that always passes now.

Friction for genuinely destructive actions stays where it already was
— the danger-zone reveal on `Book#destroy`, the concurrency guard on
`CalibreImportJob`. Those are intent-confirmation gates, not role
gates.

### Per-record ownership for lists

Lists are no longer global. Each list belongs to a user. The owner can
edit/destroy and manage entries; non-owners can view a list only if
the owner explicitly opts in via a "Share with others" flag.

Schema:

- `lists.user_id` — FK, not null. Existing rows backfill to the first
  user.
- `lists.shared` — boolean, default false. Existing rows backfill to
  `true` so prior behavior survives the migration.

Model:

- `List belongs_to :user`
- `List.for(user)` returns owned + shared lists.
- `User#can_edit_list?(list)` becomes a real ownership check
  (`list.user_id == user.id`), not passive.

Controllers:

- `ListsController` uses `set_visible_list` for `#show` (anyone with
  visibility) and `set_owned_list` (`current_user.lists.find`) for
  edit/update/reimport/destroy. Non-owners 404 on write attempts —
  conventional Rails, matches the rest of the app.
- `ListEntriesController` loses its standalone `require_admin!`;
  ownership-scoped lookup is the gate.

### Library import and ingest become Setup/Tools surfaces

The two predicates that *could* have stayed admin-only — library
import and ingest — also pass for any signed-in user, and the actions
move to dedicated `/setup` and `/tools` pages linked from the user
menu. Both are rare-use surfaces; out of the way but findable. The
library index's inline import button goes away; the empty-state
points at `/setup` instead. The primary nav loses its "Ingest" link.

## Consequences

- Sheila's friction case is gone. She can enrich, edit, delete books,
  and create/share lists.
- Lists carry the ownership semantics the conversation revealed they
  always wanted. "My lists" vs "things shared with me" is now a real
  distinction in the model.
- `User.role` is preserved in the schema even though `admin?` no
  longer gates anything. Reasoning: the migration cost is free and
  it leaves a knob for a future install in a less-trusted context
  (public-facing fork, friends-of-friends Tsundoku) without a
  schema change. The "Admin" badge on the user-menu chrome stays as
  a visual marker.
- `LibraryController#import` is now reachable by any signed-in user.
  The existing concurrency guard (`Task.active.where(kind:
  "calibre_import").exists?`) prevents double-triggers; the
  operation is idempotent so repeated triggers are cheap. The Setup
  and Tools pages are the discoverability layer, not an
  authorization layer.
- Ingest is the same story — eventual cron job, manual trigger
  available via Tools, no gate.
- Tests pin the passive predicates ("any signed-in user can do
  these"), the ownership semantics on `can_edit_list?`, and the
  ListsController write-authority boundary (non-owner gets 404 on
  edit/update/destroy of any list, owner or shared).

## Alternatives considered (not chosen)

- **Keep `admin?` gates, add "editor" role between reader and admin.**
  Would technically solve Sheila's case but the role distinction
  doesn't carry weight in a homelab — every household member ends up
  in the same group anyway. We'd be modeling complexity that doesn't
  exist.
- **Drop the `role` column entirely.** Free-er, simpler, but loses
  the future-tightening knob. Kept the column for the same reason
  we kept the named predicates: cheap to keep, costly to re-add.
- **Pundit or CanCan.** Would centralize the rules but adds a
  framework, a vocabulary, and an indirection layer for a problem
  that's currently five method bodies. Re-evaluate if rules become
  substantially more complex (per `architecture-principles.md §3`).
- **Per-list visibility flags (public / household / private).**
  Considered but the binary "shared / not shared" covers every case
  this household actually has. Adding more levels later is a column
  change, not a redesign.
