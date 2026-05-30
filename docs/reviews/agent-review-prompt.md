Read `docs/reviews/rails-code-review.md` before making architectural changes.

Project guidance from that review:

- Prefer Rails conventions and rich domain models over service objects.
- Extract nouns into POROs when needed; avoid verb-named orchestration classes unless there is a very strong reason.
- Prefer simple authorization:
  - ownership scoping for record loading
  - `User` permission predicates for action checks
  - no policy gem unless the rules become substantially more complex
- Keep controllers focused on HTTP concerns; move durable business rules into models or domain POROs.
- Be especially cautious around:
  - `BooksController` orchestration
  - file/path safety for covers, EPUBs, and KEPUBs
  - `Task` growth into a god object
  - Kobo sync invariants and tombstone behavior

When changing code, align with the review unless there is a clear reason not to. If you choose a different direction, call out the tradeoff explicitly.
