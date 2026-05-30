# Tsundoku — agent guidance

Prefer Rails conventions over architecture-heavy patterns. For rationale and examples, read `docs/architecture-principles.md` and `docs/reviews/rails-code-review.md`.

## Standing rules

- Do not introduce Pundit, CanCan, or a policy framework unless explicitly requested.
- Do not introduce generic service-layer indirection. Prefer rich domain models and well-named POROs.
- Extract nouns, not verbs. Prefer names like `BookAssets` or `MetadataProposal` over `SomethingService`.
- Keep controllers focused on HTTP concerns: load records, check permissions, choose responses.
- Authorization assumes a trusted household: most authenticated users are permitted broadly. Do not introduce an admin-role assumption unless explicitly requested — ownership and explicit sharing are the primary boundaries.
- For shared resources, keep visibility and write authority separate. Use visibility scopes for reads (`List.visible_to(user)`) and ownership-scoped lookups for writes (`current_user.lists.find(...)`). The List model is the reference pattern.
- `User` capability predicates (`can_edit_book?`, `can_edit_list?`) are extension points for future tightening — keep them action-oriented, not UI-oriented. Today most return `true`; the names exist so a future, less-trusted deployment has one place to refine.
- All book file/path access must go through `book.assets`. Do not compute book file paths inline in controllers, jobs, or views.
- `BookAssets` owns safe path resolution, file availability, cover MIME type, and cleanup for book-owned files on disk. If a change goes beyond that boundary, stop and identify the real concept before extending it.
- Add or update tests when touching risky areas, especially:
  - `BookAssets`
  - user provisioning and auth predicates
  - Kobo sync and tombstone behavior
  - file serving and KEPUB selection
  - search behavior
- If you introduce or materially change a significant architectural decision (a security boundary, a sync invariant, an authorization rule, an integration shape), record it as an ADR in `docs/adr/`. Match the format and tone of the existing five ADRs. Coding preferences do not need ADRs — those go here or in `docs/architecture-principles.md`.

