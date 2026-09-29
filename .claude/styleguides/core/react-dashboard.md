---
description: React dashboard island conventions in app_core — component structure, derived-data placement, state/data-loading shape, charting library boundaries, and Vitest/@testing-library testing conventions.
---

# React Dashboard (`app_core/app/frontend/dashboard/`)

See `.claude/styleguides/core/architecture-layers.md` first — it owns the
one rule that sits above everything in this file: the dashboard reads
`app_fetcher`'s API directly from the browser, never through an `app_core`
proxy. This file covers everything *inside* the island itself, which that
file doesn't address.

## Purpose

Give the dashboard's React code — components, derived-data functions,
UI state, data loading, and tests — a single consistent shape, so a new
tile or a new piece of async state doesn't have to re-derive conventions
from scratch by reading every existing file.

## Structure

```text
app/frontend/dashboard/
  Dashboard.jsx           — root component: owns the useReducer + the
                            data-loading hook, renders the tiles
  reducer.js              — the one UI-state reducer + its initialState
  chartConfig.js           — chart tuning constants (ranges, tick counts)
  hooks/
    useDashboardData.js    — the one data-loading hook
  components/
    <Name>Tile.jsx, <Name>.jsx — presentational components
  utils/
    <concern>.js           — pure derivation functions, no JSX, no React
  __tests__/
    *.test.js, *.test.jsx  — flat, colocated (see Testing)
```

A new concern gets a new file in the matching directory — new derived
data goes in `utils/`, a new presentational piece goes in `components/`,
a new async data source gets its own hook in `hooks/`. Nothing here uses
React Context — all shared state is owned by `Dashboard.jsx` and passed
down as props (see State).

## Component Conventions

- **Named exports only**, e.g. `export function ItemsTile(...)` — never
  `export default`. Every component in this directory follows this;
  there are no exceptions to extract as a deviation.
- **Plain destructured props**, no `PropTypes`, no TypeScript — this app
  has no frontend type-checking layer at all (Sorbet only covers the Ruby
  backends). Correctness here is the tests' job, not a props contract.
- **Presentational by default.** A component receives data and callbacks
  as props and renders; it does not fetch data itself. The only place
  that calls `fetch` is `useDashboardData.js`. A component that needs
  local, presentation-only state (e.g. `ItemsToolbar`'s outside-click
  handling via `useRef`/`useEffect`) may use it, but shared/cross-tile
  state still lives in `reducer.js`, not component state.
- **Composition over configuration.** Small single-purpose components
  (`Chevron` inside `FilterDropdown.jsx`, `SortDropdown`) are nested
  directly in the file that uses them when they have no other caller,
  rather than being extracted to their own file pre-emptively. Extract to
  `components/` only once something else needs to import it.

## Derived Data: `utils/`

Any computation over raw data — filtering, sorting, bucketing into time
series, formatting — is a pure function in `utils/`, never inlined in a
component's render body. Existing examples: `filters.js`
(`applyFilters`/`applySort`), `portfolioSeries.js`, `marketVolume.js`,
`itemSeries.js`, `bucketing.js` (the shared bucketing primitives both
series functions build on), `format.js` (display formatting).

These functions:

- take plain data (arrays/objects already mapped into the dashboard's own
  shape — `marketHashName`, `currentPriceCents`, `priceHistory`, etc.,
  not the raw snake_case API response) and return plain data;
- are null/empty-safe by construction, not by the caller checking first
  — e.g. `itemSeries` treats a missing `priceHistory` as `[]`;
  `portfolioSeries`/`marketVolume` both produce a sensible empty result
  (`[]` series, `0` totals) for an empty or not-yet-hydrated items array,
  rather than throwing or requiring a guard at the call site. Any new
  derivation function must do the same — a partially-loaded or
  empty-items dashboard state is a normal input, not an edge case to
  special-case outside the function.
- are covered by dedicated unit tests with no rendering involved (see
  Testing).

