---
status: implemented
app: core
goal: Fix frontend review notes: consistent entrypoint naming, unified 1-based pagination, rename a misnamed rarity helper, and remove a dead Sparkline ternary.
created: 2026-10-19
---

# Development Plan

## Goal

Resolve the four frontend review notes in `app_core/app/frontend`:

1. Use one filename style for every Vite entrypoint.
2. Rename `tracked_items/utils/format.js` to `rarity.js`, since it only
   exports `rarityColor`.
3. Unify pagination on a 1-based page contract and handle `totalPages = 0`
   without rendering `1 / 0`.
4. Remove the dead `showArea ? 1.6 : 1.6` ternary in `Sparkline.jsx`.

## Expected Behavior

- All files under `app_core/app/frontend/entrypoints/` use kebab-case:
  `dashboard.jsx`, `tracked-items.jsx`, `inventories-index.jsx`,
  `inventory-detail.jsx`, `admin-panel.jsx`. Every Rails view references the
  matching filename.
- `rarityColor` lives in `tracked_items/utils/rarity.js`; tracked-items
  components and its unit test import it from there. No `format.js` remains
  under `tracked_items/utils/`.
- Every pagination component (`shared/components/Pagination.jsx`,
  `admin-panel/components/Pagination.jsx`,
  `tracked_items/components/CatalogPagination.jsx`) accepts and displays a
  1-based `page`. API/reducer page values are passed through without `- 1`
  translation.

## Scope

### In Scope

- Entrypoint renames plus the five `vite_javascript_tag` references.
- Rename of the tracked-items rarity helper and its test file; import updates.
- `shared/components/Pagination.jsx`: 1-based contract, `Math.max(totalPages,
  1)` display guard, corrected disabled guards and range math.
- Dashboard pagination source of truth: `dashboard/reducer.js` page reset and
  initial page become 1-based; `dashboard/components/ItemsTile.jsx` clamps and
  slices against that base.
- Inventories call sites that currently translate 1-based state/API pages to
  the shared component's old 0-based contract
  (`inventories/InventoriesIndex.jsx`,
  `inventories/components/TopItemsList.jsx`).
- Delete the dead ternary in `shared/components/Sparkline.jsx`.
- Add a focused test for the shared `Pagination` contract, including the
  `totalPages = 0` case; update dashboard reducer tests that assert page 0.
- Update `agent/styleguides/core/react-dashboard.md` so its documented
  pagination contract matches the implementation.

### Out of Scope

- Merging `admin-panel/components/Pagination.jsx` or
  `tracked_items/components/CatalogPagination.jsx` into the shared
  component; their display shapes differ (numbered pages plus per-page
  selector, and catalog per-page selector respectively).
- Renaming island directories (`tracked_items/`, `admin-panel/`) or component
  files.
- Backend pagination behavior or API response shapes.
- Regenerating ignored `public/vite*` build output.

## Implementation Approach

### Entrypoint naming

Adopt kebab-case for Vite entrypoint filenames, matching the existing
`admin-panel.jsx` and the frontend's multiword directory naming
(`admin-panel/`). Rename the three snake_case entries with `git mv`; keep
`dashboard.jsx` and `admin-panel.jsx` unchanged. Update the five
`vite_javascript_tag` names in the corresponding ERB views.

### Pagination

Make the shared `Pagination` component's public contract 1-based, matching
the API metadata and every reducer:

- `start = totalCount === 0 ? 0 : (page - 1) * pageSize + 1`
- `end = Math.min(page * pageSize, totalCount)`
- Previous disabled when `page <= 1`; next disabled when
  `page >= Math.max(totalPages, 1)`.
- Display `page / Math.max(totalPages, 1)`, so an empty result renders
  `1 / 1`, not `1 / 0`.

Then remove all call-site base translation:

- Dashboard's reducer stores 1-based pages (`initialState.page = 1`, filter
  and sort resets set `1`). `ItemsTile` clamps the incoming page to
  `[1, totalPages]` and slices from `(currentPage - 1) * PAGE_SIZE`.
