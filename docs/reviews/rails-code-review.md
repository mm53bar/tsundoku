# Tsundoku Rails-Oriented Code Review

Last updated: 2026-05-30

## Purpose

This document is a concise summary of the Rails-oriented code review for this codebase.

It is no longer the primary home for architectural guidance. Use these docs first:

- `docs/architecture-principles.md` — current architectural rules and boundaries
- `CLAUDE.md` — short agent-facing implementation rules

Use this review as a snapshot of the main findings and priorities.

---

## Executive summary

Overall, this codebase is **mostly Rails-y and structurally healthy**.

What is working well:

- conventional Rails structure
- sensible Active Record modeling
- good use of join models
- pragmatic Hotwire/Turbo usage
- clear comments around tricky domain and integration behavior
- a coherent domain around books, shelves, readings, lists, and Kobo sync

Main risks identified in the review:

1. controllers accumulating domain/process logic
2. authorization rules becoming scattered or overly ad hoc
3. filesystem and integration rules spreading across too many layers
4. test coverage lagging behind custom behavior
5. support abstractions drifting into junk drawers if their boundaries are not kept clear

---

## Current architectural direction

The preferred direction for this app is:

- prefer Rails conventions over architecture-heavy patterns
- prefer rich domain models and well-named POROs over generic service objects
- prefer simple authorization using `User` capability predicates plus ownership-scoped lookups
- extract nouns, not verbs
- keep controllers focused on HTTP concerns
- protect subtle invariants with tests

For the fuller rationale, examples, and boundaries, see:

- `docs/architecture-principles.md`
- `CLAUDE.md`

---

## Key findings from the review

### 1. Controller boundaries matter

The biggest structural concern was controller-owned business/process logic, especially in flows like:

- book editing and enrichment
- list import/reimport
- Kobo payload construction

The recommendation was **not** to introduce a generic service layer, but to look for real domain concepts that deserve a home.

### 2. Authorization should stay simple

The review recommended:

- ownership-scoped lookups where natural
- readable `User` predicates for meaningful action checks
- no policy gem unless complexity clearly demands it later

The goal is centralized intent without adding framework-heavy indirection.

### 3. File/path logic needed one home

A major concern was that file/path behavior had been spread across models, controllers, jobs, and Kobo endpoints.

That led to the recommendation to extract a real noun-based PORO for book-owned files on disk.

### 4. Tests were a major gap

The review identified test coverage as one of the biggest practical risks, especially around:

- auth/user provisioning
- path safety
- Kobo sync/tombstones
- search behavior
- task lifecycle
- KEPUB selection/fallback

---

## Review of newer features

### KEPUB conversion

Assessment:

- useful and pragmatic
- background job is the right shape
- fallback to EPUB is good
- increases the importance of keeping file/path concerns centralized and well-bounded

### Navbar search

Assessment:

- fairly Rails-y and idiomatic
- Stimulus + Turbo Frame is a good fit
- simple controller shape is good
- should stay small unless search grows into a larger domain concern

---

## What changed after the review

Several recommendations from the review have already been applied:

- `BookAssets` was extracted as a focused PORO for book file/path concerns
- file/path callers were migrated to `book.assets`
- `User` capability predicates were introduced for action permissions
- tests were added for several high-risk invariants

Those changes are consistent with the intended direction.

---

## Ongoing watchpoints

Current standing rules and boundaries live in `docs/architecture-principles.md` and `CLAUDE.md`.

---

## Bottom line

This is a good Rails codebase with solid domain instincts.

The goal is not to replace it with a grand architecture. The goal is to keep it Rails-y as it grows by:

- strengthening domain boundaries
- keeping abstractions honest
- centralizing risky invariants in the right places
- using simple authorization patterns
- adding tests where behavior is subtle or security-sensitive