`chartConfig.js` is a sibling exception: it holds tuning *constants*
(`RANGE_MS`, tick counts, axis-label generation), not derivation over
request data — it lives at the top level next to `reducer.js`, not inside
`utils/`, because it configures the chart components rather than
transforming dashboard data.

## State & Data Loading

**UI state** (filters, sort, pagination, selection, open dropdown) is one
`useReducer(dashboardReducer, initialState)` owned by `Dashboard.jsx`,
defined in `reducer.js`. One reducer for the whole dashboard, not one per
tile — action types are flat strings (`'RANGE_CHANGED'`,
`'ITEM_ROW_CLICKED'`, `'WEAPON_FILTER_TOGGLED'`, ...), each returning a
full new state object via spread. Multi-select filter state is a plain
object of `Set`s (`{weapons: Set, conditions: Set, stattrakOnly: bool}`),
toggled through a shared `toggleSetMember` helper — follow this shape for
a new multi-select filter rather than inventing a different collection
type.

**Data loading** is a custom hook per data source
(`useDashboardData(fetcherUrl, bridgeToken)` is the only one today),
returning `{data, status, error}` with `status` a flat string enum. Two
rules that generalize beyond today's exact 3 values:

- `status` describes the *overall* load, and only needs enough values to
  distinguish states the UI actually renders differently — today that's
  `'loading' | 'success' | 'error'`. A load with more than one
  independently-resolving stage (e.g. an initial fast read plus a slower
  batch that fills in more detail) should **not** try to cram every
  stage into one `status` enum — add a second, narrower status field
  scoped to that specific stage (e.g. a `historyStatus` alongside
  `status`, rather than growing `status` to
  `'loading'|'items-ready'|'success'|'error'`). This keeps each status
  field answerable by "what does the UI do differently for each value of
  *this* field," and keeps `status === 'success'` meaning "there is data
  to render" without every consumer needing to know about substages that
  don't change whether the page is showable.
- A stage that fails after an earlier stage already produced showable
  data must not discard that data or force the whole hook back to an
  error state — only the specific stage's own status field reflects the
  failure. `status`/`data` regress to an error state only when the
  *first* (data-bearing) stage itself fails, since there is nothing
  meaningful to render without it.

## Charting: Recharts vs. hand-rolled SVG

Two different tools for two different jobs, both already in the
codebase — pick by these criteria, don't default to "always use the
charting library":

- **Recharts** (`HeroChart.jsx`) for the one chart that needs axes, a
  tooltip, and real interactivity — it's rendered once per dashboard
  view.
- **Hand-rolled inline SVG** (`Sparkline.jsx`, used by `ItemRow` per row
  and `MarketVolumeTile`) for small, repeated, decorative
  visualizations with no axes/tooltip/legend. `Sparkline.jsx`'s own
  comment states the reasoning directly: it renders 8-9+ times per page
  view, and a full charting-library instance per 38×24px decorative line
  is the wrong tool for that multiplicity. Don't replace `Sparkline`
  with a Recharts-based mini-chart "for consistency" — the two exist for
  different rendering-cost profiles, not out of inconsistency.

## Styling

Plain CSS classes (`dashboard.css`), BEM-ish naming (`tile`,
`tile-hero`, `dropdown-panel`, `chip`, `is-active`, `is-open`) — no CSS
modules, no styled-components, no Tailwind. Conditional classes are
built with template-string concatenation
(`` `chip${active ? ' is-active' : ''}` ``), not a `classnames`-style
helper (none is a dependency).

## Testing

Vitest (`vite.config.js`'s `test` block: `environment: 'jsdom'`,
`globals: true`, single setup file
`__tests__/setup.js` — which only pulls in
`@testing-library/jest-dom/vitest` matchers) + `@testing-library/react`
+ `@testing-library/user-event`. Every existing test file explicitly
`import { describe, test, expect } from 'vitest'` despite `globals:
true` being configured — follow that; don't rely on the implicit
globals even though they'd work.

