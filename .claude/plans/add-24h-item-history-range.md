---
status: implemented
app: fetcher+core
goal: Add a "24h" time range to the item-detail price-history chart (not the portfolio hero chart)
created: 2026-10-03
---

# Development Plan

## Goal

Let a user viewing an individual item's detail chart select a "24h" range
that plots every raw `PriceLog` point recorded for that item in the last
24 hours, with no downsampling/bucketing. The portfolio hero chart is
explicitly out of scope — confirmed with the user — because
`InventoryValueLog` only stores one value per day per `steam_id`, so a
real 24h portfolio series doesn't exist today and reconstructing one is a
separate, larger piece of work (see Risks/Out of Scope).

## Expected Behavior

- The item-detail chart's range toggle shows five options:
  `24H · 7D · 30D · 1Y · ALL` (new `24H` button, leftmost).
- The portfolio hero chart's range toggle is unchanged: `7D · 30D · 1Y ·
  ALL` — no `24H` option.
- Selecting `24h` on the item-detail chart calls
  `GET /api/v1/item_prices/:market_hash_name/history?period=24h` and
  renders every `PriceLog` row from the last 24 hours as its own point
  (typically ~24 points at the existing ~hourly `PriceScheduler` cadence),
  plus the existing "current price, now" fallback point if the last log
  doesn't already match the item's current price.
- Switching between portfolio and item mode preserves each mode's own
  last-selected range independently — picking `24h` on an item, then
  clicking back to the portfolio tile, still shows the portfolio's
  previous range (e.g. `30d`), not `24h` and not a reset to a default.
- `period=24h` on an unknown `market_hash_name` or with no `PriceLog`
  rows in the window behaves exactly like every other period already
  does (`[]`, or a single current-price fallback point) — no new edge
  case introduced.
- Requesting `period=24h` against `GET /api/v1/inventory_values`
  continues to be unreachable from the UI (the portfolio toggle never
  offers it) and remains a `400 Unsupported period` if hit directly,
  consistent with any other unsupported value — no behavior change
  needed there.

## Scope

### In Scope

- `Api::V1::ItemPricesController::PERIODS`: add `"24h" => 24.hours`.
- `chartConfig.js`: add a `24h` entry to `RANGE_MS` and `RANGE_SPAN`;
  split the single `RANGES` export into `PORTFOLIO_RANGES` (unchanged
  4 values) and `ITEM_RANGES` (5 values, `24h` first).
- `reducer.js`: split `state.range` into `state.portfolioRange` and
  `state.itemRange`; replace the single `RANGE_CHANGED` action with
  `PORTFOLIO_RANGE_CHANGED` and `ITEM_RANGE_CHANGED`; fix the stale
  `range: '7d', // '24h' | '7d' | '30d'` comment.
- `Dashboard.jsx`: feed each hook its own range field; compute which
  range value and dispatch action to hand to `PortfolioTile` based on
  `state.mode`.
- `RangeToggle.jsx`: accept a `ranges` prop instead of importing the
  constant directly.
- `PortfolioTile.jsx`: pick `ITEM_RANGES` vs `PORTFOLIO_RANGES` based on
  its existing `mode` prop, pass to `RangeToggle`.
- Test coverage for all of the above (see Test Plan).

### Out of Scope

- A 24h (or any intraday) view for the portfolio hero chart. Confirmed
  with the user: this would require reconstructing a portfolio-value
  time series from each owned item's own `PriceLog` history (reviving
  something like the deleted client-side `portfolioSeries.js`/
  `sumAsOfEachHour`, now server-side) — a separate, larger change, not
  bundled into this one.
- Any change to `ItemTrendCache`/`dynamics`/`trend` endpoints (unrelated
  to the detail chart; they feed the item list's sparklines and 24h
  delta, not this chart).
- Any change to `PriceLog` write cadence/granularity — the existing
  ~hourly `PriceScheduler` cadence is accepted as-is for this view.
- Adding `24h` to `InventoryValuesController::PERIODS` — not needed
  since the UI never sends it for that endpoint.

## Implementation Approach

**Backend** — the existing `#history` action already branches on
`period == "30d"` (cached, downsampled-free-by-construction since
`PriceHistoryCache` just stores raw logs within 30 days) vs. any other
period (raw `PriceLog.where(..., created_at: since..).order(:created_at)`
query, already zero-downsampling). `"24h"` is just another key in that
same generic branch — no new code path, only a new `PERIODS` entry.

