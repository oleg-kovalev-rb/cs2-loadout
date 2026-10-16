---
status: implemented
app: core
goal: Stop zero-trend item rows from reading as "up" (green) and keep the dashboard Items tile a fixed 8-row height on partial pages
created: 2026-10-16
---

## Applicable Styleguides

- **`agent/styleguides/core/react-dashboard.md`** — governs every
  frontend part of this plan. Its Structure/Reuse rules place the shared
  `trendDirection` helper in `app/frontend/shared/utils/` (two islands
  need it verbatim); its Derived Data rule requires that pure derivation
  to be a `utils/` function rather than inline in a render body; its
  Component Conventions (amended for this change) now own the
  `up`/`down`/`flat` trend rule and the fixed-height-list/decorative-
  placeholder rule the plan implements; its Testing section fixes where
  the new tests live and their shape (pure `.test.js` for the helper,
  component/real-reducer tests for the rows and `ItemsTile`); its
  "what gets a dedicated test file" rule is why `Sparkline` itself gets
  no new test file.
- **`agent/styleguides/ci-and-coverage.md`** — governs Verification: the
  frontend checks (`vitest`, `eslint`, `prettier --check`) must be run
  through `docker compose` using the `docker-compose.ci.yml` override, not
  the base compose file whose bind mount shadows the image's
  `node_modules`; `app_core/bin/ci` (which runs exactly `npm run lint` /
  `npm run format:check` / `npm run test:coverage`) is the local
  everything runner.

Note: no `agent/styleguides/fix_me.md` entry was left behind by this
change — the `tracked_items` item rows (`TickerView.jsx`, `GridView.jsx`)
that also inlined the old `pct >= 0 ? 'up' : 'down'` check were brought
into compliance with the new rule instead of being logged as deviations.

# Development Plan

## Goal

Two visual-polish fixes on the dashboard's right-hand Items tile
(`app_core/app/frontend/dashboard/`), with the zero-trend half also
applied to the Inventory Detail page's item list:

1. An item whose 24h change is `0` (or has no change data) must no longer
   be presented as a green "up" signal. Exactly as decided with the user:
   the `▲ 0.0%` delta badge is **hidden** for a flat trend, and the row's
   sparkline is drawn in a neutral grey instead of `--up` green, so a flat
   row no longer "glows green".
2. The Items tile's list must always occupy **`PAGE_SIZE = 8` rows' worth
   of height**, even when the current (usually last) page holds fewer than
   8 items — the missing slots render as empty, non-focusable rows instead
   of the tile collapsing to the item count.

## Expected Behavior

### Normal behavior

- An item row with `change24hPercent > 0` renders as today: green `▲
  x.x%` delta, green sparkline.
- An item row with `change24hPercent < 0` renders as today: red `▼ x.x%`
  delta, red sparkline.
- An item row with `change24hPercent === 0` (or a missing/`null` change)
  renders **no delta badge at all** (no `▲`/`▼`), and its sparkline uses a
  neutral grey stroke (not `--up`/`--down`).
- Items within a pricing-agnostic page sort/order are unchanged; the flat
  case still sorts as `0` in `delta_desc`/`delta_asc`.
- On the dashboard Items tile, a page with `n` real items (`1 <= n < 8`)
  renders `n` real rows followed by `8 - n` empty placeholder rows, so the
  tile's height is identical to a full 8-item page. Navigation between
  pages does not resize the tile.
- Pagination text (`"1–n of total"`) is unaffected by placeholders.

### Edge cases

- A page with exactly 8 items renders zero placeholders.
- Filtering down to fewer items (e.g. 2) on the dashboard pads to 8 slots
  the same way a partial last page does.
- An item that is unpriced (`currentPriceCents == null`) keeps today's
  behavior: `—` price, no delta badge — unchanged.
- An item with `currentPriceCents === 0` (not tradable) keeps today's
  behavior: no delta badge — unchanged.
