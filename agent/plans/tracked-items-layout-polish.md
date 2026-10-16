---
status: implemented
app: core
goal: Polish the Tracked Items page layout — cap the grid at 5 columns, make ticker rows taller with bigger icons, and drop the default page size to 20
created: 2026-10-16
---

# Development Plan

## Goal

Three layout fixes on the public Tracked Items catalog
(`app_core/app/frontend/tracked_items/`):

1. **Verify** the "Gaining today / Losing today" stat tiles actually work
   (the user reports them "not showing").
2. **Fix the grid view** so the item cards no longer leave an ugly
   single-card last row on wide screens (today 25 items render as 4 rows
   of 6 + 1 on a ≥1920px viewport).
3. **Enlarge the ticker rows** (row height + item image) and **reduce the
   default page size to 20** so the taller rows stay comfortable.

## Expected Behavior

### Normal behavior

- **Stat tiles** — unchanged code; verified to work. The three tiles
  (`Items tracked` / `Gaining today` / `Losing today`) render the API's
  `meta.total_count` / `gaining_count` / `losing_count`.
- **Grid view** — at the page's maximum content width the card grid shows
  at most **5 columns**, so the default 20-item page lays out as 4 even
  rows of 5 with no lone trailing card. Narrower viewports keep reducing
  the column count via the existing `auto-fill` behavior.
- **Ticker view** — each row is visibly taller and its item image is
  larger (roughly 38×38px → ~52×52px, row ~56px → ~76px), so the skin
  artwork reads better. The sparkline/rarity/category columns keep their
  current widths.
- **Per page** — the pager's "Per page" select offers `20 / 40 / 100`
  and defaults to `20`; every option is divisible by 5 and 4, so it stays
  clean at the grid's common column counts.

### Edge cases

- A viewport wide enough for exactly 5 grid columns with a 20-item page
  → 4 full rows, no partial row.
- Switching Ticker ↔ Grid with a 20-item page re-renders the same 20
  items in the other layout (unchanged behavior).
- Changing "Per page" still resets to page 1 and re-fetches with the new
  `per_page` (unchanged behavior, new values).
- A "Per page" value the server clamps (e.g. >100) is out of scope — the
  options never exceed 100, matching the existing server clamp.

### Must remain unchanged

- The stat strip's markup, labels, and `meta`→camelCase mapping — no code
  change is made for item 1.
- All data loading (`useItemsCatalog`), the reducer's action set, filters,
  sort, view toggle, and the sparkline/rarity/price rendering.
- `app_fetcher`'s `/api/public/items` response shape, params, clamp, and
  cache — `per_page` is already a caller-supplied param, so no backend
  change is needed.
- The dashboard, inventories, and admin-panel islands.

## Scope

### In Scope

- Cap the grid at 5 columns (`minmax(216px, 1fr)` → `minmax(240px, 1fr)`
  in `tracked_items.css`), which is the only change needed to stop the
  6-column/1-leftover layout at the page's 1440px max width.
- Enlarge ticker row height, ticker icon size, and the ticker grid's first
  (icon) column to match.
- Change the default `perPage` from 25 to 20 and the pager options from
  `[25, 50, 100]` to `[20, 40, 100]`.
- Update the affected Vitest expectations.

### Out of Scope

- Any change to the "Gaining today / Losing today" tiles — the user chose
  to leave them as-is (verified working; showing 0 only because the dev
  catalog currently has no non-zero 24h changes).
- A fixed-column-count grid with hand-tuned breakpoints — the user chose
  the simpler "max 5 columns via `minmax`" approach. A narrow (~750–1000
  content px) band can still fall to 3 columns and leave a partial last
  row; that is accepted rather than adding breakpoint complexity.
- Changing grid card icon height or any other grid-card internals.
- Any backend/API change.
- Any restyle of the stat strip.

## Implementation Approach

**Item 1 — verification only.** A browser check plus direct API call
already confirmed the tiles render (`GAINING TODAY ▲ 0` /
`LOSING TODAY ▼ 0`) and that `/api/public/items` returns
`gaining_count`/`losing_count`. The zeros come from the data: all 62 items
in the dev DB have `change_24h_cents = 0` (the price-update service sets a
non-zero change only when a ~24h-old price log exists). No code change;
this is recorded here so the finding survives.