**Frontend** — the portfolio and item-detail charts currently share one
`RangeToggle` instance, one `RANGES` list, and one `state.range` field
(`Dashboard.jsx` feeds the same value to both `usePortfolioHistory` and
`useItemHistory`). Since the two charts must now offer different range
sets, and selecting a period the other endpoint doesn't support would
otherwise break that endpoint's fetch, the single `range` field splits
into two independent reducer fields — the same pattern already used for
the filters' independent fields (`weapons`/`conditions`/`stattrakOnly`
each get their own toggle action rather than sharing one). `PortfolioTile`
already receives `mode` as a prop, so it's the natural place to decide
which `ranges` list to hand to `RangeToggle`; `RangeToggle` itself stays
a pure presentational list-renderer, now driven by a prop instead of a
hardcoded import.

## Files To Modify

- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb`
  — add `"24h" => 24.hours` to `PERIODS`.
- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb`
  — new examples for `period=24h` (see Test Plan).
- `app_core/app/frontend/dashboard/chartConfig.js`
  — add `24h` to `RANGE_MS` and `RANGE_SPAN`; replace `RANGES` with
  `PORTFOLIO_RANGES`/`ITEM_RANGES`.
- `app_core/app/frontend/dashboard/reducer.js`
  — replace `range` with `portfolioRange`/`itemRange` in `initialState`
  (fixing the stale comment); replace the `RANGE_CHANGED` case with
  `PORTFOLIO_RANGE_CHANGED`/`ITEM_RANGE_CHANGED`.
- `app_core/app/frontend/dashboard/Dashboard.jsx`
  — pass `state.portfolioRange`/`state.itemRange` to the respective
  hooks; compute the active range + dispatch action for `PortfolioTile`
  based on `state.mode`.
- `app_core/app/frontend/dashboard/components/RangeToggle.jsx`
  — accept `ranges` as a prop; add a `24h` label to `RANGE_LABELS`.
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx`
  — import `PORTFOLIO_RANGES`/`ITEM_RANGES`, pick by `mode`, pass to
  `RangeToggle`.
- `app_core/app/frontend/dashboard/__tests__/reducer.test.js`
  — split the `RANGE_CHANGED` test into `PORTFOLIO_RANGE_CHANGED`/
  `ITEM_RANGE_CHANGED` tests; update `initialState` field references.
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx`
  — new test(s) asserting the rendered `RangeToggle` options differ by
  mode.

## Files To Create

None — every change fits an existing file.

## Test Plan

**Backend (`item_prices_spec.rb`)**:
- `period=24h` with `PriceLog` rows inside and outside the 24h window
  returns only the in-window rows, each as its own point (no bucketing)
  — mirrors the existing "an explicit period wider than 30 days" test
  shape, just with a 24h cutoff and logs placed relative to it (e.g. one
  `created_at: 2.hours.ago`, one `created_at: 30.hours.ago`).