- `InventoriesIndex` and `TopItemsList` pass `state.page` / `itemsPage`
  directly and keep their existing `± 1` callbacks, which are already
  1-based API page steps.

`admin-panel/components/Pagination.jsx` and
`tracked_items/components/CatalogPagination.jsx` already use this contract;
they need no logic change. Their names can remain distinct because their
presentation differs, and after this change all three components agree on
the page base.

### Rarity helper rename

Move `tracked_items/utils/format.js` to
`tracked_items/utils/rarity.js`; the only export is `rarityColor`. Update
the three component imports and rename the colocated test to
`__tests__/rarity.test.js` with the new import path. This mirrors
`inventories/utils/rarity.js`. No behavior change.

### Sparkline cleanup

Replace `strokeWidth={showArea ? 1.6 : 1.6}` with `strokeWidth={1.6}`.

## Applicable Styleguides

- `agent/styleguides/core/react-dashboard.md` — constrains the entrypoint
  naming, the shared pagination contract and empty-result behavior, the
  dashboard reducer/slicing page base, component/test structure, and the
  Prettier/ESLint verification steps.

## Files To Modify

- `app_core/app/frontend/entrypoints/tracked_items.jsx` →
  `tracked-items.jsx`; same for `inventories_index.jsx` →
  `inventories-index.jsx`, `inventory_detail.jsx` →
  `inventory-detail.jsx`; reason: one entrypoint filename style.
- `app_core/app/views/tracked_items/show.html.erb`,
  `app_core/app/views/inventories/index.html.erb`,
  `app_core/app/views/inventories/show.html.erb`: update
  `vite_javascript_tag` names to the renamed entrypoints.
- `app_core/app/frontend/shared/components/Pagination.jsx`: 1-based math,
  zero-page guard, disabled guards.
- `app_core/app/frontend/shared/components/Sparkline.jsx`: simplify
  `strokeWidth`.
- `app_core/app/frontend/dashboard/reducer.js`: `page: 1` initial and resets.
- `app_core/app/frontend/dashboard/components/ItemsTile.jsx`: 1-based clamp
  and slice.
- `app_core/app/frontend/inventories/InventoriesIndex.jsx`: stop subtracting
  one from `state.page`.
- `app_core/app/frontend/inventories/components/TopItemsList.jsx`: stop
  subtracting one from `itemsPage`.
- `app_core/app/frontend/tracked_items/utils/format.js` →
  `utils/rarity.js`: rename only.
- `app_core/app/frontend/tracked_items/components/GridView.jsx`,
  `FilterDropdown.jsx`, `TickerView.jsx`: import `rarityColor` from
  `../utils/rarity`.
- `agent/styleguides/core/react-dashboard.md`: replace the documented
  0-indexed shared `Pagination` contract and call-site translation rule with
  the unified 1-based contract, and record the kebab-case entrypoint naming
  rule.

## Files To Create

- `app_core/app/frontend/shared/__tests__/Pagination.test.jsx` — focused
  coverage for the shared pagination contract, especially the zero-total
  edge case.

## Test Plan

- New `shared/__tests__/Pagination.test.jsx`:
  - 1-based range and page label on a middle page;
  - previous disabled on page 1, next disabled on the last page;
  - `totalPages = 0` and `totalCount = 0` renders `0 of 0` and `1 / 1` with
    both controls disabled.
- Update `dashboard/__tests__/reducer.test.js`: sort/filter reset
  expectations move from page 0 to page 1; assert the initial page.
- Keep `dashboard/__tests__/ItemsTile.test.jsx` passing (range strings and
  filter/sort integration already cover the shared component through the real
  reducer).
- Rename `tracked_items/__tests__/format.test.js` →
  `rarity.test.js`, update its import; same assertions.
- Run the full app_core Vitest suite to catch any remaining page-base
  assumptions.

## Implementation Steps

1. Rename the three snake_case entrypoints with `git mv`; update the three
   ERB `vite_javascript_tag` references.