**Item 2 — one CSS value.** `.dash-root .grid-view` uses
`repeat(auto-fill, minmax(216px, 1fr))`. `.dash-root` is capped at
`max-width: 1440px` with `32px` side padding, so the largest possible
content width is `1376px`; at 6 × 216px + 5 × 14px gap = 1366px the sixth
column fits at the widest viewports, which is what produces the 4×6+1
layout for 25 items. Raising the minimum to `240px` makes the widest grid
5 columns (5 × 240 + 4 × 14 = 1256 ≤ 1376; 6 × 240 + 5 × 14 = 1510 >
1376), so a 20-item page is exactly 4 rows of 5. `auto-fill` still thins
the grid on narrower viewports with no new breakpoints.

**Item 3 — shared `perPage` change + ticker sizing.** `perPage` is one
piece of reducer state consumed by both views, so the "fewer items"
change is a single default swap (`reducer.js`) plus the option list
(`CatalogPagination.jsx`). Keeping the options at multiples of both 5 and
4 (`20/40/100`) means every grid column count the page actually produces
(5 or 4 at desktop widths, 2 on small screens) divides the page size
evenly. The ticker row/icon are tuned purely in `tracked_items.css`:
the icon grows, the row's vertical padding grows, and the ticker grid's
first column (shared by `.ticker-head` and `.ticker-row`) widens to hold
the larger icon.

## Files To Modify

- `app_core/app/frontend/tracked_items/reducer.js` — change
  `initialState.perPage` from `25` to `20`. Reason: new default page size.
- `app_core/app/frontend/tracked_items/components/CatalogPagination.jsx`
  — change `PER_PAGE_OPTIONS` from `[25, 50, 100]` to `[20, 40, 100]`.
  Reason: options must match the new default and stay grid-friendly.
- `app_core/app/frontend/tracked_items/styles/tracked_items.css` —
  (a) `.grid-view` `minmax(216px, 1fr)` → `minmax(240px, 1fr)` (cap at 5
  columns); (b) `.ticker-icon` `38px` → `52px` square; (c) `.ticker-row`
  padding `9px 10px` → `12px 10px`; (d) the first column of both
  `.ticker-head` and `.ticker-row` `48px` → `56px`. Reason: sizes the
  grid and the taller ticker rows/icons.
- `app_core/app/frontend/tracked_items/__tests__/reducer.test.js` —
  assert `initialState.perPage === 20`. Reason: default changed.
- `app_core/app/frontend/tracked_items/__tests__/TrackedItems.test.jsx` —
  update the fixture's `meta.per_page` to `20` and switch the per-page
  test to select `40` (expecting `per_page=40`). Reason: option list and
  default changed.

## Files To Create

None.

## Test Plan

- **`reducer.test.js`** — `initialState.perPage` is `20` (the one changed
  assertion; all other reducer tests are unaffected).
- **`TrackedItems.test.jsx`** — the existing composite test that drives
  the per-page select: update the chosen option to `40` and assert the
  refetch URL carries `per_page=40` and `page=1`. Update the shared
  `catalogBody` fixture's `meta.per_page` to `20` so the pager's
  controlled value matches a real option.
- **No new dedicated test** for `CatalogPagination` or the CSS — it stays
  a pure presentational leaf (per `react-dashboard.md`'s "what gets a
  dedicated test file"), exercised through the composite test. CSS-only
  changes (grid cap, ticker sizing) are covered by manual browser
  verification, as the suite has no CSS assertions today.

## Implementation Steps

1. `reducer.js`: `initialState.perPage` `25` → `20`.
2. `CatalogPagination.jsx`: `PER_PAGE_OPTIONS` `[25, 50, 100]` →
   `[20, 40, 100]`.
3. `tracked_items.css`: bump `.grid-view` minmax to `240px`; bump
   `.ticker-icon` to `52px`, `.ticker-row` padding to `12px 10px`, and the
   ticker grid's first column to `56px` (both `.ticker-head` and
   `.ticker-row`).
