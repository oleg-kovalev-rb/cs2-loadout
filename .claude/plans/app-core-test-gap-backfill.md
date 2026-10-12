---
status: implemented
app: core
goal: Backfill app_core's request- and component-spec coverage for already-shipped, currently-untested behavior (Steam OpenID login flow, a current_user edge case, Dashboard.jsx's composition logic, filter-facet DOM wiring, pagination boundaries, and two chart-adjacent branches), adopting VCR for app_core along the way per the already-accepted but never-executed rspec-testing-strategy ADR
created: 2026-10-11
---

# Development Plan

## Goal

Add missing request- and component-level test coverage in `app_core` for
behavior that already shipped (across `dashboard-api-redesign`,
`dashboard-progressive-hydration`, `add-24h-item-history-range`,
`dashboard-filter-facets-present-only`, `dashboard-single-page-polish`,
and the Steam OpenID login flow that predates all of them) but was never
directly tested. This is a test-only change — no production behavior is
intended to change. If a new test surfaces a genuine bug in existing
code, fix only that specific bug as a flagged deviation, not as a
broader refactor.

Backend is the priority (the larger, fully-untested surface); frontend
gaps are addressed second. As part of making `SessionsController#callback`
testable at the request level per the existing `rspec-conventions.md`
MUST rule, this plan is also the first to actually execute
`.claude/adr/fetcher/rspec-testing-strategy.md`'s long-accepted-but-never-
implemented decision to adopt VCR — scoped to `app_core` only;
`app_fetcher`'s own separately-logged, still-pending VCR migration
(`inventories_spec.rb`/`price_histories_spec.rb`, see `fix_me.md`) is not
touched by this plan.

## Expected Behavior

This plan adds tests for behavior that already exists. Listed below is
the behavior each new/changed spec must pin down — not new behavior to
build.

### Backend — Steam OpenID login flow (currently zero coverage)

**`SessionsController`**
- `GET /session` (`#create`) redirects (302) to the URL built by
  `Steam::Authenticator.auth_url(callback_session_url, root_url)` — no
  HTTP call is made by this action itself.
- `GET /session/callback` (`#callback`) happy path: a user is
  persisted/updated, `session[:user_id]` is set to that user's id, and
  the response redirects to `root_path` with a welcome notice containing
  the user's nickname (or "Player" if blank).
- `#callback` with `Steam::AuthError` raised (genuinely, via a real
  invalid-validation round trip to Steam — see Implementation Approach):
  redirects to `root_path` with alert "Login failed. Please try again.";
  `session[:user_id]` is never set; the failure is logged via
  `Rails.logger.warn`.
- `#callback` with `ActiveRecord::RecordInvalid` raised (simulated, since
  no real Steam response can deterministically produce this): redirects
  to `root_path` with alert "Internal server error during login.";
  `session[:user_id]` is never set.
- `DELETE /session` (`#destroy`) clears the session and redirects to
  `root_path` — already has one example in `dashboards_spec.rb`,
  relocated here so the controller's full surface lives in one file.

**`Steam::Authenticator`** (unit, WebMock against the real host)
- `.auth_url(return_to, realm)` builds the correct `openid.*` query
  string — pure, no HTTP.
- `.validate!`: empty `auth_params` → `AuthError "Missing Steam payload"`
  (no HTTP call); a real Steam `is_valid:false` response → `AuthError
  "Steam validation failed"`; a non-2xx HTTP response → the same error;
  an `is_valid:true` response whose `openid.claimed_id` doesn't match
  `openid/id/(\d+)` → `AuthError "Invalid SteamID format"`; a matching
  `claimed_id` → returns the captured steam id; `Net::OpenTimeout` /
  `Net::ReadTimeout` / `OpenSSL::SSL::SSLError` / `EOFError` raised by
  the transport → rescued and re-raised as `AuthError "Network error
  during validation: <message>"`.

**`Steam::ProfileFetcher`** (unit, WebMock against the real host)
- `STEAM_WEB_API_KEY` blank/unset → `nil`, and no HTTP request is made at
  all.
- A non-2xx response → `nil`.
- A 2xx response whose JSON has no `response.players[0]` → `nil`.
- A 2xx response with a player → `{nickname: personaname, avatar_url:
  avatarfull}`.
- A malformed (non-JSON) body → `nil` (`JSON::ParserError` rescued).
- A transport timeout (`Net::OpenTimeout`/`Net::ReadTimeout`) → `nil`.

**`Steam::LoginUser`** (unit — first example of the `app/actions/`
layer in this repo; WebMock against both real hosts, `Authenticator`/
`ProfileFetcher` exercised for real, never stubbed as classes)
- A new `steam_id` → creates a `User` with the fetched nickname/avatar.
- An existing `steam_id` → updates its nickname/avatar.
- `ProfileFetcher` returns `nil` (e.g. blank API key) → the user's
  existing/default nickname and avatar are left untouched, not
  overwritten with `nil`.
