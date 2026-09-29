---
status: implemented
app: core
goal: Render the dashboard's item list and current prices as soon as the inventory call resolves, without waiting for the price-history batch, and show a lightweight skeleton before that
created: 2026-09-28
---

# Development Plan

## Goal

Cut perceived dashboard load time by no longer blocking the first render on
*two* sequential network calls. Today `useDashboardData` awaits
`GET /inventories/me` (items + current prices) **and then**
`POST /price_histories` (per-item history) before rendering anything —
`Dashboard.jsx` shows a bare "Loading dashboard…" string the whole time.
After this change, the dashboard renders items with their current prices
as soon as the first call resolves; price-history-dependent pieces (hero
sparkline chart, per-item 24h delta badge, market-volume chart) fill in
moments later once the second call resolves, instead of blocking the
whole page.

## Why this is smaller than the original "skeleton cache" framing

Earlier discussion of this task (see this session's research-codebase
report) assumed a literal backend "skeleton" response (items with no
price at all) plus a separate batched-price endpoint, mirroring the
original brainstorm's `user:{id}:inventory_v1` / `item:{name}:price_24h`
cache split. Research found this isn't actually where the current
bottleneck is:

- `GET /inventories/me` **already** returns `current_price_cents`/
  `change_24h_cents` merged with the item list in one response (see
  `Api::V1::InventoriesController#show`) — there is no existing "prices
  arrive late" problem for the item list or its current price.
- The only thing actually blocking today's first render past that point
  is `POST /price_histories`, a second, independent round-trip whose
  result is required for: the hero chart's series, per-item 24h
  delta/sparkline, and market volume — **not** for the item list, current
  prices, or price-based sort/filtering.
- Splitting `/inventories/me` itself into a true no-price skeleton +
  separate batched-price endpoint would add a second `app_fetcher`
  round-trip for data it already returns in one, buying no measurable
  speedup on a warm cache and none at all on the cold-Steam-API path
  (item names are still needed before prices can be requested, current
  or otherwise).

