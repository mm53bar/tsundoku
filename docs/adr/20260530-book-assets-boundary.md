# 20260530 — `BookAssets` PORO owns book file/path concerns

## Context

A book's on-disk artifacts (EPUB, KEPUB, cover image, enriched cover)
live under two roots: the user-mounted library directory
(`Rails.configuration.x.library_path`) and Rails' own
`storage/`. The path-handling rules that govern those roots are
security-sensitive — a malformed or attacker-controlled `path` or
`cover_path` column shouldn't be able to read or delete files outside
those roots.

By 2026-05-30 the rules had spread across six files:

- `Book` — `epub_full_path`, `kepub_path`, `cover_full_path`,
  `cover_available?`, `epub_downloadable?`, `kepub_available?`,
  `delete_files_from_disk!`
- `BooksController` — `safe_cover_path`, `safe_epub_path`,
  `safe_path_under`, `cover_mime_type` (path traversal check + MIME
  detection)
- `Kobo::CoversController` — its own private `cover_mime_type`, plus
  direct `book.cover_full_path` calls *without* traversal checks
- `Kobo::DownloadsController` — direct `book.kepub_path` and
  `book.epub_full_path` calls, also without traversal checks
- `ConvertToKepubJob` — `File.dirname(book.kepub_path)` and friends
  for write paths
- view templates — `book.cover_available?` for whether to render an
  `<img>`

The Kobo controllers and the KEPUB job didn't go through the
`safe_path_under` helper at all. And `safe_path_under` itself used
literal `String#start_with?(library_root)` which would have admitted:

- `"/library/../etc/passwd"` (literal prefix match; the string starts
  with `/library` even though the resolved path escapes)
- `"/library_evil/..."` (sibling-prefix; `/library` is a prefix of
  `/library_evil`)

These weren't exploitable in practice — the `path` and `cover_path`
columns come from `IngestFileJob` scanning the library tree, not from
user input — but the rule was conceptually broken and split across
layers that shouldn't be coordinating on it.

## Decision

Extract `BookAssets` as a PORO that wraps a `Book` and owns:

- safe path resolution under approved roots (library, storage)
- EPUB / KEPUB / cover lookup
- availability checks (`epub_downloadable?`, `kepub_available?`,
  `cover_available?`)
- cover MIME type
- file deletion on book destroy, including empty-directory cleanup

Path safety lives in a single `under_root(root, relative)` method:

```ruby
base      = Pathname.new(root).expand_path
candidate = base.join(relative).expand_path
return nil unless candidate.to_s.start_with?(base.to_s + File::SEPARATOR)
candidate.to_s
```

`Pathname.expand_path` collapses `..`, so `/library/../etc` resolves to
`/etc` and fails the prefix check. The `+ File::SEPARATOR` matters:
without it, `/library_evil` (sibling) would match `/library` as a
prefix.

`Book` exposes `book.assets`. All callers — controllers, jobs, views
— go through `book.assets.epub_full_path` (etc.) and never compute
paths inline. The old methods on `Book`, the `safe_*` helpers in
`BooksController`, and the duplicate `cover_mime_type` in
`Kobo::CoversController` are all removed.

`BookAssets` lives at `app/models/book_assets.rb` rather than
`app/services/`. It's a domain concept tied to a model, not a verb
class — see `docs/architecture-principles.md` for the noun-vs-verb
preference.

## Consequences

- One source of truth for path safety. A future security review
  reads `BookAssets#under_root` and is done.
- Brakeman ignores around `send_file` / `FileAccess` / `Execute`
  warnings now all point at `BookAssets` as the centralized check.
  See `config/brakeman.ignore` notes.
- `book.assets.kepub_path` (etc.) is the canonical API. No callers
  reach for paths directly; tests assert that the methods on `Book`
  for these are gone.
- The previous path-safety check accepted attacks that
  `BookAssets#under_root` refuses. Behavior change is a tightening,
  not a loosening — but it means a malformed column that used to
  resolve to a (rejected by File.exist?) path now returns nil
  earlier. Tests in `test/models/book_assets_test.rb` pin every
  refusal case explicitly.
- **`BookAssets` is a focused noun, not a junk drawer.** It owns
  *what files exist, where they live, whether their paths are safe,
  how they get cleaned up*. It does not own: KEPUB conversion logic
  (that's `ConvertToKepubJob`), remote downloads (BooksController's
  enrichment fetch, which has its own constraints), Kobo sync payload
  decisions (`Kobo::SyncController`), or anything device-protocol-
  specific. If a change pushes beyond file/path ownership, the next
  step is identifying the real concept that should own it, not
  extending `BookAssets`.

## Alternatives considered (not chosen)

- **Keep methods on `Book`, just centralize the safety helper** —
  would have worked but left every caller responsible for choosing
  between safe and unsafe variants. The Kobo controllers' habit of
  calling `book.epub_full_path` directly is exactly the failure mode
  we wanted to remove.
- **A `BookFileService` or `BookAssetService` class under
  `app/services/`** — the verb-flavored name discourages future
  contributors from thinking of it as a domain concept. We picked the
  noun and put it in `app/models/` to keep the framing clear.
