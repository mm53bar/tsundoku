# 20260803 — Integration tests over system tests

## Context

A fresh `rails new` ships a browser system-test harness: `capybara` +
`selenium-webdriver`, a `test/system/` directory, and a `system-test` CI job.
Tsundoku inherited all of it but never used it — `test/system/` held only
`.keep`, there was no `ApplicationSystemTestCase`, and the required `system-test`
CI check ran `bin/rails test:system` against zero tests. It was a green
checkmark asserting nothing: worse than no gate, because it reads as coverage.

Meanwhile the app's real UI coverage already lives where it belongs — in
`ActionDispatch::IntegrationTest`s that drive the app over Rack and assert
against the rendered HTML with `assert_select` (see the per-controller tests).
That's fast and deterministic. Browser system tests, by contrast, are the
flaky, slow layer (timing races, obsolete nodes, driver management), and the
industry has been moving off them for behavior coverage — see DHH,
["System tests have failed"](https://world.hey.com/dhh/system-tests-have-failed-d90af718).

## Decision

Test UI **behavior** with Rack integration tests; reserve browser system tests
for genuinely-JS interactions only.

- **Behavior → `test/integration/`.** Auth/authorization, CRUD, redirects,
  rendered-HTML assertions — driven over Rack with `assert_select` and the
  request helpers, no browser. Authentication uses `headers_for(user)` (a
  shared helper in `test_helper.rb`) to inject the forward-auth `Remote-User`
  header the proxy would supply.
- **Genuinely-JS surfaces → manual, for now.** The Turbo/Stimulus pieces (the
  star-shelf toggle, hamburger nav, the Turbo-Stream task tray) are few and are
  verified by hand. `test/system/` is kept (empty) so a focused browser test
  can be added later if a JS interaction becomes load-bearing enough to warrant
  one.
- **Drop the unused harness.** Remove `capybara` + `selenium-webdriver`, the
  `system-test` CI job, and `system-test` from the required status checks (a
  required check that runs no tests must not gate merges).

## Consequences

- No more phantom "system tests passed" signal. The gates that remain
  (`scan_ruby`, `scan_js`, `lint`, `test`) all assert something real.
- New UI coverage has one obvious home and a one-line sign-in idiom. A starter
  set lives in `test/integration/smoke_test.rb`.
- We give up in-browser assertions (visual layout, JS execution). Accepted: the
  JS surface is small and manual-tested; if that changes, add a *focused*
  system test for the interaction itself, not the behavior behind it — and
  re-add the driver gem at that point.

## Alternatives considered

- **Keep the scaffolding "just in case."** Rejected: it wasn't inert — it was a
  required check masquerading as coverage, plus two unused gems.
- **Adopt Capybara-enhanced integration tests** (Capybara's `assert_selector`
  over Rack, as in a sibling project's ADR). Deferred: `assert_select` already
  covers our needs, and dropping `capybara` entirely is fewer dependencies. The
  option remains open if richer HTML assertions are wanted later.