### Structure

- All tests live flat under `__tests__/`, not colocated per-component —
  `ItemsTile.test.jsx` sits next to `filters.test.js`, not inside
  `components/`.
- `.test.js` for testing a pure `utils/`/`reducer.js` function with no
  rendering (`filters.test.js`, `portfolioSeries.test.js`,
  `marketVolume.test.js`, `reducer.test.js`). `.test.jsx` only when the
  test itself renders JSX (`ItemsTile.test.jsx`) — matches the
  source-file split below.

### What gets a dedicated test file

Not every component has one — `SortDropdown`, `ItemsToolbar`,
`FilterDropdown`, `Pagination`, `RangeToggle`, `Sparkline`,
`ChartTooltip`, and `HeroChart` have none today. The dividing line
observed across the existing suite: a component gets its own test when
it **composes/orchestrates other pieces** (`ItemsTile` wires the
reducer, `filters.js`, and `Pagination` together) or **contains
conditional/derivation logic worth isolating in its own right**, not
merely when it renders. A simple presentational leaf component with no
branching logic of its own is exercised indirectly (through whichever
composite renders it) or not directly tested at all. When adding a new
component, ask "does this branch on data in a way that could be wrong,"
not "is this a component" — if yes, it gets a test file; if it's pure
layout/presentation, it doesn't need one just for existing.

### Test styles, by what's under test

- **Pure-function unit tests** (`filters.test.js`, `portfolioSeries.test.js`,
  `marketVolume.test.js`, `reducer.test.js`): call the function directly
  with hand-built plain-object fixtures, assert on the return value — no
  rendering, no mocking.
- **Hook tests** (`useDashboardData.test.js`): `renderHook` +
  `waitFor` from `@testing-library/react`, with `vi.stubGlobal('fetch',
  vi.fn()...)` to control network responses — mock at the `fetch`
  boundary, not by stubbing the hook's own internals.
- **Component "integration-style" tests** (`ItemsTile.test.jsx`): mount a
  small harness component that owns a real
  `useReducer(dashboardReducer, initialState)` (the same reducer
  `Dashboard.jsx` uses, not a stub), render the component under test
  wired to it, and drive it through `@testing-library/user-event` —
  proving the reducer, derivation functions, and rendering work together
  end to end, rather than asserting against a shallow render or a mocked
  reducer. Follow this pattern for any new component whose correctness
  depends on how it responds to real state transitions (see
  `ItemsTile.test.jsx`'s own header comment for the reasoning).

## Interaction With Other Layers

```text
Dashboard.jsx
    ↓ useReducer(dashboardReducer, initialState)      (reducer.js)
    ↓ useDashboardData(fetcherUrl, bridgeToken)         (hooks/)
        ↓ fetch — GET Api::V1::InventoriesController#show
        ↓ fetch — POST Api::V1::PriceHistoriesController#index
          (see architecture-layers.md: called directly, no app_core proxy)
    ↓ passes data + dispatch-bound callbacks to tiles   (components/)
        ↓ tiles call utils/ functions to derive what they render
```

## Canonical Implementations

- `app_core/app/frontend/dashboard/Dashboard.jsx`,
  `app_core/app/frontend/dashboard/reducer.js`
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js`
- `app_core/app/frontend/dashboard/components/ItemsTile.jsx` — the
  composition/derivation/testing pattern in one place
- `app_core/app/frontend/dashboard/components/Sparkline.jsx` vs.
  `app_core/app/frontend/dashboard/components/HeroChart.jsx` — the
  charting-tool boundary
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx`,
  `useDashboardData.test.js`, `portfolioSeries.test.js`

## Related ADR

- `.claude/adr/core/sparkline-vs-recharts.md` — why Recharts is scoped to
  the one hero chart and repeated sparklines are hand-rolled SVG instead.
- `.claude/adr/core/component-tests-real-reducer.md` — why composite
  component tests drive a real `dashboardReducer` instead of mocking
  callback props.