- Placeholder rows are purely decorative: they must not be reachable by
  assistive tech or focus, and must not count as list items in tests
  (`getAllByRole('listitem')` must still return only the real rows).
- The existing filter-to-zero state (`"No items match these filters."`)
  is **not** padded — the empty-state message is a distinct UX and is left
  as-is (see Out of Scope).

### Must remain unchanged

- All data-loading hooks (`useDashboardData`, `useItemPrices`,
  `useItemTrend`, `useInventoryDetail`) and the reducer actions.
- Pricing, sorting, filtering, and pagination logic.
- The sparkline's shape/geometry, and its existing `up`/`down`/`volume`
  colors.
- The Inventory Detail page's list height (only its flat-trend rendering
  changes; the "fixed 8 rows" requirement is dashboard-specific).

## Scope

### In Scope

1. Extract the piecewise trend direction into a pure, shared helper and
   have it return a distinct `flat` state (`up | down | flat`) instead of
   collapsing `0` into `up`.
2. Dashboard `ItemRow`: use the helper; hide the delta badge for `flat`;
   pass `flat` to `Sparkline`.
3. Inventory Detail `InventoryItemRow`: same flat handling (this is the
   "Dashboard + Inventory Detail" scope the user chose for the trend fix).
4. Tracked Items `TickerView`/`GridView` item rows: same flat handling —
   brought in so neither needs a `fix_me.md` entry (the change is the same
   one-line swap, and the rule already covers every island's item row).
5. `Sparkline`: support a `flat` variant rendered in a neutral grey.
6. Dashboard `ItemsTile`: pad the visible page to `PAGE_SIZE` with
   decorative placeholder rows.
7. Tests for the helper, all four row components, and the tile padding.

### Out of Scope

- The same `>= 0 ? 'up' : 'down'` zero-bug in aggregate (non-item-row)
  components the user did not name:
  `inventories/components/InventoryCard.jsx` (a per-inventory delta) and
  the dashboard hero `PortfolioTile.jsx`'s `hero-delta` (a portfolio
  aggregate). The trend rule was deliberately scoped to item rows, so it
  doesn't cover these; leaving them is a scope decision, not a logged
  deviation.
- Padding the Inventory Detail `TopItemsList` to its `ITEMS_PER_PAGE = 12`
  — the user's fixed-height request was specifically about the dashboard's
  8-item right block.
- The zero-items empty state (message stays as-is; no padding).
- Any backend/API change — this is presentation-only.
- Redesigning the delta badge for very small non-zero changes (e.g.
  `0.04%` shown as `0.0%`); only an exact `0`/missing change is treated as
  flat.

## Implementation Approach

**Flat trend as a shared pure function.** The styleguide requires any
computation over raw data to live in a pure `utils/` function, not inline
in a render body — and the current inline `pct >= 0 ? 'up' : 'down'` in
`ItemRow.jsx`/`InventoryItemRow.jsx` is exactly such a computation. Because
two different islands (dashboard, inventories) need the identical rule, it
belongs in `app/frontend/shared/utils/trend.js` (the styleguide's
"second consumer moves it to `shared/`" test), returning `'up' | 'down' |
'flat'`. `'flat'` covers `pct === 0`, `null`, `undefined`, and `NaN`.

**Row components.** Both `ItemRow` and `InventoryItemRow` derive
`direction = trendDirection(pct)`; the delta badge is rendered only when
`direction !== 'flat'` (and the existing price/tradability guards still
hold); the arrow is `direction === 'up' ? '▲' : '▼'`; the sparkline gets
`variant={direction}`. This keeps the delta's `up`/`down` CSS classes and
adds no `flat` delta class (the badge never renders flat).

**Sparkline.** Add a `flat` branch to the color map
(`variant === 'flat' ? 'var(--text-muted)' : ...`) so a flat trend line is
neutral grey rather than `--up` green. Geometry is untouched.