- `period=24h` composes correctly with the existing current-price
  fallback: an item whose only log falls outside 24h still returns
  exactly one point (reuse the existing "falls outside the requested
  window" test pattern already proven for `7d`).
- `period=24h` for an unknown `market_hash_name` returns `[]` (already
  covered generically, but confirm it isn't period-specific by
  construction — no new test strictly required, existing "unknown name"
  test doesn't vary by period).

**Frontend**:
- `reducer.test.js`: `PORTFOLIO_RANGE_CHANGED` updates only
  `portfolioRange` (leaves `itemRange`/`mode` untouched);
  `ITEM_RANGE_CHANGED` updates only `itemRange` (leaves `portfolioRange`/
  `mode` untouched). Replaces the single old `RANGE_CHANGED` test.
- `PortfolioTile.test.jsx`: portfolio mode renders a `RangeToggle` with
  no `24H` button; item mode renders one that includes `24H`. Query via
  `screen.queryByRole('button', { name: '24H' })` (absent vs. present).
- No new test needed for `RangeToggle.jsx`/`HeroChart.jsx` /
  `chartConfig.js` directly — per the project's documented testing
  convention (`.claude/styleguides/core/react-dashboard.md`), these stay
  simple presentational/constant exports with no branching logic of
  their own; behavior is exercised indirectly through `PortfolioTile`'s
  test and the backend's own coverage of what `24h` actually returns.

## Implementation Steps

1. **Backend, RED → GREEN**: add the two new `item_prices_spec.rb`
   examples for `period=24h` (window filtering, fallback-point
   composition); confirm they fail against the current `PERIODS` hash
   (missing key → `400`); add `"24h" => 24.hours` to `PERIODS`; confirm
   green.
2. **`chartConfig.js`**: add `24h` to `RANGE_MS`/`RANGE_SPAN`; rename
   `RANGES` to `PORTFOLIO_RANGES` (unchanged value) and add
   `ITEM_RANGES = ['24h', ...PORTFOLIO_RANGES]`.
3. **`reducer.js`, RED → GREEN**: update `reducer.test.js` to the two
   split actions first; then update `initialState` and the reducer's
   `switch` to match (replace `RANGE_CHANGED` case with
   `PORTFOLIO_RANGE_CHANGED`/`ITEM_RANGE_CHANGED`, each updating only
   its own field).
4. **`RangeToggle.jsx`**: accept `ranges` prop, drop the direct
   `RANGES` import, add `'24h': '24H'` to `RANGE_LABELS`.
5. **`PortfolioTile.jsx`, RED → GREEN**: add the new
   `PortfolioTile.test.jsx` case(s) asserting per-mode range options
   first; then wire `PortfolioTile` to import
   `PORTFOLIO_RANGES`/`ITEM_RANGES`, select by `mode`, pass to
   `RangeToggle`.
6. **`Dashboard.jsx`**: update hook wiring
   (`usePortfolioHistory(..., state.portfolioRange)`,
   `useItemHistory(..., state.itemRange)`) and the props/dispatch passed
   to `PortfolioTile` (active range + mode-appropriate action type).
7. Run full backend and frontend suites; rubocop on touched Ruby files.

## Verification

- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/requests/api/v1/item_prices_spec.rb"`,
  then the full `app_fetcher` suite.
- `bundle exec rubocop` on the touched controller/spec file.
- `npx vitest run` for the full `app_core` frontend suite.
- Manual check (already planned separately per the user's own request to
  re-run the browser walkthrough): open an item's detail chart, confirm
  a `24H` button appears and renders hourly-ish points; confirm the
  portfolio tile's toggle has no `24H` button and its own range selection
  survives a round-trip through item mode and back.

## Risks

- **Splitting `state.range` touches every current range consumer at
  once** (`Dashboard.jsx`, `PortfolioTile.jsx`, `reducer.test.js`,
  `PortfolioTile.test.jsx`) — contained by doing the reducer change with
  its own RED→GREEN pass before touching the components that consume it,
  per Implementation Steps.
- **If `PriceScheduler`'s cadence drifts above ~1/hour for a given item
  (rate limiting, backlog), the 24h view can show fewer points than a
  user expects** — this is an existing, accepted characteristic of
  `PriceLog`'s write cadence, not something this plan changes or needs
  to guard against.
- **Portfolio 24h remains unsupported** — flagged again here for
  visibility: if the user later asks for it, it needs its own plan (see
  Out of Scope).

## Assumptions

- `24h` using exactly `24.hours` (not "since start of today") matches
  the user's stated intent ("все точки ... за последние 24 часа" — a
  trailing 24-hour window, not a calendar-day boundary) and is
  consistent with how `change_24h_cents` is already computed elsewhere
  (`PriceUpdateWorker` also uses a trailing `24.hours.ago` window, not a
  calendar day).
- `24h` is inserted as the leftmost/shortest option in `ITEM_RANGES`
  (`['24h', '7d', '30d', '1y', 'all']`), matching the existing
  ascending-duration ordering of the toggle.

## Applicable Styleguides

- `.claude/styleguides/fetcher/internal-api-controllers.md` — governs the
  `PERIODS` hash addition: `#history` already follows every MUST/SHOULD
  here (single collaborator query, `current_steam_id`-free params-only
  branching, no failure path needed for a local ActiveRecord read); a new
  key in an existing hash doesn't introduce any new constraint this guide
  doesn't already cover.
- `.claude/styleguides/ruby-sorbet.md` — the one-line `PERIODS` change
  stays inside the existing `T::Hash[String, T.nilable(ActiveSupport::Duration)]`
  sig; no new typing surface.
- `.claude/styleguides/rspec-conventions.md` — governs the new
  `item_prices_spec.rb` examples (request-spec level, one behavior per
  example, reusing the existing fixture/assertion shape already used by
  the `7d`/`1y` period examples).
- `.claude/styleguides/core/react-dashboard.md` — governs every frontend
  file touched: `chartConfig.js` stays a sibling constants file, not a
  `utils/` derivation function; `reducer.js`'s two-field split follows
  the guide's documented precedent for independently-varying state
  (status-field splitting rationale, and the existing
  `WEAPON_FILTER_TOGGLED`/`CONDITION_FILTER_TOGGLED`/
  `STATTRAK_FILTER_TOGGLED` action-per-field pattern); `RangeToggle.jsx`
  and `HeroChart.jsx` correctly stay without dedicated test files per the
  guide's "branches on data" dividing line (neither gains branching logic
  of its own); `PortfolioTile.jsx` gaining mode-based ranges selection
  does cross that line, so it gets new test coverage, consistent with
  the guide's own `ItemsTile.test.jsx` precedent for composite
  components with real derivation logic.

## Completion Criteria

- `PERIODS` accepts `24h` on the backend, returning raw unbucketed
  `PriceLog` points for the window, composing with the existing
  current-price fallback.
- The item-detail `RangeToggle` offers `24H`; the portfolio one does not.
- Portfolio and item ranges are independently selectable and persist
  independently across mode switches.