2. Rename `tracked_items/utils/format.js` → `utils/rarity.js` and the test
   file; update the three component imports and the test import.
3. Write `shared/__tests__/Pagination.test.jsx` against the intended 1-based,
   zero-guarded contract (expect it to fail before the component change).
4. Change `shared/components/Pagination.jsx` to the 1-based contract and
   `Math.max(totalPages, 1)` guards; make the new test pass.
5. Move the dashboard reducer to 1-based pages and update its tests.
6. Update `ItemsTile` clamp/slice math for 1-based pages.
7. Remove the `- 1` translations in `InventoriesIndex` and `TopItemsList`.
8. Simplify `strokeWidth` in `Sparkline.jsx`.
9. Run Prettier, then the full frontend test, lint, and format checks.

## Verification

From `app_core/`:

- `npm test` (Vitest run, including the new pagination test and renamed
  rarity test).
- `npm run lint`.
- `npm run format:check` (run `npm run format` first if needed).
- Manually confirm the renamed entrypoints are the only files in
  `app/frontend/entrypoints/` and that every `vite_javascript_tag` references
  an existing filename.

## Risks

- Missing one `- 1` translation makes a server-paginated list request or show
  page 0. The full Vitest suite and direct grep for the old pattern cover
  this.
- The shared `Pagination` is used by both in-memory and server-paginated
  lists; the clamp in `ItemsTile` and the zero guard in the component keep
  empty/short result sets safe.
- Renaming entrypoints is only safe if Rails view tags are updated in the
  same change; Vite resolves entries by filename.

## Assumptions

- Kebab-case is the chosen entrypoint style because `admin-panel.jsx` already
  uses it and it is the conventional multiword filename style for frontend
  modules in this repository.

## Implementation Summary

### Implemented

- Renamed Vite entrypoints to kebab-case:
  `tracked-items.jsx`, `inventories-index.jsx`, `inventory-detail.jsx`;
  updated the three matching ERB `vite_javascript_tag` references.
- Renamed `tracked_items/utils/format.js` to `utils/rarity.js` and its test
  to `__tests__/rarity.test.js`; updated the three component imports and
  removed the stale top-of-file comment from the helper.
- Unified `shared/components/Pagination.jsx` on a 1-based page contract,
  added `Math.max(totalPages, 1)` guards, and removed the `1 / 0`
  empty-result display.
- Moved the dashboard reducer and `ItemsTile` slicing to 1-based pages.
- Passed 1-based pages straight through in `InventoriesIndex` and
  `TopItemsList` instead of subtracting one.
- Simplified `Sparkline`'s `strokeWidth` to the constant `1.6`.
- Updated `agent/styleguides/core/react-dashboard.md` with the 1-based
  pagination contract, zero-result guard, and kebab-case entrypoint rule.

### Tests

- Added `shared/__tests__/Pagination.test.jsx` (1-based range, disabled
  guards, `totalPages = 0`).
- Added 1-based pagination integration cases to
  `dashboard/__tests__/ItemsTile.test.jsx`,
  `inventories/__tests__/InventoriesIndex.test.jsx`, and
  `inventories/__tests__/InventoryDetail.test.jsx`.
- Updated `dashboard/__tests__/reducer.test.js` to assert page 1 resets.
- Renamed `tracked_items/__tests__/format.test.js` to `rarity.test.js`.
- Executed: `npm test`, `npm run lint`, `npm run format`,
  `npm run format:check`, `npx vite build`.

### Verification

- `npm test`: 49 files, 306 tests passed.
- `npm run lint`: passed with one pre-existing `exhaustive-deps` warning in
  `tracked_items/TrackedItems.jsx` (0 errors).
- `npm run format:check`: all files formatted.
- `npx vite build`: succeeded and emitted all five kebab-case entrypoints,
  confirming Vite resolves the renamed files.
- `bin/vite build` could not run in this environment because the local
  Ruby bundle is not installed (`Bundler::GemNotFound`); the direct Vite
  build above covers entrypoint resolution.

### Deviations

- None from the planned behavior.