**Tile padding.** `ItemsTile` already computes `pageItems` from the sorted
slice. Compute `placeholders = Math.max(0, PAGE_SIZE - pageItems.length)`
and, after the real rows, render that many `<li>` slots carrying the row
class (`.mover-row mover-row-empty`) plus a `.mover-icon` span — reusing
the same-class placeholder idea the component conventions already mandate
for a missing `iconUrl`, which makes each placeholder exactly the row's
`64px + 2*9px` footprint without hard-coding a pixel height. Mark each
placeholder `aria-hidden="true"` so it is neither announced nor counted as
a list item (`getAllByRole('listitem')` in the existing tests keeps
returning only real rows). Padding applies only when `totalCount > 0`; the
empty-state branch is untouched.

## Files To Modify

- `app_core/app/frontend/dashboard/components/ItemRow.jsx` — replace the
  inline `pct >= 0` direction/arrow with `trendDirection(pct)`; gate
  `showDelta` on a non-flat direction; pass `direction` to `Sparkline`.
  Reason: fix 1, dashboard side.
- `app_core/app/frontend/inventories/components/InventoryItemRow.jsx` —
  same flat handling. Reason: fix 1, Inventory Detail side.
- `app_core/app/frontend/tracked_items/components/TickerView.jsx` and
  `GridView.jsx` — same flat handling on their item rows. Reason: fix 1
  applied across every island's item row, so no `fix_me.md` entry is
  needed for either.
- `app_core/app/frontend/shared/components/Sparkline.jsx` — add the
  `flat` variant color. Reason: a flat row must not draw a green line.
- `app_core/app/frontend/dashboard/components/ItemsTile.jsx` — pad
  `pageItems` up to `PAGE_SIZE` with decorative placeholder rows. Reason:
  fix 2.
- `app_core/app/frontend/shared/styles/tokens.css` — no new rule strictly
  required (the placeholder reuses `.mover-row`/`.mover-icon`); only if
  implementation finds the bare `li.mover-row` needs an explicit
  `pointer-events: none` / `list-style: none` guard, add a minimal
  `.mover-row-empty` rule next to the existing `.mover-row` block. Reason:
  keep the decorative row inert.
- `app_core/app/frontend/dashboard/__tests__/ItemRow.test.jsx` — add
  flat/down/missing-change coverage. Reason: verify fix 1.