4. Update `reducer.test.js` and `TrackedItems.test.jsx` expectations.
5. Run the Vitest suite and the lint/format checks.
6. Manual browser verification: at a ≥1920px viewport confirm the grid is
   5 columns (20 items = 4 rows, no lone card); confirm ticker rows are
   taller with larger icons; confirm the "Per page" select shows 20 by
   default and offers 40/100.

## Applicable Styleguides

- **`agent/styleguides/core/react-dashboard.md`** — governs every
  frontend part of this plan. Its Styling section fixes the CSS split (the
  grid/ticker changes stay in the island's own
  `tracked_items/styles/tracked_items.css`, built on the shared
  `shared/styles/tokens.css` custom properties rather than redefining
  them); its Component Conventions / "what gets a dedicated test file"
  sections are why `CatalogPagination` gets no new dedicated test
  (presentational leaf, exercised through the composite test) and why the
  reducer default change is verified in `reducer.test.js`; its Reuse
  Across Islands rule is why this stays island-local rather than touching
  `shared/`; its Testing section fixes where the updated tests live and
  their shape.
- **`agent/styleguides/ci-and-coverage.md`** — governs Verification: the
  frontend checks (`vitest`, `eslint`, `prettier --check`) must be run
  through `docker compose` using the `docker-compose.ci.yml` override (or
  the equivalent `app_core/bin/ci`), not the base compose file whose bind
  mount shadows the image's `node_modules`.
- **`agent/adr/core/multiple-react-islands.md`** — consulted: this change
  stays entirely within the existing `tracked_items/` island (its reducer,
  its pagination component, its stylesheet); no cross-island state or new
  sibling island is introduced, consistent with the ADR.
- **`agent/styleguides/git-commits.md`** — applies at commit time during
  `implement-plan` (the `[Scope] Imperative summary` convention), not to
  the plan's content itself.
- **`agent/styleguides/fix_me.md`** — checked; none of the files this plan
  touches (`reducer.js`, `CatalogPagination.jsx`, `tracked_items.css`,
  `reducer.test.js`, `TrackedItems.test.jsx`) is listed as a known
  deviation.

## Verification

- `npm run test` (or `npx vitest run app/frontend/tracked_items`) —
  all tracked_items tests pass. Run through the CI compose override per
  `ci-and-coverage.md` (below).