Per the user's own scope decision ("сужаем, потом в задаче 2
разберемся"), this plan implements the smaller, fully-grounded version:
**decouple rendering from the price-history call only.** No
`app_fetcher` endpoint, cache class, or contract changes — this is a
frontend-only change. This also means the earlier scope decisions about
cache backend (solid_cache) and skeleton-invalidation-on-trade don't
apply to this plan at all: nothing on the caching layer is touched, so
there is nothing new to invalidate or store. Those decisions remain
recorded (see this session's history) for whichever future phase actually
introduces a new cache bucket.

## Expected Behavior

**Normal behavior**

- Before the inventory call resolves: a lightweight skeleton screen
  renders (placeholder blocks matching the hero/items/volume tile
  layout) instead of today's plain "Loading dashboard…" text.
- As soon as `GET /inventories/me` resolves: the item list renders with
  real names, metadata (weapon/condition/stattrak), and current prices.
  The hero tile shows the correct total portfolio value (sum of
  `current_price_cents`) immediately. Filtering, name/price-based
  sorting, and pagination are fully functional at this point — none of
  them depend on price history.
- Items with no price yet (`current_price_cents: null` — the existing
  warmup edge case) render with a "—" placeholder, not "$0.00" (see Risks
  — fixes a latent formatting bug that becomes far more visible under
  this change).
- Price-history-dependent UI (hero sparkline/chart, per-item 24h delta
  badge, market-volume chart/count) shows a pending state until
  `POST /price_histories` resolves, then fills in without disturbing
  already-rendered rows, sort order, or scroll position.
- Default sort (`delta_desc`) and per-item delta badges do not show a
  misleading "▲ 0.0%" for items whose history hasn't arrived yet — they
  render as pending/hidden until real history data exists, same visual
  language `PortfolioTile` already uses for its own "no data yet" case
  (`hasData` gate).

**Edge cases**

- An inventory with zero items: unchanged — no history call is made,
  dashboard renders the existing empty state immediately.
- An item with a real price but zero `PriceLog` history rows (e.g. brand
  new pricing): today this already produces an empty `points` array from
  `PriceHistoryCache`/`price_histories`; must continue to render
  gracefully (single flat point derived from `current_price_cents` via
  `itemSeries`, exactly as `itemSeries.js` already does) rather than a
  crash or a misleading zero-delta badge.

**Failure behavior**

- Inventory call failure: unchanged from today — full error state,
  nothing renders (there is no meaningful partial state without the item
  list itself).
- Price-history call failure: **changed, intentionally.** Today this
  blanks the entire dashboard even though the item list/prices already
  loaded successfully. After this change, the item list/current
  prices/hero total value stay visible and usable; only the
  history-dependent pieces (hero chart, delta badges, market volume) stay
  in a permanent pending/unavailable state instead of populating. This is
  a direct, in-scope consequence of decoupling the two calls, not scope
  creep — the whole point is that a failure in the second call shouldn't
  take down data the first call already successfully delivered.

**Must remain unchanged**

- `GET /inventories/me` and `POST /price_histories` request/response
  shapes — untouched, no `app_fetcher` file changes at all.
- Filtering, sorting, and pagination logic in `reducer.js`/`filters.js` —
  untouched; they already operate correctly on partially-hydrated items
  (`priceHistory: []`) because `itemSeries`/`changePct` are already
  null-safe.
- `portfolioSeries`/`marketVolume` pure functions — untouched; they
  already produce a sensible (if empty) result when every item's
  `priceHistory` is `[]`.

## Scope

### In Scope

- `useDashboardData.js`: split the single awaited `load()` into two
  stages — render after the inventory call resolves, keep loading price
  history in the background, merge it in and re-render when it resolves.
- A new pending/loading signal (`historyStatus`) exposed alongside
  `data`, distinct from the overall `status`, so components can tell
  "no history data because it hasn't loaded yet" apart from "genuinely
  no history for this item."
- A lightweight skeleton-loading component shown pre-inventory-resolve,
  replacing the current plain-text loading message.
- `PortfolioTile.jsx`: fix the hero value to fall back to
  `portfolio.currentValueCents` instead of `0` when there's no series
  data yet (see Risks — this is a **pre-existing bug**, invisible today,
  that this change would otherwise surface on every single dashboard
  load).
- `ItemRow.jsx`: hide the 24h delta badge when an item has no history
  data yet, instead of showing a misleading "▲ 0.0%", reusing the same
  `hasData`-gating pattern `PortfolioTile` already uses.
- `format.js`: fix `fmtPrice(null)`/`fmtPrice(undefined)` to render "—"
  like `fmtPrice(0)` already does, instead of "$0.00".
- Test coverage for all of the above (see Test Plan).

### Out of Scope

- Any `app_fetcher` change — no new caching class, no new endpoint, no
  contract change, no cache-backend decision (solid_cache stays exactly
  as configured).
- Per-visible-row / virtual-scroll lazy price loading — ruled out by this
  session's research (conflicts with `PortfolioTile`/`MarketVolumeTile`/
  price-sort needing the full data set; deferred to Задача 2 per the
  user's decision).
- Any new item metadata field (`rarity`, `icon_url`, or anything else not
  already consumed by the frontend today) — confirmed via grep that
  neither exists anywhere in either app.
- Inventory-cache invalidation-on-trade — not touched by this plan since
  no inventory cache is touched at all.
- Migrating `inventories_spec.rb`/`price_histories_spec.rb` off WebMock
  (pre-existing `fix_me.md` item) — not triggered, since this plan
  doesn't touch either file (no backend changes).
- `changeCents`/`change_24h_cents` — confirmed present on the mapped item
  object but not actually read anywhere in the frontend (delta display
  and sort both derive from `priceHistory` via `changePct`/`itemSeries`,
  not from this field). Leaving as dead data; not this plan's job to
  remove it.

## Implementation Approach

**`useDashboardData.js`.** Replace the single `load()` async function
with two sequential-but-independently-rendered stages:

1. `await fetchJson(inventories)`. Map items via the existing `mapItem`
   with `pointsByName = {}` (so every item gets `priceHistory: []`, its
   already-null-safe default). Compute `portfolio = portfolioSeries(items)`
   and `marketVolume = marketVolume(items)` — both already tolerate
   all-empty histories (verified: `sumAsOfEachHour`/`bucketByHour` return
   `[]` when no point lists have any data). Call `setData({..., items,
   portfolio, marketVolume})`, `setStatus('success')`,
   `setHistoryStatus('pending')`. This is the new earlier render point.
2. If `names.length`, `await fetchJson(price_histories)` in the
   background. On success: rebuild `pointsByName`, remap items (now with
   real `priceHistory`), recompute `portfolio`/`marketVolume`, `setData`
   again, `setHistoryStatus('ready')`. On failure: `setHistoryStatus
   ('error')`, leave the already-set `data` (from stage 1) untouched —
   do **not** call `setStatus('error')`, since the page already has valid
   data to show.

`status` keeps its existing three values (`loading`/`success`/`error`)
and existing meaning for the inventory call — `Dashboard.jsx`'s current
`status === 'loading'`/`'error'` branches don't need new branches, only
their loading-state UI changes (see next point). `historyStatus`
(`'pending'|'ready'|'error'`) is new, read by `PortfolioTile`,
`ItemRow` (via items carrying their own `priceHistory`, so no prop
threading needed there beyond what already exists), and
`MarketVolumeTile`.

**Skeleton loading state.** Replace `Dashboard.jsx`'s `status ===
'loading'` branch (currently `<p className="dash-loading">Loading
dashboard…</p>`) with a new presentational `DashboardSkeleton` component
— static placeholder blocks in the hero/items/volume layout shape, no
data dependency, no new test-worthy logic beyond "it renders."

**`PortfolioTile.jsx` fix.** Change:
```
const last = hasData ? values[values.length - 1].value : isItemMode ? selectedItem.currentPriceCents : 0
```
to fall back to `portfolio.currentValueCents` (already passed in via the
`portfolio` prop) instead of the hardcoded `0` in the portfolio-mode/
no-data branch. Today this is a latent bug invisible because
`portfolio.series[range]` is essentially always non-empty by the time
anything renders (both calls are awaited together) — this plan's earlier
render point makes the empty-series case the *normal* first-paint state
for every dashboard load, so the bug must be fixed as a direct
prerequisite, not a nice-to-have.

**`ItemRow.jsx` fix.** Gate the delta badge on history availability,
mirroring `PortfolioTile`'s existing `showDelta = isTradable && hasData`
pattern:
```
const hasHistory = item.priceHistory.length > 0
const showDelta = isTradable && hasHistory
```
and use `showDelta` instead of the current bare `isTradable` check around
the delta `<span>`.

**`format.js` fix.** `fmtPrice`: treat `null`/`undefined` the same as
`0` (render "—"), instead of falling through to `fmtUSD(0)` ("$0.00").

## Files To Modify

- `app_core/app/frontend/dashboard/hooks/useDashboardData.js` — two-stage
  load, new `historyStatus` state, background history fetch with
  independent error handling.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — swap the loading
  branch to render `DashboardSkeleton`; thread `historyStatus` to
  `PortfolioTile`/`MarketVolumeTile` if they need it directly (or read it
  off `data`, whichever keeps prop-drilling smallest — decide during
  implementation, not a design fork worth pre-committing to here).
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx` — hero
  value fallback fix (see above).
- `app_core/app/frontend/dashboard/components/ItemRow.jsx` — delta badge
  gating fix (see above).
- `app_core/app/frontend/dashboard/components/MarketVolumeTile.jsx` —
  show a pending indicator (e.g. "—" or a subtle loading affordance)
  instead of a bare "0" while `historyStatus === 'pending'`.
- `app_core/app/frontend/dashboard/utils/format.js` — `fmtPrice`
  null/undefined fix.
- `app_core/app/frontend/dashboard/__tests__/useDashboardData.test.js` —
  rewrite around the two-stage resolution (see Test Plan).
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx` —
  extend with a no-history-yet scenario.

## Files To Create

- `app_core/app/frontend/dashboard/components/DashboardSkeleton.jsx` —
  static placeholder layout shown before the inventory call resolves.
  New file because no equivalent exists today (`Dashboard.jsx`'s loading
  branch is currently a single `<p>`).
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` —
  new (no component test exists for this tile today): covers the hero
  value fallback fix directly, since no other test currently exercises
  `PortfolioTile` with an empty series.
- `app_core/app/frontend/dashboard/__tests__/format.test.js` — new (no
  test file exists for `format.js` today): covers the `fmtPrice`
  null/undefined/zero cases directly.

## Test Plan

- **`useDashboardData.test.js`** (rewritten around two stages):
  - Inventory resolves, history still pending: assert `status ===
    'success'` fires as soon as the inventory mock resolves (before the
    history mock resolves), with `historyStatus === 'pending'`, items
    carrying correct `currentPriceCents` and empty `priceHistory`, and
    `portfolio.currentValueCents` correctly summed.
  - History then resolves: assert a second update with `historyStatus
    === 'ready'`, items now carrying merged `priceHistory`, `portfolio`/
    `marketVolume` recomputed.
  - History fetch fails: assert `status` stays `'success'` (items remain
    visible, regression-guarded against today's "one failure blanks
    everything" behavior), `historyStatus === 'error'`.
  - Inventory fetch fails: unchanged regression case — full `status ===
    'error'`.
  - Empty inventory: unchanged regression case — history call skipped
    entirely, single fetch call total.
- **`PortfolioTile.test.jsx`** (new): with `portfolio.series[range] = []`
  and a non-zero `portfolio.currentValueCents`, the hero renders the
  correct value (not "$0.00") and does not show a delta badge (`hasData`
  false). With non-empty series, existing delta/value behavior
  unaffected (regression case using realistic series data).
- **`ItemsTile.test.jsx`** (extended): an item with `priceHistory: []`
  and a real `currentPriceCents` renders its price, no delta badge, and
  participates correctly in price-based and name-based sort; the default
  delta-based sort doesn't crash or misorder against items that do have
  history.
- **`format.test.js`** (new): `fmtPrice(0)` → `'—'` (regression),
  `fmtPrice(null)` → `'—'` (the fix), `fmtPrice(undefined)` → `'—'`,
  `fmtPrice(3845)` → `'$38.45'` (regression).
- **`MarketVolumeTile`**: covered indirectly via `useDashboardData.test.js`'s
  assertions on `data.marketVolume` at each stage; no dedicated component
  test needed beyond that unless implementation reveals otherwise.
- **Regression**: `portfolioSeries.test.js`, `filters.test.js`,
  `reducer.test.js`, `marketVolume.test.js` are not expected to need
  changes (none of the pure functions they test change shape or
  behavior) — run them to confirm.

## Implementation Steps

1. `format.js`: TDD the `fmtPrice` null/undefined fix against a new
   `format.test.js`.
2. `PortfolioTile.jsx`: TDD the hero-value fallback fix against a new
   `PortfolioTile.test.jsx` (write the empty-series/correct-value case
   first, confirm it fails against current code, then fix).
3. `ItemRow.jsx`: TDD the delta-badge gating fix, extending
   `ItemsTile.test.jsx` with a no-history-yet row case.
4. `useDashboardData.js`: TDD the two-stage load against a rewritten
   `useDashboardData.test.js`, one scenario at a time (inventory-resolves-
   first, then-history-resolves, then history-failure, then existing
   regression cases).
5. `MarketVolumeTile.jsx`: add the pending-state indicator; extend its
   coverage via `useDashboardData.test.js`'s stage-1 assertions (no
   separate component test unless step 4 shows it's needed).
6. `Dashboard.jsx` + new `DashboardSkeleton.jsx`: wire the skeleton into
   the loading branch; thread `historyStatus` through to the components
   that need it.
7. Full frontend suite run; fix any fallout in the four "should be
   unaffected" pure-function test files if something unexpected surfaces.

## Verification

- `npm test` (or the project's configured Vitest command) for
  `app_core`'s frontend suite — targeted files first
  (`useDashboardData.test.js`, `PortfolioTile.test.jsx`,
  `ItemsTile.test.jsx`, `format.test.js`), then the full suite for
  regression.
- Manual check in a browser: load the dashboard on a warm cache and
  confirm the item list/prices appear, then confirm the hero
  chart/delta badges/market volume populate moments later without a
  layout jump or lost scroll/sort/filter state; throttle network (or
  stub a slow history response) to confirm the pending state is visible
  and not instant on a slower connection.
- No `app_fetcher` verification needed — no files in that app change.

## Risks

- **`PortfolioTile`'s hero-value bug is pre-existing, not introduced by
  this plan** — but this plan is what makes it fire on *every* dashboard
  load instead of never (today's simultaneous-await hides it in
  practice). Confirmed by reading `sumAsOfEachHour`: with every item's
  `priceHistory` empty, every hour bucket has `hasAnyData = false`, so
  `series[range]` is genuinely `[]`, and `PortfolioTile` currently
  hard-codes `last = 0` in that branch instead of using
  `portfolio.currentValueCents`. Must be fixed as part of this plan (see
  Scope), not treated as a follow-up.
- **`historyStatus` prop-threading shape** is deliberately left as an
  implementation-time decision (component props vs. reading off `data`)
  rather than pre-specified — whichever keeps the smallest diff against
  the existing `Dashboard.jsx`/tile prop patterns.
- **No frontend/React styleguide exists in this repo** — `.claude/styleguides/core/architecture-layers.md` covers controller/action/lib layering and the "no proxy" rule, but nothing governs React component structure, state-lifting conventions, or Vitest/`@testing-library` conventions specifically. This plan follows the *existing* patterns already visible in `ItemsTile.jsx`/`ItemsTile.test.jsx` (integration-style tests via a reducer harness, colocated `__tests__/`) since that's the only precedent, but `styleguides-check` should confirm whether a styleguide needs to be written before/alongside implementing this, per this repo's own pipeline rule ("if guides are missing, create them before moving on").
- **Two `setData` calls per load** (stage 1, then stage 2) means any
  component subscribed to `data` re-renders twice per dashboard load
  instead of once — acceptable for this app's scale, but worth knowing
  if a future performance pass looks at render counts.

## Assumptions

- No dedicated Vitest config nuance prevents adding new test files
  (`PortfolioTile.test.jsx`, `format.test.js`) alongside existing ones in
  `__tests__/` — inferred from the existing flat structure, not
  independently verified by running the suite yet.
- "Lightweight skeleton" (Files To Create) is a static, non-interactive
  placeholder — no shimmer/animation requirement was specified; kept
  minimal on purpose. Confirm this is sufficient before/while
  implementing if a more polished loading treatment is expected.

## Applicable Styleguides

- `.claude/styleguides/core/react-dashboard.md` — governs the whole
  Implementation Approach: component structure/naming for the new
  `DashboardSkeleton`, `utils/`-only placement for any new derived-data
  logic (none needed beyond what's already planned), and — directly —
  the `historyStatus` design. This styleguide's State & Data Loading
  section explicitly prescribes "a second, narrower status field scoped
  to that specific stage (e.g. a `historyStatus` alongside `status`)"
  for exactly this multi-stage-load shape, which is the design this plan
  already proposed — confirmed consistent, no rework needed. Its Testing
  section's "what gets a dedicated test file" rule also directly
  resolves this plan's open questions: `PortfolioTile.test.jsx` is
  justified (the component has real conditional/fallback logic —
  `hasData`/`isItemMode`/the value fallback this plan fixes), while
  `DashboardSkeleton` (pure layout, no branching) does not need one
  beyond confirming it renders.
- `.claude/adr/core/sparkline-vs-recharts.md` — relevant context for the
  `MarketVolumeTile`/`ItemRow` changes (both consume `Sparkline`) even
  though this plan doesn't add a new chart type: confirms the pending-state
  indicator these components need should stay outside the
  `Sparkline`/`HeroChart` boundary (plain text/markup), not a new chart
  variant.
- `.claude/adr/core/component-tests-real-reducer.md` — reinforces that
  `ItemsTile.test.jsx`'s extension (the no-history-yet scenario) should
  keep driving the real `dashboardReducer` through the existing harness,
  not switch to mocked props for the new case.
- `.claude/styleguides/core/architecture-layers.md` — confirms this plan
  doesn't violate the one rule above everything in `react-dashboard.md`:
  no new `app_core` endpoint/proxy is introduced; `useDashboardData.js`
  keeps calling `app_fetcher`'s `Api::V1::` endpoints directly.
- `.claude/styleguides/git-commits.md` — governs how this plan's
  eventual implementation is committed: since `react-dashboard.md` and
  its two ADRs were created specifically because this plan needed them
  (not pre-existing, reusable conventions), they're committed together
  with this plan's code as one `[Core]`-tagged commit (per "Task-Scoped
  Styleguides, ADRs, and Plans"), not a separate preceding `[AI
  WorkFlow]` commit.

`.claude/styleguides/rspec-conventions.md` and every `.claude/styleguides/fetcher/*`/`.claude/adr/fetcher/*` file were checked and confirmed not applicable — this plan touches no Ruby/RSpec files and no `app_fetcher` code at all.

## Completion Criteria

- [x] Desired behavior made explicit (two-stage render, failure
  isolation, pending states, the two pre-existing bugs found and slated
  for fixing).
- [x] Scope explicit (frontend-only; no backend/cache/contract changes;
  no new metadata fields).
- [x] Affected files/components identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (`styleguides-check`).
- [x] Implemented (`implement-plan`).

# Implementation Summary

## Implemented

- **`utils/format.js`**: `fmtPrice` now treats any falsy `cents`
  (`0`, `null`, `undefined`) uniformly as "no price" → `'—'`, instead of
  `null`/`undefined` falling through to `fmtUSD(0)` ("$0.00").
- **`components/PortfolioTile.jsx`**: the hero value's no-series-data
  branch now falls back to `portfolio.currentValueCents` instead of a
  hardcoded `0`, so the hero shows the real total immediately during the
  new pending window instead of flashing "$0.00".
- **`components/ItemRow.jsx`**: the 24h delta badge is now gated on
  `showDelta = isTradable && hasHistory` (`hasHistory =
  item.priceHistory.length > 0`) instead of `isTradable` alone, so an
  item with no history yet doesn't show a misleading "▲ 0.0%".
- **`hooks/useDashboardData.js`**: split into two stages. `load()` now
  fetches `/inventories/me`, immediately builds and sets `data` (items
  with real current prices, empty `priceHistory`), sets `status:
  'success'`, and sets a new `historyStatus` (`'pending'|'ready'|'error'`)
  — `'ready'` immediately if the inventory is empty, else `'pending'`
  followed by a background `loadHistory()` call. `loadHistory` fetches
  `/price_histories`, remaps items with real history, and updates `data`
  again + `historyStatus: 'ready'`; on failure it sets `historyStatus:
  'error'` without touching `status`/`data` — the already-shown items
  stay visible. `status`/`data` only regress to an error state if the
  *first* (inventory) fetch itself fails, unchanged from before.
- **`components/MarketVolumeTile.jsx`**: accepts a new `historyStatus`
  prop; renders `'—'` instead of a bare `0` count while
  `historyStatus === 'pending'`.
- **`components/DashboardSkeleton.jsx`** (new): a static, non-interactive
  placeholder reusing the existing `tile`/`tile-hero`/`tile-items`/
  `tile-volume` layout classes (so it inherits the real grid
  positioning/box styling with zero new CSS), with a few inline-styled
  placeholder bars. Shown by `Dashboard.jsx` while `status === 'loading'`,
  replacing the previous plain-text "Loading dashboard…" message.
- **`Dashboard.jsx`**: renders `DashboardSkeleton` for the loading state;
  threads the new `historyStatus` through to `MarketVolumeTile`.
  `PortfolioTile`/`ItemRow` needed no new prop — their fixes above derive
  entirely from data already in `portfolio`/`item`, per the styleguide's
  "smallest prop-drilling" guidance.

## Deviation: `components/Sparkline.jsx`

Not in the original plan's Files To Modify. Discovered while TDD-ing
`MarketVolumeTile`'s pending indicator: `Sparkline` crashed
(`TypeError: Cannot read properties of undefined`) whenever it was
rendered with an empty `values` array and `showArea: true` — exactly the
shape `marketVolume.sparkline` has during the new pending window (every
item's `priceHistory` is `[]`, so `bucketByHour` returns `[]`). This is a
pre-existing bug, but this plan's own core behavior (a pending render
with all-empty histories, on *every* dashboard load) makes it
unconditionally reachable rather than a rare edge case — the same
category as the `PortfolioTile`/`fmtPrice` bugs the plan already
anticipated fixing. Fixed by guarding the area-path computation on
`points.length > 0`; covered directly by
`MarketVolumeTile.test.jsx`'s pending-state test (which renders a real
`Sparkline` with an empty array and asserts no crash).

## Tests

- `__tests__/format.test.js` (new, 4 examples): `fmtPrice(0)`,
  `fmtPrice(null)`, `fmtPrice(undefined)` → `'—'`; `fmtPrice(3845)` →
  `'$38.45'`.
- `__tests__/PortfolioTile.test.jsx` (new, 2 examples): renders the known
  current value with no delta badge when the series is empty; renders the
  last series value with a delta once the series has points (regression).
- `__tests__/ItemsTile.test.jsx` (extended, +1 example): an item with
  `priceHistory: []` renders its price, no delta badge, and doesn't break
  rendering/sorting alongside items that do have history. `Harness` now
  accepts an `items` override prop (existing calls unaffected — default
  unchanged).
- `__tests__/useDashboardData.test.js` (rewritten, 4 examples): items
  render with real prices as soon as inventory resolves and before
  history resolves (`historyStatus: 'pending'`, empty `priceHistory`,
  correct `portfolio.currentValueCents`), then update again once history
  resolves (`historyStatus: 'ready'`); a history-fetch failure keeps
  items visible (`status` stays `'success'`, only `historyStatus` becomes
  `'error'`); an inventory-fetch failure is unchanged (full `status:
  'error'`); an empty inventory skips the history call entirely and sets
  `historyStatus: 'ready'` immediately (regression, extended with the new
  field).
- `__tests__/MarketVolumeTile.test.jsx` (new, 2 examples): pending state
  renders `'—'` instead of `0` (and, incidentally, doesn't crash — see
  Deviation above); ready state renders the real count.
- Regression: `portfolioSeries.test.js`, `filters.test.js`,
  `reducer.test.js`, `marketVolume.test.js` unchanged, all still passing.

Commands actually executed for every increment (RED → GREEN), and again
at the end, from `app_core/`:

```
npm test                                              # full suite
npx vitest run app/frontend/dashboard/__tests__/<file> # targeted, per step
```

## Verification

- **Full `app_core` frontend suite**: 48 examples, 0 failures (up from a
  39-example green baseline captured before any change) — 9 test files
  (3 new: `format.test.js`, `PortfolioTile.test.jsx`,
  `MarketVolumeTile.test.jsx`).
- **Linter/formatter**: none configured for this project's frontend (no
  `.eslintrc*`/`eslint.config*`/`.prettierrc*` found) — nothing to run.
- **Final diff review**: 9 files modified, 4 files created, all within or
  directly required by the plan's scope (see Deviation above for the one
  file not originally listed). No debug code, no unrelated changes.
- **Manual browser check**: not performed. Per the plan's Verification
  section this would require loading `/dashboard` against a live Steam
  OpenID login and a running `app_core`+`app_fetcher`+Postgres+Redis
  stack (bridge-token-authenticated, per `architecture-layers.md`), which
  isn't available in this environment — same limitation noted in the
  prior `fetcher-price-caching.md` implementation. The rewritten
  `useDashboardData.test.js` exercises the exact same two-stage state
  machine a real browser session would drive (real `fetch` timing via a
  manually-controlled deferred promise, not an instant mock), which is
  the closest available substitute.

## Remaining Issues

- Manual visual verification (no layout jump, correct pending→ready
  transition, `DashboardSkeleton`'s look) is unverified in a real
  browser — worth a quick look next time this can be run against the
  live stack.
- `changeCents`/`change_24h_cents` remains dead data on the mapped item
  object (per the plan's Out of Scope) — untouched.
- The pre-existing `Sparkline` empty-array crash (see Deviation) was
  fixed only for the `points.length === 0` case that this plan's own
  behavior newly makes reachable; no broader audit of `Sparkline`/
  `computePoints` for other malformed-input cases was performed, since
  none of them are reachable by anything this plan changes.