- `app_core/app/frontend/inventories/__tests__/InventoryItemRow.test.jsx`
  — add flat coverage. Reason: verify fix 1 on the second consumer.
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx` — add
  padding coverage. Reason: verify fix 2, and protect the existing
  real-row assertions.

## Files To Create

- `app_core/app/frontend/shared/utils/trend.js` — exports the pure
  `trendDirection(pct)` (`'up' | 'down' | 'flat'`). Necessary because the
  rule is shared by every island's item row (dashboard, inventories,
  tracked_items) and the styleguide forbids inlining the derivation.
- `app_core/app/frontend/shared/__tests__/trend.test.js` — pure unit test
  of `trendDirection` (positive, negative, `0`, `null`, `undefined`,
  `NaN`). Necessary because pure `utils/` functions get dedicated
  no-rendering unit tests.

## Test Plan

Follow `react-dashboard.md`'s Testing conventions: explicit
`import { describe, test, expect } from 'vitest'`, flat `__tests__/`
directories, `.test.js` for pure functions, `.test.jsx` for anything that
renders.

- **`shared/__tests__/trend.test.js` (pure unit, `.test.js`)**:
  `trendDirection(2.5) === 'up'`, `(-1.2) === 'down'`, `0 === 'flat'`,
  `null === 'flat'`, `undefined === 'flat'`, `NaN === 'flat'`.
- **`dashboard/__tests__/ItemRow.test.jsx` (component)**:
  - positive `change24hPercent` → `.mover-delta` present, class `up`,
    text contains `▲`.
  - negative → `.mover-delta` present, class `down`, text contains `▼`.
  - `0` → no `.mover-delta` in the row, and the sparkline `path`'s `stroke`
    is the neutral `var(--text-muted)` (assert via the SVG path attribute).
  - missing/`null` `change24hPercent` → no `.mover-delta`.
  - unpriced item (`currentPriceCents: null`) behavior unchanged (existing
    coverage stays).
- **`inventories/__tests__/InventoryItemRow.test.jsx` (component)**:
  - keep the existing up-delta test; add a `change24hPercent: 0` case
    asserting no `.mover-delta`, and (minimally) that the sparkline is not
    green.
- **`tracked_items/__tests__/TrackedItems.test.jsx` (integration)**:
  - a priced item with `change_24h_percent: 0` renders no `▲`/`▼` delta in
    both the Ticker and the Grid view, and its sparkline line path strokes
    `var(--text-muted)` (explicitly the last path there, since the grid
    sparkline's `showArea` puts a `stroke="none"` area path first).
- **`dashboard/__tests__/ItemsTile.test.jsx` (integration, real
  reducer harness)**:
  - with the existing 5-item fixture, assert
    `container.querySelectorAll('.mover-row-empty')` is `3` and
    `getAllByRole('listitem')` is still `5` (placeholders excluded from the
    accessibility tree) — proving the tile renders 8 row slots without
    changing the real-row count.
  - with a fixture of exactly `PAGE_SIZE` (8) items, assert zero
    `.mover-row-empty` slots.
  - keep the existing filter/sort/paginate assertions passing unchanged
    (they must remain green, since the real-row count and pager text are
    unaffected by padding).
- No dedicated test for `Sparkline` itself (`react-dashboard.md` lists it
  among components with no test file today); its new `flat` color is
  covered through the four row-component tests.

## Implementation Steps

1. Add `shared/utils/trend.js` with `trendDirection`, and its unit test
   (RED first: test written against the not-yet-existing module).
2. Wire `ItemRow.jsx` to `trendDirection`, hiding the delta for `flat`
   and passing the direction through; update/extend `ItemRow.test.jsx`.
3. Wire `InventoryItemRow.jsx` the same way; extend
   `InventoryItemRow.test.jsx`.
4. Wire `TickerView.jsx`/`GridView.jsx` the same way; extend
   `TrackedItems.test.jsx` (ticker + grid flat cases).
5. Add the `flat` color branch to `Sparkline.jsx`.
6. Add placeholder padding to `ItemsTile.jsx`; extend `ItemsTile.test.jsx`
   with the placeholder-count and full-page assertions, and confirm the
   existing accessibility-role assertions still hold.
7. Only if needed, add a minimal `.mover-row-empty` rule in
   `tokens.css`; otherwise leave the stylesheet untouched.
8. Run the frontend test suite, lint, and format checks (see
   Verification) and fix any fallout.

## Verification

Run the frontend checks through `docker compose` with the CI override, per
`agent/styleguides/ci-and-coverage.md` (never against the base
`docker-compose.yml`, whose bind mount shadows the image's `node_modules`),
e.g. `docker compose -f docker-compose.yml -f docker-compose.ci.yml run
--rm app_core npm test`:

- `npm test` (`vitest run`) — full suite, since `Sparkline` and
  `tokens.css` are shared and the row components are reused across
  `dashboard/` and `inventories/`.
- `npm run lint` (`eslint app/frontend`) — must stay clean.
- `npm run format:check` (`prettier --check app/frontend`) — new/changed
  files must pass; run `npm run format` rather than hand-formatting. (Note:
  `inventories/InventoriesIndex.jsx` is already flagged red in
  `agent/styleguides/fix_me.md` for `prettier --check`; that pre-existing
  warning is not caused by, and not fixed by, this change.)
- `app_core/bin/ci` is the local everything-runner equivalent; running just
  the three frontend steps above is sufficient for this frontend-only
  change, but `bin/ci` is a valid superset if a single "all green" run is
  preferred.
- If the app is runnable in this environment, a manual/visual check that a
  partial last page keeps the Items tile at full height and that a
  zero-change row shows neither a green delta nor a green sparkline.
- `app_core`'s Ruby side is untouched, so no RSpec/Sorbet run is required
  for this change (stated explicitly rather than omitted).

## Risks

- **Placeholder rows must not be counted as list items.** The existing
  `ItemsTile.test.jsx` asserts `getAllByRole('listitem')` lengths; if
  `aria-hidden="true"` is not enough to exclude a `<li>` from the role
  query under jsdom, the fallback is `role="presentation"` (or updating
  the assertions to count only real rows). This is verified in step 5
  before proceeding.
- **Placeholder height must match a real row.** Reusing `.mover-icon`
  inside a `.mover-row` keeps the `64px + 18px` footprint self-maintaining;
  if a bare `li.mover-row` collapses in practice, add an explicit
  `.mover-row-empty { min-height: ... }` (or the same icon span) rather
  than a magic pixel value on `.items-list`.
- **Responsive interaction.** At `<= 920px` the list is clamped to
  `max-height: 420px` (`dashboard.css`); placeholders simply become part of
  the scrollable content there, which is the desired behavior — no extra
  media-query work expected, but worth a look during visual verification.
- **Scope discipline.** The helper is applied to every item row
  (`ItemRow`, `InventoryItemRow`, `TickerView`, `GridView`); resist also
  rewriting the aggregate deltas `InventoryCard`/`PortfolioTile` (explicitly
  Out of Scope).

## Assumptions

- "Trend 0" means `change24hPercent` is exactly `0` or absent from a
  priced item — the two cases that currently render `▲ 0.0%` in green via
  `changePct`'s `|| 0` fallback. Very small non-zero changes keep their
  `up`/`down` treatment.
- The user's "fixed at 8" is satisfied by rendering empty slots on any
  partial page, and the zero-items empty state may keep its current
  single-message rendering (not padded).
- Neutral grey for a flat sparkline is `--text-muted` (the lighter of the
  two existing grey tokens), chosen for visibility on the dark surface; the
  user's "grey or white" left this open.

## Completion Criteria

- Flat-trend rows render no delta badge and a neutral sparkline on both
  the dashboard and Inventory Detail pages.
- The dashboard Items tile is the same height for any page with 1–8 items.
- New/changed tests pass, `npm run lint` is clean, and `format:check`
  passes for every touched file.
- No changes outside the files listed above.

# Implementation Summary

## Implemented

- **Shared flat-trend helper.** New
  `app/frontend/shared/utils/trend.js` exports `trendDirection(pct)` →
  `'up' | 'down' | 'flat'`, treating `0`, `-0`, `null`, `undefined`, and
  `NaN` as `flat` (via `if (!pct) return 'flat'`).
- **Dashboard `ItemRow`** now derives `direction = trendDirection(pct)`;
  the delta badge is gated on `direction !== 'flat'` (so a `0`/missing
  change shows no `▲ 0.0%`), and the sparkline receives `variant={direction}`.
- **Inventory Detail `InventoryItemRow`** got the same treatment
  (`direction`, a `showDelta` gate replacing the bare `hasPrice` gate).
- **Tracked Items `TickerView`/`GridView`** got the same treatment on their
  item rows (`TickerRow`, `ItemCard`), so both islands' rows share the one
  rule and neither needs a `fix_me.md` entry.
- **`Sparkline`** gained a `flat` variant that strokes the line with
  `var(--text-muted)` instead of the green `var(--up)`.
- **Dashboard `ItemsTile`** now pads a partial page up to `PAGE_SIZE` (8)
  with inert placeholder rows (`<li className="mover-row mover-row-empty"
  aria-hidden="true">` containing a `.mover-icon` span), so the tile keeps
  a full 8-row height. The zero-items empty state is unchanged.
- **`tokens.css`** — added a `.mover-row-empty { pointer-events: none; }`
  rule so the empty slots don't inherit `.mover-row`'s hover highlight and
  aren't interactable.

## Tests

Changed/created (all vitest, `app_core/app/frontend/`):

- `shared/__tests__/trend.test.js` (new, pure `.test.js`) —
  `trendDirection` for positive, negative, `0`, `-0`, `null`,
  `undefined`, `NaN`.
- `dashboard/__tests__/ItemRow.test.jsx` — added up/down delta tests,
  a zero-change test (no `.mover-delta`, sparkline stroke
  `var(--text-muted)`), and a missing-change test.
- `inventories/__tests__/InventoryItemRow.test.jsx` — added a down-delta
  test and the same zero-change test.
- `tracked_items/__tests__/TrackedItems.test.jsx` — added a priced
  zero-change item test for both the Ticker and the Grid view (no `▲`/`▼`
  delta; the sparkline's line path strokes `var(--text-muted)` — the last
  path, since the grid sparkline's `showArea` emits a `stroke="none"` area
  path first).
- `dashboard/__tests__/ItemsTile.test.jsx` — added a "fixed-height list"
  describe: a 5-item page renders `PAGE_SIZE - 5 == 3`
  `.mover-row-empty` slots while `getAllByRole('listitem')` stays 5 (the
  placeholders are `aria-hidden`), and a full 8-item page renders zero
  placeholders.

TDD: every test above was written first and confirmed RED for the
expected reason (missing module / delta present / zero placeholders)
before the corresponding change made it GREEN.

Commands actually executed (from `app_core`, `node_modules` present
locally):

- `npx vitest run app/frontend/shared/__tests__/trend.test.js`
- `npx vitest run app/frontend/dashboard/__tests__/ItemRow.test.jsx`
- `npx vitest run app/frontend/inventories/__tests__/InventoryItemRow.test.jsx`
- `npx vitest run app/frontend/dashboard/__tests__/ItemsTile.test.jsx`
- `npx vitest run app/frontend/tracked_items/__tests__/TrackedItems.test.jsx`
- `npm test` (full suite)
- `npm run lint`
- `npx prettier --check <changed files>` / `npx prettier --write` the two
  test files that needed it
- `npm run format:check`

## Verification

- `npm test`: **41 test files, 242 tests, all passing** (full frontend
  suite; run after the Prettier pass).
- `npm run lint` (`eslint app/frontend`): **0 errors**, 1 warning in
  `tracked_items/TrackedItems.jsx` (`react-hooks/exhaustive-deps`) — a
  pre-existing warning this change does not introduce.
- `npx prettier --check` on every changed/new file: clean.
- `npm run format:check` (whole `app/frontend`): red only on
  `inventories/InventoriesIndex.jsx`, the pre-existing deviation already
  logged in `agent/styleguides/fix_me.md`; none of this change's files are
  flagged.
- Ruby side untouched, so no RSpec/Sorbet run was performed (as the plan's
  Verification states).

## Deviations

- The plan listed the `.mover-row-empty` CSS rule as "only if needed".
  It was needed: without `pointer-events: none`, the empty slots inherit
  `.mover-row:hover`'s `background: var(--surface-raised)` and light up on
  hover, which neither the plan nor the tests would have caught. Added the
  minimal rule to `tokens.css`.
- **Scope grew to `tracked_items` item rows.** The plan had left
  `TickerView.jsx`/`GridView.jsx` Out of Scope and logged them in
  `fix_me.md`. The user rejected that: the swap to `trendDirection` is the
  same trivial change already applied here, and `fix_me.md` is not the
  place for it. Both were brought into compliance, their flat cases are now
  covered in `TrackedItems.test.jsx`, and the `fix_me.md` entry was
  deleted. `InventoryCard.jsx` and `PortfolioTile.jsx` remain out of scope
  — they render an aggregate delta, not an item row, so the (item-row-
  scoped) trend rule does not cover them.

## Remaining Issues

- None blocking.
- No browser-level manual check was performed in this environment (the
  first-run Steam/OAuth data needed for a live dashboard isn't available
  here); the padding's height parity and the flat grey are covered by the
  component tests instead.
