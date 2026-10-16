---
status: implemented
app: core
goal: Stop the portfolio/item hero charts from drawing a green zero delta when there is no change to report (e.g. a single-point series)
created: 2026-10-16
---

## Applicable Styleguides

- **`agent/styleguides/core/react-dashboard.md`** — governs both hero
  components. Its Component Conventions (amended for this task) now own
  the hero-delta zero-hiding rule implemented here; its "what gets a
  dedicated test file" rule is why `PortfolioTile.test.jsx` gets the
  new cases and `PortfolioHeroTile` is covered through the
  `InventoryDetail` root-component integration test rather than a new
  file; its CSS-split rule keeps the `.hero-delta` classes in
  `tokens.css` untouched.
- **`agent/styleguides/ci-and-coverage.md`** — governs how the frontend
  checks in Verification are run (docker compose with the CI override, or
  the local `node_modules` for a quick run).

# Development Plan

## Goal

Apply the same "a `0` change must not read as green" rule from the item
rows to the hero/portfolio **charts**: when a hero chart has no actual
change to report — most visibly a single-point series, where `delta` and
`pct` are both `0` — the delta badge must not render at all, instead of a
green `▲ $0.00 (+0.00%)`.

## Expected Behavior

### Normal behavior

- `PortfolioTile` (dashboard hero, portfolio and item mode): when the
  series has a real change (`last - first !== 0`), the delta badge renders
  exactly as today (green `▲` for a rise, red `▼` for a fall).
- `PortfolioTile`: when there is **no** change — a single-point series, or
  a series whose last value equals its first — the badge is omitted and
  only the value is shown.
- `PortfolioHeroTile` (Inventory Detail hero): same — the badge renders
  only when `portfolio.changeCents !== 0`; `changeCents === 0` (a
  single-point history) shows the value alone.

### Edge cases

- A single-point series of any non-zero value still shows the value
  (`$…`), just no delta badge.
- The portfolio "estimating" branch is unchanged: it already shows no
  delta while there is no series.
- `itemHistoryStatus === 'pending'` behavior is unchanged (no delta, as
  today).
- A negative change still renders red `▼`; a positive change still renders
  green `▲` — only the exact `0` case changes.

### Must remain unchanged

- The hero charts themselves (`HeroChart`), the series/node shapes, the
  value formatting (`fmtUSD`/`fmtPrice`/`centsToUSD`).
- All data-loading hooks and the `hero-delta` CSS classes/colors.
- Item rows (`ItemRow`, `InventoryItemRow`, `TickerView`, `GridView`) —
  already fixed by `dashboard-flat-trend-fixed-height`.

## Scope

### In Scope

1. `dashboard/components/PortfolioTile.jsx`: gate `showDelta` on a
   non-zero `delta` (in addition to the existing tradability/has-data
   guards).
2. `inventories/components/PortfolioHeroTile.jsx`: render the delta only
   when `portfolio.changeCents !== 0`.
3. Tests covering the zero/single-point case in
   `dashboard/__tests__/PortfolioTile.test.jsx` and
   `inventories/__tests__/InventoryDetail.test.jsx`.
4. Amend `agent/styleguides/core/react-dashboard.md` to extend the
   zero-delta rule from "item rows" to hero/aggregate delta badges (the
   gap this task surfaces).

### Out of Scope

- `inventories/components/InventoryCard.jsx`'s `inv-delta` (an
  inventory-card delta, not a chart hero) — same visual class of bug, but
  a card, not a chart; left as-is.
- Any change to how the series/`change_cents` are produced on the backend
  (the frontend already receives `0` for a single point; the fix is purely
  presentational).
- Item-row trend logic — already handled.

## Implementation Approach

Both heroes already compute or receive a delta and derive the `is-up`/
`is-down` colour from its sign; neither guards against "there is no
delta". Add the guard at the existing `showDelta`/render decision:

- `PortfolioTile`: the component already has `const showDelta = isTradable
  && hasData` on line ~37; change it to also require `delta !== 0` (the
  `delta`/`first`/`last` values are already computed just above it).
- `PortfolioHeroTile`: it has no `showDelta` today; derive `const
  showDelta = portfolio.changeCents !== 0` next to the existing `up`
  boolean and wrap the `<span className="hero-delta …">` with it.