- `Authenticator.validate!` raises `AuthError` → propagates uncaught (not
  swallowed by `LoginUser`).
- Invalid user attributes → `user.save!`'s `ActiveRecord::RecordInvalid`
  propagates uncaught.

### Backend — `ApplicationController#current_user` edge case

- A session whose `user_id` refers to a deleted/non-existent `User` row
  renders the same signed-out root page as a fully anonymous request —
  not an error. (Already named as expected behavior in
  `dashboard-single-page-polish.md`'s Edge Cases; never tested.)

### Frontend — `Dashboard.jsx` (currently zero coverage)

- While `useDashboardData`'s `status` is `'loading'`, renders
  `DashboardSkeleton` only.
- On `status === 'error'`, renders the error message including
  `error.message`.
- Once the skeleton resolves, `useItemPrices`/`useItemTrend` results are
  merged onto each item by `marketHashName` (`currentPriceCents`,
  `change24hPercent`, `trendPoints`, etc. appear on the rendered rows).
- Clicking an item, then having its price/trend data arrive afterward,
  keeps the hero tile showing that item (not the stale pre-enrichment
  object) — the `selectedItem` re-resolution against the enriched `items`
  list on every render.
- Changing the range control dispatches `PORTFOLIO_RANGE_CHANGED` while
  in portfolio mode and `ITEM_RANGE_CHANGED` while in item mode, each
  feeding the correct hook (`usePortfolioHistory`/`useItemHistory`) with
  its own independent range value.

### Frontend — `FilterDropdown`/`ItemsTile` facet wiring

- An inventory with zero StatTrak items renders no "Special" filter
  group at all (not an empty one).
- An inventory whose items only cover a subset of `CONDITIONS` renders
  only those condition chips, in canonical wear order — no chip for an
  absent condition.

### Frontend — `Pagination`

- With more than one page's worth of items (`PAGE_SIZE = 8`): the "Prev"
  button is disabled on page 1 and enabled afterward; "Next" is disabled
  on the last page and enabled before it; clicking "Next"/"Prev"
  navigates and the rendered row set and "`x`–`y` of `n`" range text
  update accordingly.

### Frontend — `ChartTooltip` / `chartConfig`

- `ChartTooltip({active: false, ...})` and `ChartTooltip({active: true,
  payload: []})` both render nothing.
- `ChartTooltip({active: true, payload: [...]})` renders the formatted
  price and the formatted timestamp from the point's `at` field.
- `chartConfig.generateAxisLabels('all')` produces its documented
  special-cased output (distinct from a fixed-duration range); `RANGE_MS`
  has no `'all'` entry (consistent with `HeroChart`'s `dataMin`/`dataMax`
  fallback already relying on that absence).

### Must remain unchanged

- No production code changes. `authenticator.rb`'s/`application_
  controller.rb`'s/`sessions_controller.rb`'s known Sorbet-sigil
  deviations (logged in `fix_me.md`) are left exactly as they are — this
  plan doesn't edit those files, only adds specs that exercise them.

## Scope

### In Scope

- `app_core/Gemfile`: add `vcr` to the `:test` group (first real use in
  either app); `spec/support/vcr.rb` config.
- New unit specs: `Steam::Authenticator`, `Steam::ProfileFetcher`,
  `Steam::LoginUser`.
- New request spec: `spec/requests/sessions_spec.rb` (all of
  `SessionsController`'s actions).
- One real, recorded VCR cassette for the one scenario actually
  reproducible without live Steam credentials — see Implementation
  Approach.
- `dashboards_spec.rb`: add the deleted-user `current_user` edge case;
  remove the now-duplicate `DELETE /session` example (moved to
  `sessions_spec.rb`).
- New `Dashboard.test.jsx`, `ChartTooltip.test.jsx`, `chartConfig.test.js`.
- Extend `ItemsTile.test.jsx` (facet-hiding + pagination-boundary cases).
- Optionally extend `PortfolioTile.test.jsx` with one `range: 'all'` case.

### Out of Scope

- Any production-code change, except a minimal, explicitly-flagged fix if
  a new test uncovers a genuine bug (none expected based on research).
- Fixing the pre-existing Sorbet-sigil deviations on `authenticator.rb`,
  `application_controller.rb`, `sessions_controller.rb` (`fix_me.md`) —
  not triggered, since this plan doesn't edit those files.
- `app_fetcher`'s own pending VCR migration
  (`inventories_spec.rb`/`price_histories_spec.rb`) — separate, already
  logged, not this plan's job.
- `app_core/spec/fixtures/users.yml` migration — logged deviation, not
  touched; all new scenarios use the existing `:user` factory.
- A real system spec (`type: :system`) for the full browser-driven Steam
  OpenID redirect dance — `rspec-conventions.md` already earmarks that as
  a future system spec's job, not this request spec's; none written yet,
  none added here.
- New dedicated test files for `SortDropdown`, `ItemsToolbar`,
  `RangeToggle`, `Sparkline`, `DashboardSkeleton` — stays consistent with
  `react-dashboard.md`'s documented "presentational leaf" convention.
- Any new dashboard feature or UI behavior.

## Implementation Approach

### VCR adoption (app_core)

Add `gem "vcr"` to `app_core/Gemfile`'s `:test` group, next to the
existing `webmock`/`factory_bot_rails`. New `app_core/spec/support/vcr.rb`,
following `.claude/adr/fetcher/rspec-testing-strategy.md`'s already-decided
shape exactly (this plan executes that decision, not a new one):

```ruby
VCR.configure do |c|
  c.cassette_library_dir = "spec/cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.allow_http_connections_when_no_cassette = false
  c.default_cassette_options = { record: ENV["CI"] ? :none : :once }
  c.filter_sensitive_data("<STEAM_WEB_API_KEY>") { ENV["STEAM_WEB_API_KEY"] }
end
```

`rails_helper.rb` already `require "webmock/rspec"`; add
`require "vcr"` and require the new support file (or rely on the
commented-out `Rails.root.glob("spec/support/**/*.rb")` auto-require —
app_core's `rails_helper.rb` currently has that line commented out, so
either uncomment it or add an explicit `require_relative
"support/vcr"`; confirm which during implementation to keep the diff
minimal).

**The practical recording problem.** A genuine VCR cassette requires one
real round trip to the real host. `Steam::Authenticator.validate!`'s
*success* path (`is_valid:true`) can only be produced by Steam for
`openid.*` params tied to an actual, just-completed Steam login — this
environment has no live Steam account to drive that with (consistent
with every prior plan's own "no real Steam login available in this
environment" note). `Steam::ProfileFetcher`'s success response likewise
needs a real `STEAM_WEB_API_KEY`, not confirmed present here.

What **is** genuinely recordable without any credentials: POSTing
synthetic `openid.*` params to Steam's real `check_authentication`
endpoint deterministically returns `is_valid:false` for anything not
tied to a live session — a real, honest network interaction requiring no
secret. This plan therefore records exactly **one** real cassette, for
`#callback`'s `AuthError`-via-invalid-validation scenario, satisfying both
the MUST rule (VCR, not hand-written WebMock, at the request level) and
the ADR's "recorded, not guessed" rationale for real.

The happy-path and `RecordInvalid` scenarios, which cannot be produced
via a real round trip in this environment, are covered at the request
level by stubbing `Steam::LoginUser.call` directly (`allow(Steam::LoginUser)
.to receive(:call)...`) — not a WebMock stub of the Steam HTTP call, so
it doesn't conflict with the MUST-use-VCR rule, and consistent with
`dashboards_spec.rb`'s existing precedent of stubbing a collaborator
method (`current_user`) directly in a request spec. `LoginUser`'s own
correctness for producing a valid `User`/raising `RecordInvalid` is
already exhaustively covered by its own new unit spec, so the request
spec isn't skipping real coverage — it's exercising the boundary
(routing/session/redirect) without re-proving business logic the unit
level already owns, per `rspec-conventions.md`'s own stated division of
responsibility. Flag this explicitly as an environment-driven compromise
in the Implementation Summary once done, the same way several already-
implemented plans in this repo flagged "manual browser verification not
performed — no live Steam login available."

If, during implementation, even the one real `AuthError` cassette turns
out to be unrecordable (e.g. no outbound network access from the
implementation environment), fall back to stubbing
`Steam::Authenticator.validate!` directly for that one scenario too, and
record this as a Deviation — don't block the whole plan on it.

### Unit specs

`spec/lib/steam/authenticator_spec.rb`, `spec/lib/steam/profile_fetcher_spec.rb`
(mirroring `lib/steam/` under `spec/lib/steam/`, matching the existing
`bridge_token_spec.rb` precedent) and the new `spec/actions/steam/login_user_spec.rb`
(first spec under `spec/actions/`) all stub the real outbound hosts via
`WebMock.stub_request`, per `rspec-conventions.md`'s unit-level rule —
never VCR, never mocking `Authenticator`/`ProfileFetcher` as classes from
`LoginUser`'s own spec.

### Request spec

`spec/requests/sessions_spec.rb`, `type: :request`. `#create` needs no
stub (pure URL construction). `#callback` has three contexts as described
above. `#destroy` is moved here from `dashboards_spec.rb`.

### `current_user` edge case

Add directly to `dashboards_spec.rb`'s existing structure: `get root_path,
params: {}, headers: {}` with `session: { user_id: <id that doesn't
exist> }` (no `current_user` stub this time — letting the real
`User.find_by(id: ...)` run), asserting the same signed-out markup as the
"when not signed in" context.

### Frontend

`Dashboard.test.jsx` follows `useDashboardData.test.js`'s pattern — stub
`global.fetch` keyed by which endpoint path is requested (skeleton vs.
`item_prices/dynamics` vs. `item_prices/trend` vs. `inventory_values` vs.
`item_prices/:name/history`), since `Dashboard.jsx` fires four hooks at
once (the fifth, `useItemHistory`, only once an item is selected).

`ItemsTile.test.jsx`'s facet and pagination cases extend the existing
real-reducer harness (`.claude/adr/core/component-tests-real-reducer.md`)
with new fixtures rather than introducing a new harness shape.

`ChartTooltip.test.jsx` renders `<ChartTooltip />` directly with plain
props — no Recharts/HeroChart mounting needed, since the component has no
dependency on being inside a chart to render.

`chartConfig.test.js` is a plain pure-function unit test, no rendering,
following `filters.test.js`'s style.

## Files To Modify

- `app_core/Gemfile` — add `vcr` to `:test` group.
- `app_core/Gemfile.lock` — updated via `bundle install`.
- `app_core/spec/rails_helper.rb` — `require "vcr"` (+ require the new
  support file, or enable the support-dir auto-require, whichever is the
  smaller diff).
- `app_core/spec/requests/dashboards_spec.rb` — remove the `DELETE
  /session` example (moved to `sessions_spec.rb`); add the deleted-user
  `current_user` edge case.
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx` — add
  the no-stattrak / limited-conditions facet cases and the >8-item
  pagination boundary case.
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` —
  add one `range: 'all'` item-mode case.

## Files To Create

- `app_core/spec/support/vcr.rb` — VCR configuration.
- `app_core/spec/cassettes/<derived-from-example-description>.yml` — one
  real recorded cassette for `#callback`'s invalid-validation scenario
  (exact filename auto-derived by `configure_rspec_metadata!`).
- `app_core/spec/lib/steam/authenticator_spec.rb`.
- `app_core/spec/lib/steam/profile_fetcher_spec.rb`.
- `app_core/spec/actions/steam/login_user_spec.rb`.
- `app_core/spec/requests/sessions_spec.rb`.
- `app_core/app/frontend/dashboard/__tests__/Dashboard.test.jsx`.
- `app_core/app/frontend/dashboard/__tests__/ChartTooltip.test.jsx`.
- `app_core/app/frontend/dashboard/__tests__/chartConfig.test.js`.

## Test Plan

**`authenticator_spec.rb`**: `.auth_url` builds the expected query
string; `.validate!` — empty params (no HTTP call, `AuthError`), real
`is_valid:false` via WebMock, non-2xx via WebMock, `is_valid:true` +
unmatchable `claimed_id` via WebMock, `is_valid:true` + matching
`claimed_id` → returns the id, each of the four rescued transport
errors → wrapped `AuthError`.

**`profile_fetcher_spec.rb`**: blank key → `nil`, no request made;
non-2xx → `nil`; valid JSON, no player → `nil`; valid player → correct
hash; malformed JSON → `nil`; timeout → `nil`.

**`login_user_spec.rb`**: new steam_id creates a user with profile data;
existing steam_id updates nickname/avatar; `nil` profile leaves existing
fields untouched; `AuthError` propagates; `RecordInvalid` propagates.

**`sessions_spec.rb`**: `#create` redirects to `Steam::Authenticator
.auth_url`'s result; `#callback` happy path (stubbed `LoginUser.call`)
sets the session and redirects with the welcome notice (nickname and
"Player"-fallback variants); `#callback` real-cassette `AuthError` path
redirects with the login-failed alert and leaves the session unset;
`#callback` stubbed `RecordInvalid` path redirects with the
internal-error alert and leaves the session unset; `#destroy` clears the
session and redirects (moved from `dashboards_spec.rb`).

**`dashboards_spec.rb`**: new example — a session with a non-existent
`user_id` renders the same signed-out markup as no session at all.

**`Dashboard.test.jsx`**: loading renders `DashboardSkeleton`; error
renders the error message; once all fetches resolve, rendered rows carry
merged price/trend data; selecting an item then having its price arrive
later updates the hero tile for that same item (not a stale copy);
changing range in portfolio vs. item mode dispatches the correct action
and feeds the correct hook.

**`ItemsTile.test.jsx`** (extended): a fixture with zero StatTrak items
renders no "Special" group; a fixture missing some `CONDITIONS` values
renders only the present ones, in canonical order; a >8-item fixture
exercises `Pagination`'s Prev/Next, disabled-at-boundary states, and the
range text across page changes.

**`ChartTooltip.test.jsx`**: `active: false` → renders nothing;
`active: true, payload: []` → renders nothing; `active: true, payload:
[{value, payload: {at}}]` → renders the formatted price and timestamp.

**`chartConfig.test.js`**: `RANGE_MS` has no `'all'` key;
`generateAxisLabels('all')` differs from a fixed-range result in the
documented way (exact assertion shape confirmed by reading the function
during implementation).

**`PortfolioTile.test.jsx`** (extended, optional but included): item
mode with `range: 'all'` renders without crashing and selects the `'all'`
toggle option as active.

## Implementation Steps

1. Add `vcr` to `app_core/Gemfile`'s `:test` group; `bundle install`; add
   `spec/support/vcr.rb`; wire it into `rails_helper.rb`.
2. `authenticator_spec.rb` — TDD each branch via WebMock, confirming each
   example fails for the right reason before the (already-existing)
   production code makes it pass.
3. `profile_fetcher_spec.rb` — same approach.
4. `login_user_spec.rb` — same approach, exercising the real
   `Authenticator`/`ProfileFetcher` via WebMock-stubbed hosts.
5. `sessions_spec.rb` — `#create` and the two stubbed `#callback`
   contexts (happy path, `RecordInvalid`) first; then attempt to record
   the real `AuthError` cassette (confirm outbound network access first;
   fall back to a direct `Authenticator` stub for this one scenario if
   recording isn't possible, per Implementation Approach); then
   `#destroy`, removing its duplicate from `dashboards_spec.rb`.
6. `dashboards_spec.rb` — add the deleted-user `current_user` edge case.
7. Run the full `app_core` RSpec suite; `bin/rubocop` on touched files.
8. `Dashboard.test.jsx` — build the multi-endpoint fetch-mock harness,
   one scenario at a time (loading → merge → selection re-resolution →
   range dispatch).
9. `ItemsTile.test.jsx` — add the facet-hiding and pagination cases.
10. `ChartTooltip.test.jsx`, `chartConfig.test.js` — new, straightforward
    direct-render/pure-function tests.
11. `PortfolioTile.test.jsx` — add the `'all'`-range case.
12. Run the full `app_core` Vitest suite.

## Verification

- `docker compose run --rm app_core bundle exec rspec` (full suite).
- `docker compose run --rm app_core bin/rubocop` (files touched by this
  plan).
- `npx vitest run` (full `app_core` frontend suite).
- Confirm `spec/cassettes/*.yml` is committed, contains no secrets
  (nothing to filter for this particular call, but confirm the
  `filter_sensitive_data` config is in place for future cassettes), and
  is actually replayed (not silently re-recording) on a second local run.
- Confirm no other file references the relocated `DELETE /session`
  example by its old location.

## Risks

- A genuine, live-recorded VCR cassette for `#callback`'s **success**
  path is not obtainable in this environment (no real Steam login, no
  confirmed `STEAM_WEB_API_KEY`) — accepted and explicitly compromised on
  (see Implementation Approach); flag in the Implementation Summary
  rather than silently presenting the stubbed happy path as equivalent to
  a real one.
- Even the one real `AuthError` cassette requires outbound network access
  to `steamcommunity.com` from wherever this plan is implemented — if
  unavailable, falls back to a direct `Authenticator` stub for that
  scenario (see Implementation Approach's explicit fallback).
- `Dashboard.test.jsx`'s mock must correctly route four concurrent
  endpoint fetches by URL; getting this wrong produces a flaky or
  falsely-passing test rather than a loud failure — worth deliberately
  checking each mocked response is hit by asserting call counts/URLs, not
  just final rendered output.
- Moving the `DELETE /session` example out of `dashboards_spec.rb` is a
  test reorganization — low risk, but confirm nothing else names that
  example/location.
- A VCR cassette recorded today can drift from Steam's real future
  response shape — an accepted, already-named risk in the governing ADR,
  not new to this plan.

## Assumptions

- The implementation environment has outbound network access to
  `steamcommunity.com`'s public, unauthenticated `check_authentication`
  endpoint, sufficient to record one real cassette; unconfirmed until
  attempted (see Risks/fallback).
- No real `STEAM_WEB_API_KEY` is available in the implementation/test
  environment; `ProfileFetcher`'s success shape is therefore only ever
  covered by a WebMock-fabricated fixture, never a live recording.
- The existing `:user` FactoryBot factory needs no new trait for any
  scenario in this plan.
- `rails_helper.rb`'s commented-out `Rails.root.glob("spec/support/**/*.rb")`
  auto-require can either be enabled or bypassed with an explicit
  `require_relative` for `spec/support/vcr.rb` — whichever keeps the diff
  smaller is decided during implementation, not pre-committed here.

## Applicable Styleguides

- **`.claude/styleguides/rspec-conventions.md`** — governs every new
  backend spec: unit-vs-request-vs-system level placement (including the
  first `spec/actions/` example, `login_user_spec.rb`), the WebMock
  (unit)-vs-VCR (request) split that directly shapes `authenticator_spec.rb`/
  `profile_fetcher_spec.rb`/`login_user_spec.rb` vs. `sessions_spec.rb`,
  `FactoryBot` usage, `aggregate_failures`, and the `let`/`before`/named-
  `subject` example structure once a spec has persisted data or a stub.
- **`.claude/adr/fetcher/rspec-testing-strategy.md`** — governs this
  plan's VCR adoption exactly: cassette directory (`spec/cassettes/`),
  `:once`/`:none` record-mode split between local and CI,
  `allow_http_connections_when_no_cassette = false`, and
  `filter_sensitive_data` from day one — already explicitly scoped to
  "both apps" despite living under the `fetcher/` ADR folder (a
  pre-existing organizational note, not acted on by this plan).
- **`.claude/styleguides/core/react-dashboard.md`** (amended during this
  check) — governs every frontend file this plan touches:
  - its new "Multi-source orchestration tests" entry (Testing → Test
    styles) directly shapes `Dashboard.test.jsx`'s URL-routed `fetch`
    mock, resolving the gap this check originally flagged;
  - its extended `chartConfig.js` paragraph (Derived Data) confirms
    `generateAxisLabels`'s `'all'`-branch is held to the same
    "branches on data → gets a test" line as any `utils/` function,
    grounding `chartConfig.test.js`;
  - its "What gets a dedicated test file" dividing line (unchanged by
    this amendment) confirms `ChartTooltip.test.jsx` is warranted —
    `ChartTooltip` "contains conditional/derivation logic worth
    isolating in its own right" (the `!active || !payload?.length`
    branch plus `fmtDateTime`/`fmtUSD` formatting) even though it had no
    file before this plan;
  - its refreshed "Interaction With Other Layers" diagram documents the
    real gating differences between `useItemPrices`/`useItemTrend`
    (skeleton-gated), `usePortfolioHistory` (fires on mount), and
    `useItemHistory` (selection-gated) that `Dashboard.test.jsx` must
    account for.
- **`.claude/adr/core/component-tests-real-reducer.md`** — governs the
  `ItemsTile.test.jsx` extensions (facet-hiding, pagination boundaries):
  both reuse the existing real-reducer harness as-is, no new pattern
  needed.
- **`.claude/adr/core/sparkline-vs-recharts.md`** — confirms this plan
  correctly does not add a dedicated `Sparkline.jsx` test; its crash-guard
  branch is already incidentally exercised via `ItemRow.test.jsx` and the
  component has no remaining live caller passing `showArea: true`.
- **`.claude/styleguides/git-commits.md`** — this plan's eventual
  implementation commit uses the `[Core]` scope tag; per "Task-Scoped
  Styleguides, ADRs, and Plans," the `react-dashboard.md` amendment
  produced only to unblock this plan bundles into that same `[Core]`
  commit, not a separate `AI WorkFlow` commit.

`.claude/styleguides/ruby-sorbet.md` and
`.claude/styleguides/rails-layering.md`/`core/architecture-layers.md`
were checked and confirmed not applicable — this plan adds no new
production Ruby file (spec files are explicitly sigil-exempt per
`rspec-conventions.md`) and makes no architecture/layering change.

## Completion Criteria

- [x] Desired behavior made explicit for every new spec (backend
  Steam-login surface, `current_user` edge case, frontend
  `Dashboard.jsx`/facet-wiring/pagination/chart gaps).
- [x] Scope explicit, including the deliberate VCR-recording compromise.
- [x] Affected/new files identified.
- [x] Test strategy defined per file.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (`styleguides-check`) — see
  Applicable Styleguides above.
- [x] Implemented — see Implementation Summary below.

# Implementation Summary

## Implemented

**VCR adoption (`app_core`, first real use in either app)**
- `Gemfile`: added `gem "vcr"` to the `:test` group.
- `spec/support/vcr.rb` (new): `VCR.configure` exactly per
  `rspec-testing-strategy.md`'s already-decided shape — cassette dir
  `spec/cassettes`, hooked into WebMock, `configure_rspec_metadata!`,
  `allow_http_connections_when_no_cassette = false`, `record: :once`
  locally / `:none` in CI, `filter_sensitive_data` for
  `STEAM_WEB_API_KEY`.
- `rails_helper.rb`: added `require "vcr"`; enabled the previously
  commented-out `Rails.root.glob("spec/support/**/*.rb")` auto-require
  (matching `app_fetcher`'s already-active equivalent) instead of adding
  a one-off `require_relative`, per the plan's own open Assumption,
  resolved in favor of the smaller/more-consistent diff.

**Steam OpenID login flow — previously zero coverage**
- `spec/lib/steam/authenticator_spec.rb` (new): `.auth_url` query-string
  construction; `.validate!`'s every branch (missing payload, real
  `is_valid:false`, non-2xx, unmatchable `claimed_id`, matching
  `claimed_id`, and all four rescued transport errors) via WebMock
  against the real host.
- `spec/lib/steam/profile_fetcher_spec.rb` (new): blank key (no HTTP
  call), non-2xx, no-player, valid player, malformed JSON, and timeout
  branches, all via WebMock.
- `spec/actions/steam/login_user_spec.rb` (new, first spec under
  `spec/actions/`): new-user creation, existing-user update, `nil`
  profile leaving existing fields untouched, `AuthError` propagation,
  `ActiveRecord::RecordInvalid` propagation — `Authenticator`/
  `ProfileFetcher` exercised for real against WebMock-stubbed hosts, per
  "never stub the internal client class."
- `spec/requests/sessions_spec.rb` (new): `#create`'s redirect to
  `Steam::Authenticator.auth_url`; `#callback` happy path (nickname and
  "Player"-fallback variants) and the `RecordInvalid` rescue path, both
  via a direct `Steam::LoginUser.call` stub; `#callback`'s `AuthError`
  rescue path via one **genuinely recorded** VCR cassette — a real POST
  to `steamcommunity.com/openid/login` with synthetic `openid.*` params,
  which Steam's real `check_authentication` endpoint deterministically
  rejects (`is_valid:false`) without needing any credential; `#destroy`,
  relocated from `dashboards_spec.rb`.

**`current_user` deleted-user edge case**
- `dashboards_spec.rb`: new example — signs a user in for real (via a
  stubbed `Steam::LoginUser.call` through the actual `#callback` action,
  establishing a real session cookie), deletes that user, then confirms
  `GET /` still renders the signed-out empty state via the real
  `User.find_by(id: session[:user_id])` → `nil` path (not stubbed).
- Removed the now-duplicate `DELETE /session` example (moved to
  `sessions_spec.rb`).

**Frontend**
- `__tests__/Dashboard.test.jsx` (new): loading → `DashboardSkeleton`;
  inventory failure → error message; dynamics+trend merge onto the
  rendered row (price, delta badge, sparkline path); a selected item's
  hero tile updates once its price arrives *after* selection (the
  `items.find(...)` re-resolution behavior); range changes dispatch
  `PORTFOLIO_RANGE_CHANGED`/`ITEM_RANGE_CHANGED` and refetch the correct
  endpoint depending on mode. Uses the new URL-routed `fetch` mock
  pattern from the amended `react-dashboard.md`.
- `__tests__/ItemsTile.test.jsx` (extended): a StatTrak-free fixture
  hides the "Special" group entirely; a fixture with a limited condition
  set renders only those chips, in canonical wear order; a 9-item
  fixture exercises `Pagination`'s Prev/Next and disabled-at-boundary
  states across a real page change.
- `__tests__/ChartTooltip.test.jsx` (new): inactive and
  empty-payload render nothing; an active payload renders the formatted
  price and timestamp.
- `__tests__/chartConfig.test.js` (new): `RANGE_MS` has no `'all'` entry;
  `generateAxisLabels` computes relative-offset labels for a fixed range
  vs. its blank-except-"today" special case for `'all'`.
- `__tests__/PortfolioTile.test.jsx` (extended): item mode with
  `range: 'all'` renders without crashing and marks the `all` toggle
  active.

## Tests

- `app_core` RSpec: 37 examples (9 pre-existing + 28 new: 10
  `authenticator_spec.rb`, 7 `profile_fetcher_spec.rb`, 5
  `login_user_spec.rb`, 6 `sessions_spec.rb`, 1 new `dashboards_spec.rb`
  example net of the 1 relocated).
- `app_core` Vitest: 83 tests across 14 files (67 pre-existing + 16 new:
  6 `Dashboard.test.jsx`, 3 `ChartTooltip.test.jsx`, 3
  `chartConfig.test.js`, 3 new `ItemsTile.test.jsx` cases, 1 new
  `PortfolioTile.test.jsx` case).

Commands actually executed (via `docker compose run --rm --no-deps
app_core ...`, `--no-deps` to avoid an unrelated host-port conflict on
this worktree's `redis` service from an already-running sibling
worktree — `app_core`'s test suite doesn't use Redis at all, confirmed
via `grep` across `config/environments/test.rb` and the Gemfile):

```
bundle install                                              # add vcr
RAILS_ENV=test bundle exec rails db:create db:schema:load    # one-time, this environment had no test DB yet
npm install                                                  # one-time, node_modules was absent
RAILS_ENV=test bundle exec rspec [target]                    # per new spec file, then full suite
bin/rubocop [touched files] -f simple        # then -A to autocorrect 4 Layout/SpaceInsideArrayLiteralBrackets offenses
npx vitest run [target]                                      # per new/changed test file, then full suite
bundle exec srb tc                                           # informational
```

## Verification

- **`app_core` full RSpec suite**: 37 examples, 0 failures (up from a
  9-example green baseline captured before any change).
- **Rubocop** (all new/touched files): 0 offenses after one
  autocorrect pass (4 `Layout/SpaceInsideArrayLiteralBrackets` offenses,
  purely stylistic). The only remaining offenses anywhere in the touched
  file set are 8 pre-existing ones on `Gemfile` lines 45–49 (`sorbet`,
  `sorbet-runtime`, `tapioca`, `jwt`) — not introduced by, or adjacent
  to, this plan's one added line, and not logged in `fix_me.md`; left
  untouched per "modify only files required by the plan."
- **`srb tc`**: 19 errors, all `Unable to resolve constant`
  (`RSpec`/`WebMock`/`VCR`) on the new spec/support files — the same
  pre-existing category every prior `app_core`/`app_fetcher` plan's
  verification has already identified and accepted (no generated RBI for
  test-only gems), just more instances for the newly added files and the
  newly added `vcr` gem specifically. Not part of this project's CI.
- **`app_core` full Vitest suite**: 83 tests across 14 files, 0 failures
  (up from a 67-test, 11-file baseline).
- **The one real VCR cassette** (`spec/cassettes/Sessions/GET_/session/callback/
  when_Steam_validation_genuinely_fails/...yml`) was inspected directly:
  confirmed a genuine `POST https://steamcommunity.com/openid/login`
  round trip with a real `is_valid:false` Steam response body, no
  secrets in the recording (the request carried no API key; the
  `filter_sensitive_data` config is in place for any future cassette that
  would).
- **Final diff review**: only files listed in the plan's Files To
  Modify/Create changed (confirmed via `git status`); one incidental,
  unrelated change (`package-lock.json`'s top-level `name` field,
  surfaced by a first-time local `npm install` needed to run the
  suite at all) was reverted rather than committed.

## Deviations

- **`current_user` deleted-user edge case uses a real sign-in-then-delete
  sequence instead of directly injecting `session: { user_id: ... }`.**
  The plan's Implementation Approach proposed `get root_path, session: {
  user_id: <nonexistent id> }`, but Rails request specs don't reliably
  support presetting session state that way before the session
  middleware has ever run. Instead, the test signs a real user in via a
  stubbed `Steam::LoginUser.call` through the actual `#callback` action
  (establishing a genuine session cookie), deletes that user, then
  issues the real request under test — exercising the exact same
  `User.find_by(id: session[:user_id]) → nil` path, via a more reliable
  mechanism than the originally-sketched approach.
- **No exact before/after `srb tc` diff via `git stash`** (unlike several
  prior `app_core`/`app_fetcher` plans' verification sections) — a stash
  attempt was made but reverted immediately once it became clear
  `git stash` doesn't touch untracked files, which would have produced a
  misleading mixed state (new spec files present, but `Gemfile`/
  `rails_helper.rb` temporarily reverted) rather than a clean comparison.
  The category-level check (all errors are the pre-existing
  "unresolved constant" kind) was sufficient given this is a test-only
  plan with no production-code changes.
- Everything else matched the plan as written, including the VCR-recording
  approach: outbound network access to `steamcommunity.com` was available
  in this implementation environment (the plan's own stated Assumption,
  confirmed rather than falling back to the named stub-based contingency).

## Remaining Issues

- A genuinely live-recorded VCR cassette for `#callback`'s **success**
  path still doesn't exist (no real Steam login or `STEAM_WEB_API_KEY`
  available in this environment) — the happy path and `RecordInvalid`
  paths remain covered via a direct `Steam::LoginUser.call` stub, as the
  plan explicitly anticipated and accepted. Worth revisiting if this
  suite is ever run somewhere with real Steam credentials.
- Pre-existing, out-of-scope deviations logged in `fix_me.md`
  (`authenticator.rb`'s missing Sorbet sigil, `application_controller.rb`'s
  missing sigil, `sessions_controller.rb`'s `typed: true` instead of
  `typed: strict`) remain unfixed, as scoped — this plan only added specs
  exercising those files, never edited them.
- `app_fetcher`'s own separately-logged, still-pending VCR migration
  (`inventories_spec.rb`/`price_histories_spec.rb`) remains untouched, as
  scoped.