- All new/updated tests pass; full backend and frontend suites remain
  green; rubocop clean on touched files.

# Implementation Summary

## Implemented

- `Api::V1::ItemPricesController::PERIODS` gained `"24h" => 24.hours`.
  The existing non-`"30d"` branch in `#history` already queries raw,
  unbucketed `PriceLog` rows for whatever window `PERIODS` resolves to —
  no new code path was needed, just the new hash key.
  **Superseded**: a later code-review pass replaced this `PERIODS` hash
  (and `InventoryValuesController`'s separate, drifted copy) with a
  shared `PricePeriod` `T::Enum` — see `dashboard-api-redesign.md`'s
  Code Review Remediation addendum. The `24h` behavior itself is
  unchanged, just reached via `PricePeriod::TwentyFourHours` now instead
  of a hash key.
- `chartConfig.js`: added a `24h` entry to `RANGE_MS` and `RANGE_SPAN`;
  replaced the single `RANGES` export with `PORTFOLIO_RANGES` (`7d/30d/
  1y/all`, unchanged) and `ITEM_RANGES` (`24h/7d/30d/1y/all`).
- `reducer.js`: `initialState.range` split into `portfolioRange` and
  `itemRange` (also fixed the stale `// '24h' | '7d' | '30d'` comment
  that predated this feature); `RANGE_CHANGED` split into
  `PORTFOLIO_RANGE_CHANGED`/`ITEM_RANGE_CHANGED`, each updating only its
  own field.
- `Dashboard.jsx`: `usePortfolioHistory`/`useItemHistory` now each read
  their own range field; the range/dispatch handed to `PortfolioTile` is
  computed from `state.mode` (item mode uses `itemRange` +
  `ITEM_RANGE_CHANGED`, portfolio mode uses `portfolioRange` +
  `PORTFOLIO_RANGE_CHANGED`).
- `RangeToggle.jsx`: now takes `ranges` as a prop instead of importing a
  hardcoded constant; added a `24H` label.
- `PortfolioTile.jsx`: picks `ITEM_RANGES` vs `PORTFOLIO_RANGES` based on
  its existing `mode`/`selectedItem` check, passes the result to
  `RangeToggle`.
- No CSS change needed — `.range-toggle` is an unconstrained flexbox; a
  5th button lays out the same way the existing 3-4 did.

## Tests

- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb`: new
  `"period=24h"` context — one example for raw-point filtering (log
  inside the window included, log outside excluded, no bucketing), one
  nested example for the existing current-price fallback composing
  correctly with the new period (only log falls outside 24h → still one
  fallback point).
- `app_core/app/frontend/dashboard/__tests__/reducer.test.js`: the old
  single `RANGE_CHANGED` test replaced with
  `PORTFOLIO_RANGE_CHANGED`/`ITEM_RANGE_CHANGED`, each asserting only its
  own field changes and the other range/mode stay untouched.
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx`: two
  new tests — portfolio mode's toggle has no `24H` button, item mode's
  does.

Commands actually executed:
- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/requests/api/v1/item_prices_spec.rb -e 'period=24h'"` (RED, confirmed failure for the expected reason — unsupported period)
- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/requests/api/v1/item_prices_spec.rb"` (GREEN, 22 examples)
- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec && bundle exec rubocop app/controllers/api/v1/item_prices_controller.rb spec/requests/api/v1/item_prices_spec.rb"` (121 examples, 0 failures; rubocop clean)
- `docker compose run --rm app_fetcher bash -c "bundle exec srb tc"` (97 errors — unchanged from the pre-existing baseline)
- `npx vitest run app/frontend/dashboard/__tests__/reducer.test.js` (RED then GREEN)
- `npx vitest run app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` (RED then GREEN)
- `npx vitest run` (full suite, 61 tests, 12 files, all passing)

## Verification

- Backend: 121/121 rspec examples green, rubocop clean on touched files,
  `srb tc` at its unchanged pre-existing baseline (97 errors).
- Frontend: 61/61 vitest tests green across 12 files.
- Final diff reviewed: only the files listed in the plan's Files To
  Modify changed; no stray references to the old `RANGES`/`state.range`/
  `RANGE_CHANGED` names remain anywhere in `app_core/app/frontend/dashboard/`
  (confirmed via grep).
- Manual browser verification of the new `24H` button (rendering,
  fetching, point count) was not performed as part of this change —
  bundled into the user's separately-requested browser walkthrough.

## Deviations

None — implementation matched the plan as written.

## Remaining Issues

- Manual browser verification of the 24h item-detail view is still
  pending, folded into the broader manual walkthrough the user asked to
  re-run in this same session (dev-login route, full flow check).
- Portfolio 24h remains unsupported, as scoped — would need its own plan
  if ever requested (see this plan's Out of Scope/Risks).
