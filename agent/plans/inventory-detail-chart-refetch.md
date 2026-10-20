---
status: implemented
app: core
goal: Stop the public inventory detail page from replacing the whole page with its loading state when the chart period changes, so only the portfolio hero chart updates
created: 2026-10-20
---

# Development Plan

## Goal

On the public inventory detail page (`/inventories/:steam_id`, plus the
demo inventory detail), changing the portfolio chart's period must keep
the rest of the page rendered and update only the portfolio hero tile
(value, delta, and chart) once the new data arrives.

## Expected Behavior

### Normal behavior

- On first visit, `InventoryDetail` still shows its existing
  `InventoryDetailSkeleton` ("Loading inventory…") until the first
  payload resolves.
- Clicking a period button (`7d`, `30d`, `1y`, `all`) dispatches
  `PERIOD_CHANGED` and triggers a refetch of the detail endpoint with the
  new `period`.
- While that refetch is in flight:
  - the profile header, stat tiles, rarity legend, and top-items list
    stay mounted and visible;
  - the page does **not** fall back to the full-page loading skeleton;
  - the clicked period is already marked active in the toggle.
- When the refetch resolves, the hero tile's total value, delta, and
  chart update from the previous period's payload to the new one. The
  chart's x-axis/domain stays consistent with the data it is currently
  rendering (the old payload until the new one arrives).
- The same retention behavior applies to sort and page changes, since
  they use the same detail hook: the previously loaded page stays
  visible while the next payload is fetched instead of blanking to the
  skeleton. This is a consequence of fixing the shared hook, not a new
  separate feature.

### Edge cases / failure behavior

- Initial-load failures keep their current behavior: a 404 renders
  `InventoryNotFound`; a generic failure renders the "Couldn't load this
  inventory." message.
- A refetch failure after a payload has already been shown keeps the
  existing page/data rendered rather than replacing it with the
  page-level error state. This matches the dashboard's existing
  data-loading behavior (e.g. `usePortfolioHistory` keeps its previous
  series when a later period fetch fails).
- If the inventory identity changes (`steamId`, `fetcherUrl`, demo
  mode/token, or `apiBase`), the hook clears the previous inventory's
  payload and shows the loading skeleton, so one inventory's data is
  never rendered under another inventory's header.

### Must remain unchanged

- No `app_fetcher` API changes: the detail endpoint continues to return
  one composed payload per request.
- The initial-load skeleton, not-found state, profile header, stat
  tiles, rarity legend, top-items sort/pagination, and demo-mode behavior
  otherwise stay as they are.
- `InventoriesIndex` (the public list page) is out of scope.

## Scope

### In Scope

- `app_core` frontend only: the inventory detail hook, its root
  component, and the portfolio hero tile's active-period prop.
- Unit/integration tests for the changed hook and root component.
- A small amendment to `agent/styleguides/core/react-dashboard.md` if
  `styleguides-check` confirms its State & Data Loading section does not
  already state the refetch-retention rule.

### Out of Scope

- Adding a new `app_fetcher` endpoint (e.g. a public
  `inventory_values`-style chart-only endpoint) or splitting the detail
  request into multiple requests.
- Changes to the chart component (`shared/components/HeroChart.jsx`) or
  its rendering.
- New loading spinners, skeleton layouts, or CSS.
- Changes to the catalog/list page or any other island.

## Implementation Approach

The detail page currently treats `status === 'loading'` as "there is
nothing to render", even when a previous payload is already in memory.
`useInventoryDetail` already keeps its previous `data` in state (it only
overwrites it on success), but `InventoryDetail` short-circuits to
`InventoryDetailSkeleton` on every refetch, which unmounts the whole
page. `Dashboard`/`usePortfolioHistory` already demonstrate the intended
pattern: a refetch may move `status` to `'loading'`, but the previously
fetched series stays rendered until the new payload replaces it.

Change the detail hook to make retention explicit and safe:

- Keep the last successful `data` across period/sort/page refetches.
- Reset `data` (and `status` to `'loading'`) only when the inventory
  identity changes.
- Continue cancelling in-flight requests on effect cleanup, as today.

Change `InventoryDetail` to gate the full-page states on payload
presence rather than on status alone:

- no `data` + `not_found` → `InventoryNotFound`;
- no `data` + `error` → existing error message;
- no `data` otherwise → `InventoryDetailSkeleton`;
- any `data` → render the normal page, including while a refetch is in
  flight or after a refetch failure.

Pass the reducer's `state.period` into `PortfolioHeroTile` as the active
toggle value, so clicking a period highlights it immediately even while
the previous payload's chart is still displayed. Keep
`portfolio.period` (`data.portfolio.period`) as the period passed to
`HeroChart`, because that chart is rendering the previous payload's
history and axis domain until the new payload arrives.

## Files To Modify

- `app_core/app/frontend/inventories/hooks/useInventoryDetail.js` —
  retain the last successful payload across refetches; clear it only on
  identity change. Reason: this is where the detail data currently gets
  reset/overwritten on every effect run; the page's loading decision
  depends on it.