No new helper file: this is a single-component boolean, not a shared
derivation across islands (the item rows' shared `trendDirection` solved a
genuinely cross-island piece; here it's two one-line render guards).

## Files To Modify

- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx` — add
  `delta !== 0` to the `showDelta` guard.
- `app_core/app/frontend/inventories/components/PortfolioHeroTile.jsx` —
  derive and apply a `showDelta` guard.
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` —
  add single-point / zero-change cases.
- `app_core/app/frontend/inventories/__tests__/InventoryDetail.test.jsx` —
  add a zero-`change_cents` case asserting no `.hero-delta`.
- `agent/styleguides/core/react-dashboard.md` — extend the trend rule to
  hero deltas (see Scope item 4).

## Test Plan

Follow `react-dashboard.md`'s Testing conventions.

- **`dashboard/__tests__/PortfolioTile.test.jsx` (component)**:
  - portfolio mode, single-point series
    (`[{ at: 1, value: 15000 }]`) → value `$150.00` shown, no
    `.hero-delta`.
  - portfolio mode, multi-point series whose ends are equal
    (`[14000, 15000, 14000]`) → no `.hero-delta`.
  - keep the existing 2-point rising case asserting the delta is present.
  - item mode, single-point item history → no `.hero-delta`.
- **`inventories/__tests__/InventoryDetail.test.jsx` (integration)**:
  - a payload with `change_cents: 0` (single-point history) renders the
    total value and no `.hero-delta`.
  - the existing `change_cents: 12500` payload keeps rendering the delta
    (add an explicit assertion if missing).

## Implementation Steps

1. RED: add the single-point/zero-change assertions to
   `PortfolioTile.test.jsx` and the zero-`change_cents` assertion to
   `InventoryDetail.test.jsx`; confirm they fail because the badge is
   present.
2. GREEN: add the `delta !== 0` guard in `PortfolioTile.jsx`.
3. GREEN: add the `showDelta` guard in `PortfolioHeroTile.jsx`.
4. Amend `react-dashboard.md` (via `styleguides-check`/`update-styleguide`)
   to cover hero deltas.
5. Run the frontend suite, lint, and format checks.

## Verification

- `npm test` (full frontend suite).
- `npm run lint`.
- `npx prettier --check` on changed files.
- Ruby side untouched — no RSpec/Sorbet run.

## Risks

- Over-hiding: a genuinely flat multi-point series now shows no delta.
  This is intended (matches the item-row `0`-hides rule) and the user's
  explicit "while there's no delta, show nothing".
- `PortfolioHeroTile` relies on the backend sending `change_cents: 0`
  for a single-point history; if it instead sends a stale non-zero value,
  the badge would still show — acceptable, since the frontend only has
  the value it's given.

## Assumptions

- "No delta" means the computed change is exactly `0` (single point, or
  equal endpoints), not "the series is short" — a 2-point series with a
  real change still shows its delta.
- `PortfolioHeroTile`'s `changeCents` is the authoritative change signal
  for that card; `changePercent` is derived from it and need not be
  checked separately.

## Completion Criteria

- No hero chart renders a delta badge for a zero/absent change.
- Positive/negative deltas render exactly as before.
- New/changed tests pass; lint and format are clean.

# Implementation Summary

## Implemented

- **`dashboard/components/PortfolioTile.jsx`** — the hero `showDelta` gate
  now also requires `delta !== 0` (previously `isTradable && hasData`), so
  a single-point series or a series whose endpoints are equal renders the
  value with no `.hero-delta` badge.
- **`inventories/components/PortfolioHeroTile.jsx`** — added a
  `showDelta = portfolio.changeCents !== 0` guard and wrapped the
  `.hero-delta` span in it (it previously rendered unconditionally).
- **`agent/styleguides/core/react-dashboard.md`** — Component Conventions
  gained the hero-delta zero-hiding bullet; the frontmatter description
  and Canonical Implementations list were updated to match.

## Tests

- `dashboard/__tests__/PortfolioTile.test.jsx` — added: a single-point
  portfolio series shows `$150.00` and no `.hero-delta`; a series ending
  where it started shows no `.hero-delta`; a single-point item history
  shows no `.hero-delta`. The existing 2-point rising case still asserts
  the badge is present.
- `inventories/__tests__/InventoryDetail.test.jsx` — added a
  `change_cents: 0` payload test asserting the total value renders with no
  `.hero-delta`, and added an explicit `toHaveClass('is-up')` assertion to
  the existing non-zero payload test so the positive path stays locked.

TDD: the four new assertions were written first and confirmed RED
(the green `▲ $0.00 (+0.00%)` badge rendered) before the two guards made
them GREEN.

Commands actually executed (from `app_core`, local `node_modules`):

- `npx vitest run app/frontend/dashboard/__tests__/PortfolioTile.test.jsx app/frontend/inventories/__tests__/InventoryDetail.test.jsx`
- `npm test` (full suite)
- `npm run lint`
- `npx prettier --check <changed files>`

## Verification

- `npm test`: **41 test files, 246 tests, all passing**.
- `npm run lint`: 0 errors; the same pre-existing
  `react-hooks/exhaustive-deps` warning in the untouched
  `tracked_items/TrackedItems.jsx`.
- `npx prettier --check` on all four changed files: clean.
- Ruby side untouched, so no RSpec/Sorbet run was performed.

## Deviations

- None from the plan. No new shared helper was introduced (the plan
  explicitly decided against it): the hero guard is a per-component
  one-line boolean, not a cross-island derivation.

## Remaining Issues

- None blocking.
- `inventories/components/InventoryCard.jsx`'s `inv-delta` still colours a
  `0` change green — it's a card, not a chart hero, and was left out of
  scope by the plan (the user asked specifically about the charts).