- `npm run lint` and `npm run format:check` from `app_core/` — clean.
- Manual browser check (the project's preview workflow) at a wide
  viewport: grid = 5 columns / 4 rows for the default 20-item page;
  ticker rows taller with larger artwork; pager default `20`.
- No Ruby/Sorbet change, so no Ruby-side checks are required.

## Risks

- **Grid column count vs. content width.** `auto-fill` depends on the
  live content width, so a mid-width viewport (~750–1000px content) can
  fall to 3 columns and leave a partial last row. Accepted per the chosen
  approach; 20/40/100 were selected to keep the common 5-/4-column counts
  exact.
- **Ticker first-column width must track the icon size.** `.ticker-head`
  and `.ticker-row` share the same `grid-template-columns`; both must be
  updated together or the header labels drift out of alignment with the
  row cells.
- **Per-page select is driven by the server's echoed `per_page`.** The
  select's value comes from `data.meta.perPage`, so the option list must
  continue to include whatever the server echoes (20/40/100) or the
  control renders blank.

## Assumptions

- The user's wide-screen report ("4 rows of 6 + 1") corresponds to a
  ≥1920px viewport, where `.dash-root`'s 1440px cap plus the current
  `minmax(216px, 1fr)` yields 6 columns — confirmed by reproducing the
  5-column case at a 1440px viewport and by the width arithmetic.
- 20 is a suitable default for both views (the user's own suggestion);
  taller ticker rows plus a 20-item page is the intended combination.

## Completion Criteria

- Desired behavior, scope, affected files, test strategy, and steps are
  explicit above.
- Plan is written to `agent/plans/tracked-items-layout-polish.md`.
- Proceed to `styleguides-check`, then `implement-plan`.

# Implementation Summary

## Implemented

- **Gaining/Losing verification (item 1)** — no code change. Verified in a
  real browser and via the API: `/tracked-items` renders
  `GAINING TODAY ▲ 0` / `LOSING TODAY ▼ 0`, and
  `GET /api/public/items` returns `gaining_count`/`losing_count`. The zeros
  are data-driven: every item in the dev DB has `change_24h_cents = 0`
  (62/62), because the price-update service only sets a non-zero change
  when a ~24h-old price log exists.
- `app_core/app/frontend/tracked_items/reducer.js` — `initialState.perPage`
  `25` → `20`.
- `app_core/app/frontend/tracked_items/components/CatalogPagination.jsx` —
  `PER_PAGE_OPTIONS` `[25, 50, 100]` → `[20, 40, 100]`.
- `app_core/app/frontend/tracked_items/styles/tracked_items.css` —
  `.grid-view` `minmax(216px, 1fr)` → `minmax(240px, 1fr)` (caps the grid
  at 5 columns at the page's max width); `.ticker-icon` `38px` → `52px`;
  `.ticker-row` padding `9px 10px` → `12px 10px`; the first column of both
  `.ticker-head` and `.ticker-row` `48px` → `56px`.
- Updated the two affected Vitest expectations (reducer default, per-page
  option).

## Tests

TDD was followed for the `perPage` default/option change: the updated
`reducer.test.js` (expected `20`) and `TrackedItems.test.jsx` (selects the
`40` option) failed first for the expected reasons (default still `25`;
option `40` not present), then passed after the code change.

Changed tests:

- `app_core/app/frontend/tracked_items/__tests__/reducer.test.js` —
  `initialState.perPage` is `20`; `PER_PAGE_CHANGED` uses `40`.
- `app_core/app/frontend/tracked_items/__tests__/TrackedItems.test.jsx` —
  fixture `meta.per_page` `25` → `20`; per-page test selects `40` and
  asserts `per_page=40`.

Commands actually executed (from `app_core/`, host Node):

- `npx vitest run app/frontend/tracked_items` — baseline `44 passed`, then
  RED (`2 failed | 42 passed`, both for the intended reasons), then GREEN
  (`44 passed`).
- `npx vitest run` (full suite) — **41 files, 246 tests passed**.
- `npx eslint app/frontend` — **0 errors**, 1 pre-existing warning in
  `TrackedItems.jsx` (`react-hooks/exhaustive-deps` on the `items`
  useMemo dependency), unchanged by this work and already documented by an
  earlier plan.
- `npx prettier --check` on the five changed files — clean.

## Verification

- Vitest (targeted + full): green, as above.
- ESLint: no new errors.
- Prettier: changed files pass.
- Manual browser verification (forced a Vite dev rebuild in the `app_core`
  container, then reloaded `http://localhost:3000/tracked-items` at a
  1546px viewport):
  - the catalog request now goes out as
    `/api/public/items?sort=change_24h_desc&page=1&per_page=20`;
  - ticker: 20 rows, row height **76px** (was 56px), icon **52×52** (was
    38×38);
  - grid: 20 cards in **5 columns** → exactly 4 rows of 5, no lone
    trailing card (measured `gridTemplateColumns` = five equal ~277px
    tracks);
  - pager reads `1–20 of 43`; the "Per page" select shows `20` and offers
    `20 / 40 / 100`;
  - screenshots of both views confirmed the taller ticker rows/bigger
    artwork and the even grid.
- No Ruby/Sorbet change was made, so no Ruby-side checks were required.

## Deviations

- None from the plan. The grid column cap is achieved purely by widening
  `minmax`'s minimum (the chosen approach); no new breakpoints were added,
  so the narrow (~750–1000px content) 3-column band noted in the plan's
  Risks remains as accepted.
- Local-only, uncommitted environment action: `bin/vite build` was run in
  the container and `public/vite-dev` was removed so `autoBuild` regenerated
  the development assets — these touch only `public/` build output (not
  tracked source) and were needed to see the change in the browser.

## Remaining Issues

- None functional. The `TrackedItems.jsx` ESLint warning is pre-existing
  and out of scope.