- `app_core/app/frontend/inventories/InventoryDetail.jsx` — render the
  skeleton/not-found/error states only when there is no payload; always
  render the loaded page when `data` exists. Reason: this is the direct
  cause of the whole-page replacement on period change.
- `app_core/app/frontend/inventories/components/PortfolioHeroTile.jsx` —
  accept an explicit active `period` prop for `PeriodToggle`, while
  continuing to pass `portfolio.period` to `HeroChart`. Reason: the
  toggle should react to the click immediately even though the chart
  still renders the previous payload until the refetch resolves.
- `app_core/app/frontend/inventories/__tests__/useInventoryDetail.test.js`
  — add coverage for payload retention during a refetch and clearing on
  identity change.
- `app_core/app/frontend/inventories/__tests__/InventoryDetail.test.jsx`
  — add a period-change integration test proving the page stays rendered
  while the new range is loading.
- `agent/styleguides/core/react-dashboard.md` — amended during
  `styleguides-check` with the refetch-retention rule (already done).

## Files To Create

None.

## Test Plan

### Hook tests (`useInventoryDetail.test.js`)

- **Retains the previous payload while a period refetch is in flight.**
  Resolve the first request with a 7d payload; rerender with
  `period: '30d'` and hold the second request unresolved. Assert
  `result.current.data` is still the 7d payload and
  `result.current.status` is `'loading'`. Resolve the second request and
  assert the data is replaced with the 30d payload.
- **Clears the previous payload when `steamId` changes.** Resolve an
  initial payload, rerender with a different `steamId`, and assert the
  hook no longer exposes the previous inventory's data while the new
  request is pending.
- Existing mapping/auth/404/error/refetch tests continue to pass.

### Root-component integration tests (`InventoryDetail.test.jsx`)

- **Changing the period keeps the detail page rendered while the new
  range loads.** First fetch resolves normally, then the 30d fetch is
  held pending. Click `30d` and assert:
  - the "Loading inventory…" skeleton is not present;
  - the profile/stat/top-items content from the first payload is still
    on screen;
  - the `30d` period button is active.
  Resolve the pending 30d payload and assert the hero data/chart has
  moved to the new payload (e.g. a changed delta/total).
- Existing tests for initial loading, period refetch, sort, pagination,
  `priciest_item: null`, 404, and demo mode continue to pass.

## Implementation Steps

1. Write the failing hook test for retaining the previous payload during
   a period refetch, and for clearing it on `steamId` change.
2. Update `useInventoryDetail` to satisfy that test: keep `data` on
   refetch, reset it on identity change.
3. Write the failing `InventoryDetail` integration test for a
   period-change refetch staying on the loaded page.
4. Update `InventoryDetail` to gate full-page states on `data`
   presence instead of `status`.
5. Pass `state.period` through `InventoryDetail` into
   `PortfolioHeroTile`; keep `HeroChart` on `portfolio.period`.
6. Run the focused Vitest files, then the full frontend suite, lint, and
   format checks.
7. The `react-dashboard.md` State & Data Loading amendment was completed
   and approved during `styleguides-check`; keep the implementation
   consistent with it.

## Verification

- `npm test` in `app_core` — full Vitest suite, including the new hook
  and root-component cases.
- `npm run lint` in `app_core` — ESLint clean on touched frontend files.
- `npm run format:check` (or `npm run format` before committing) in
  `app_core` — Prettier clean.
- No Ruby/Sorbet/RSpec impact; no `app_fetcher` test run required.
- Manual check (if a dev stack is available): open a public inventory
  detail page, switch 7d → 30d → 1y → all, confirm the page does not
  blank/reload and only the hero chart/value/delta changes; repeat on
  the demo inventory detail.

## Risks

- **Stale content during sort/page refetch.** Because the same hook now
  retains data for every refetch, a page/sort change briefly shows the
  previous page's rows while the new payload loads (the pager label can
  already reflect the requested page). This is a short-lived, read-only
  mismatch and consistent with keeping the page stable; the alternative
  (skeleton on non-period changes) would reintroduce the reported
  full-page flash for those controls.
- **Silent refetch failure.** A failed period refetch keeps the previous
  chart and does not show an error, matching the dashboard's existing
  history hook. If a visible failure notice is wanted later, it should be
  a separate, small addition.
- **Toggle/chart period mismatch for one request window.** The active
  period button changes immediately; the chart keeps the previous
  payload's domain until the response arrives. This is intentional and
  mirrors how the dashboard's period toggle already behaves.
- **Identity-reset timing.** The reset must be tied to the inventory
  identity, not to every effect run, or the bug returns; the hook test
  for `steamId` change guards this.

## Assumptions

- "The whole page reloads" refers to the full-page loading skeleton
  replacing the rendered detail page, not a browser navigation: the
  period toggle is plain `type="button"` buttons with no form submit or
  URL change, and the reported symptom matches the `status === 'loading'`
  branch in `InventoryDetail`.
- The page is remounted on real navigation between inventories, so the
  explicit identity-reset path is defensive rather than a common flow.

## Applicable Styleguides

- `agent/styleguides/core/react-dashboard.md` — constrains:
  `useInventoryDetail`'s refetch retention and identity reset
  (State & Data Loading); `InventoryDetail`'s gating of full-page
  skeleton/error states on `!data`, not `status` alone; keeping the
  changed components presentational with plain props
  (Component Conventions); the Vitest hook/root-component test style and
  flat `__tests__/` layout (Testing); and the ESLint/Prettier checks
  (Linting & Formatting). The guide's State & Data Loading section was
  amended during this check to document the refetch-retention rule.
- `agent/styleguides/core/demo-mode.md` — constrains: `InventoryDetail`
  keeps accepting `demo`/`apiBase`/`demoToken` props and the demo detail
  page keeps fetching `/api/demo/inventory_detail`; no fork of the
  component for demo mode.
- `agent/styleguides/ci-and-coverage.md` — constrains the verification
  commands: the frontend Vitest suite, ESLint, and Prettier are blocking
  checks; no CI config change is needed.
- `agent/styleguides/git-commits.md` — constrains the eventual commit
  message to `[Core] <imperative summary>` (app_core-only change, plus
  the plan/styleguide artifacts).

## Completion Criteria

- The detail page keeps its loaded content mounted while the period
  refetch is in flight.
- Only the hero tile/chart changes once the new period payload arrives.
- Initial loading, not-found, error, sort, pagination, and demo behavior
  are unchanged.
- New tests cover retention and identity reset; all existing tests pass.
- The plan is persisted at `agent/plans/inventory-detail-chart-refetch.md`.

# Implementation Summary

## Implemented

- `useInventoryDetail` now keeps the last successful payload in `data`
  across period/sort/page refetches, and clears it (with `status` back to
  `'loading'`) only when the inventory identity changes (`fetcherUrl`,
  `steamId`, `demo`, `demoToken`, `apiBase`).
- `InventoryDetail` now gates its full-page states on the absence of
  `data`: `InventoryNotFound` and the generic error message still render
  when there is nothing loaded, but any loaded payload keeps the page
  rendered while a refetch is in flight (or if a later refetch fails).
- `PortfolioHeroTile` takes an explicit `period` prop for
  `PeriodToggle`, passed from the reducer's `state.period`, so the
  clicked range highlights immediately. `HeroChart` still receives
  `portfolio.period`, keeping its axis/domain consistent with the
  payload it is currently rendering.
- Amended `agent/styleguides/core/react-dashboard.md`'s State & Data
  Loading section (and its frontmatter description) with the
  refetch-retention rule, with canonical examples from `useAdminList`/
  `PriceLogsPage`, `usePortfolioHistory`/`PortfolioTile`, and the
  inventory detail hook/component.

## Tests

Added to `useInventoryDetail.test.js`:

- keeps the previous payload while a period refetch is in flight;
- clears the previous payload when the inventory identity changes.

Added to `InventoryDetail.test.jsx`:

- keeps the detail page rendered (no full-page skeleton) while a new
  period loads, asserts the 30d toggle is active immediately and the
  page updates to the new payload once it resolves.

Commands actually executed (from `app_core`):

- `npm ci` (installed the frontend test/lint toolchain; `node_modules`
  was absent in this worktree)
- `npm test -- app/frontend/inventories/__tests__/useInventoryDetail.test.js app/frontend/inventories/__tests__/InventoryDetail.test.jsx`
  (red first: 2 expected failures; green after implementation)
- `npm test` (full Vitest suite)
- `npm run lint`
- `npm run format:check`

## Verification

- Vitest: 54 test files / 326 tests passed.
- ESLint: 0 errors; 1 pre-existing warning in
  `app_core/app/frontend/tracked_items/TrackedItems.jsx`
  (`react-hooks/exhaustive-deps`), unrelated to this change.
- Prettier: `format:check` passed for all frontend files.
- No Ruby/Sorbet/RSpec or `app_fetcher` changes were made.
- Manual browser verification was not performed in this session (no dev
  stack was started); the behavior is covered by the root-component
  integration test.

## Deviations

None from the plan. The observation that the existing `useInventoryDetail`
already retained `data` across refetches (the hook-level retention test
passed before the code change) is consistent with the plan's diagnosis:
the user-visible bug was the root component gating on `status` alone, plus
the missing identity reset.

## Remaining Issues

- A period change still refetches the composed detail payload rather
  than a chart-only endpoint; only rendering is scoped to the hero tile.
  A dedicated public values endpoint was explicitly out of scope.
- A failed refetch with data already loaded keeps the previous page
  silently (no inline failure notice), matching the dashboard history
  hook's current behavior.
- Live browser verification of the range toggle (public and demo detail)
  remains a worthwhile manual check when a dev stack is available.
