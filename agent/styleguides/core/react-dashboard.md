---
description: React island conventions in app_core (app/frontend/dashboard/ and any sibling island, e.g. tracked_items/, inventories/) — component structure, cross-island reuse via app/frontend/shared/, derived-data placement, state/data-loading shape, item-row trend direction (up/down/flat) and hero-delta zero-hiding, fixed-height paginated lists, mutation failure handling, charting library boundaries, CSS split, Vitest/@testing-library testing conventions, and the ESLint/Prettier lint/format stack.
---

# React Islands (`app_core/app/frontend/`)

See `agent/styleguides/core/architecture-layers.md` first — it owns the
one rule that sits above everything in this file: a React island reads
`app_fetcher`'s API directly from the browser, never through an `app_core`
proxy. This file covers everything *inside* an island itself, which that
file doesn't address.

These conventions govern every React island under `app_core/app/frontend/`,
not just the original one — see Purpose below for the full list, Structure
for the two internal shapes an island can take plus the `app/frontend/
shared/` directory cross-island code lives in, and Reuse Across Islands
for what crosses between islands and what doesn't. Most rules still read
in terms of `dashboard/`'s own files, since that's where the first
example of each lives; treat each as "the `dashboard/` island's version of
the rule," generalizing the same way for any other island.

## Purpose

Give a React island's code — components, derived-data functions, UI
state, data loading, and tests — a single consistent shape, so a new
tile, a new piece of async state, or a whole new island doesn't have to
re-derive conventions from scratch by reading every existing file. These
conventions apply to any React island mounted in `app_core`, not only the
dashboard — `app/frontend/dashboard/` is this file's first (single-page)
example, `app/frontend/tracked_items/` and `app/frontend/inventories/`
other single-page ones, and `app/frontend/admin-panel/` its first
multi-page example (see Structure/State & Data Loading for the one place
the two shapes genuinely differ).

## Structure

Single-page island (`app/frontend/dashboard/`, `app/frontend/tracked_items/`,
`app/frontend/inventories/` — the shape below applies as-is to any island
with exactly one page, or one root component per route for an island with
more than one but each with its own independent data-loading shape):

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

Multi-page island (`app/frontend/admin-panel/` — for an island with more
than one logical page sharing one mount point, e.g. a hash-routed admin
panel):

```text
app/frontend/admin-panel/
  AdminPanel.jsx           — root component: owns ONLY navigation state
                            (which page is active) via useHashRoute(),
                            renders the active page — no business/table
                            state lives here (see State & Data Loading)
  useHashRoute.js          — small hook: reads/writes location.hash,
                            re-renders on 'hashchange'; the one
                            dependency-free piece of navigation plumbing,
                            not a general-purpose router
  adminApi.js              — thin fetch wrapper (auth header, JSON
                            parse/error shape) shared by every page's
                            hooks/handlers — the one place that knows the
                            fetcher base URL and auth scheme, same role
                            `useDashboardData.js` plays alone when there's
                            only one data source to wrap
  pages/
    <Resource>Page.jsx      — one per logical page: owns its own
                            useReducer (see State & Data Loading),
                            renders that page's components
    <resource>Reducer.js    — that page's UI-state reducer + initialState
                            (naming mirrors reducer.js's role, scoped per
                            page: itemsReducer.js, priceLogsReducer.js, ...)
  hooks/
    useAdminList.js         — one generic data-loading hook parametrized
                            by resource path + page/per_page, reused by
                            every page (see State & Data Loading for why
                            this is one hook, not one per page)
  components/
  utils/
  __tests__/
```

Cross-island code with no knowledge of which island it's rendered in — it
takes plain data/callbacks in, renders or computes, and nothing about its
behavior changes if another island reuses it — lives in a third, sibling
location, not inside any one island's tree:

```text
app/frontend/shared/
  fonts/                   — the woff2 files every island's stylesheet builds on
  styles/
    tokens.css             — font-face rules, design-token custom
                             properties, and page-agnostic chrome
                             (topbar/nav-tabs, tile/card shell, dropdown,
                             range-toggle, pager) every island's own
                             stylesheet layers on top of
  utils/
    format.js               — display formatting with no island-specific shape
  chartConfig.js            — chart-rendering constants/mechanics
                              (RANGE_MS, tick counts, generateAxisLabels)
                              with no per-island range-set choice baked in
  components/
    Sparkline.jsx, RangeToggle.jsx, Pagination.jsx, HeroChart.jsx,
    ChartTooltip.jsx         — generic chart/sparkline/pagination primitives
  __tests__/
    format.test.js
```

A file moves to `shared/` the moment a second consumer needs it
verbatim — not pre-emptively, and not by forking it into near-identical
copies, one per island (see Reuse Across Islands for the exact test to
apply, and `agent/adr/core/multiple-react-islands.md` for why this was
deliberately deferred until a third island's concrete need confirmed it:
`dashboard/` and `tracked_items/` cross-imported `Sparkline`/`format.js`
directly from `dashboard/` at first; `inventories/` becoming a third
consumer of the same pure code is what triggered extracting `shared/`,
exactly the trigger that ADR named in advance). An island's own
`chartConfig.js` is the pattern for the part that *doesn't* generalize:
it keeps its own range-set choice (e.g. `dashboard/chartConfig.js`'s
`PORTFOLIO_RANGES`/`ITEM_RANGES`, with the comment on why `24h` is
excluded there) once the range-rendering mechanics (`RANGE_MS`,
`generateAxisLabels`) move to `shared/chartConfig.js` — split a file at
the "is this a choice this specific island makes, or a mechanism any
island would use identically" line, rather than moving it wholesale just
because most of it qualifies.

A new concern gets a new file in the matching directory — new derived
data goes in `utils/`, a new presentational piece goes in `components/`,
a new async data source gets its own hook in `hooks/` (single-page) or
goes through the shared `adminApi.js`/`useAdminList.js` if it's the same
shape as the other pages' (multi-page). Nothing here uses React Context
— all shared state is owned by the page that needs it (`Dashboard.jsx`
for a single-page island, each `<Resource>Page.jsx` for a multi-page one)
and passed down as props (see State & Data Loading).

A genuinely new top-level feature — one with its own route, its own data
source, and a data-loading shape that doesn't fit any existing island's
reducer/hook contract — is a new sibling directory under `app/frontend/`
(single-page or multi-page, per Structure above), not a second mode
squeezed into an existing island's reducer, and not a new page bolted
onto an existing multi-page island whose pages don't share its data
shape. It gets its own root component and its own `reducer.js`/`hooks/`/
`components/`/`utils/`/`styles/`/`__tests__/`, following every convention
in this file exactly as `dashboard/` does, importing what it needs from
`shared/` rather than duplicating those files or reaching into a sibling
island's own directory for them (an island's directory name describes
that one island, not a shared library — see Reuse Across Islands). State
is never shared between islands directly — two islands only ever share
pure, stateless code via `shared/`, never a reducer, a hook's state, or a
Context.

Every Vite entrypoint under `app/frontend/entrypoints/` uses **kebab-case**
(`admin-panel.jsx`, `tracked-items.jsx`, `inventory-detail.jsx`), never
snake_case. The entrypoint filename is the contract between Vite Ruby and
the Rails view, so `vite_javascript_tag` must reference the exact same
kebab-case name. Single-word entries (`dashboard.jsx`) are unchanged.

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
- **Optional image fields get a same-class placeholder, not a collapsed
  gap.** When a prop that renders as an `<img>` may be absent for a given
  row (`ItemRow`'s `item.iconUrl`, which the API can omit), branch in the
  render body: the `<img>` when present, an empty
  `<span aria-hidden="true" />` carrying the *same* class when absent
  (`ItemRow`: `<img className="mover-icon" src={item.iconUrl} alt="" />`
  vs. `<span className="mover-icon" aria-hidden="true" />`). Sharing the
  class means the placeholder keeps the element's layout footprint (e.g.
  a fixed-width icon column) instead of the row collapsing around a
  missing image. Cover both branches with explicit tests, the same as any
  other conditional rendering (see `ItemRow.test.jsx`).
- **A zero or absent 24h change is a `flat` trend, never `up`.** Every
  item row derives its trend direction through `shared/utils/trend.js`'s
  pure `trendDirection(pct)` (`'up' | 'down' | 'flat'`), not an inline
  `pct >= 0 ? 'up' : 'down'` — the latter maps a `0`/missing change into
  the green `--up` bucket and renders a misleading `▲ 0.0%`. A `flat` row
  shows **no** delta badge at all (the badge is gated on `direction !==
  'flat'`) and passes `variant="flat"` to `Sparkline`, which strokes the
  line in the neutral `--text-muted` rather than `--up`, so a flat row
  doesn't read as rising. A table row with no separate badge wrapper (the
  admin panel's Item table) renders a muted em dash (`—`) for `flat`
  instead of an arrow plus `0.0%`, using the same `trendDirection` result.
  The helper lives in `shared/` because more than one island's item row
  needs the identical rule (see Reuse Across Islands). Canonical:
  `dashboard/components/ItemRow.jsx`,
  `inventories/components/InventoryItemRow.jsx`,
  `admin-panel/pages/ItemsPage.jsx`.
- **The same flat rule applies to an aggregate card delta — a `0`/absent
  24h change hides its badge too.** `inventories/components/InventoryCard.jsx`'s
  `.inv-delta` (an inventory's summed 24h change) derives its direction
  through the same `trendDirection(pct)` helper and renders the badge
  only when the direction isn't `flat`, so a card with `0`/absent
  `change24hPercent` never shows `▲ 0.0%`. This is deliberately the
  `trendDirection` helper, **not** the bare `!== 0` guard the hero/
  portfolio delta below uses — the card delta is a 24h change (same
  meaning as an item row's), while the hero delta is a range-over-range
  value difference. Canonical: `inventories/components/InventoryCard.jsx`.
- **A stale item price keeps its last price and last computed delta, with
  a freshness marker.** When `price_updated_at` is older than the shared
  24-hour threshold, the row (`dashboard/components/ItemRow.jsx`,
  `inventories/components/InventoryItemRow.jsx`) still renders the last
  price and its last computed 24h delta, but adds an `is-stale` class and
  a `title`/caption with the last update time. It must never substitute
  `0`, hide the number, or recompute the delta on read — a stale price is
  not a missing one. The threshold and the human age label live in
  `shared/utils/priceFreshness.js`, shared by both islands' item rows.
  Canonical: `dashboard/components/ItemRow.jsx`,
  `inventories/components/InventoryItemRow.jsx`.
- **A hero/portfolio delta is rendered only when there is an actual,
  complete change.** The chart-hero delta (`PortfolioTile`'s and
  `PortfolioHeroTile`'s `.hero-delta`) must be omitted — not drawn as a
  green `▲ $0.00 (+0.00%)` — whenever the change is exactly `0`: most
  visibly a single-point series, where `last - first === 0`, but equally a
  series whose endpoints are equal. Gate it on `delta !== 0`
  (`PortfolioTile`) / `changeCents !== 0` (`PortfolioHeroTile`). It must
  also be omitted when the valuation is incomplete
  (`portfolio.complete === false`), the backend marks the change partial
  (`change.partial === true`), or no baseline exists
  (`change.available === false`) — a partial value is a lower bound and
  must not carry a delta badge. The value itself still renders, with the
  partial badge/Estimating caption described below. Unlike the item-row
  rule above this is a per-component render guard, not a shared
  helper — it isn't a cross-island derivation. Positive and negative
  complete changes render exactly as before. Canonical:
  `dashboard/components/PortfolioTile.jsx`,
  `inventories/components/PortfolioHeroTile.jsx`.
- **A partial valuation is marked, not hidden or silently presented as
  complete.** When the backend reports `complete === false`, the hero
  (`PortfolioTile`/`PortfolioHeroTile`) and the catalog card
  (`InventoryCard`) show a small partial badge next to the value, using
  the backend's `priced_items_count` / `pricable_items_count` (for
  example `38/40 priced`) — never a locally derived completeness rule.
  The item count and average may still render; the badge is the honesty
  marker for the lower-bound value. The chart may still plot partial
  history points, but the delta is suppressed per the rule above.
  Canonical: `dashboard/components/PortfolioTile.jsx`,
  `inventories/components/PortfolioHeroTile.jsx`,
  `inventories/components/InventoryCard.jsx`.
- **A paginated list keeps a stable `PAGE_SIZE` height with decorative
  placeholder rows.** When the current page holds fewer than `PAGE_SIZE`
  items, render the missing slots as empty `<li>`s that reuse the row's
  own layout classes (`.mover-row` plus a `.mover-icon` span) so each
  placeholder has exactly a real row's footprint — instead of a magic
  `min-height` on the list container (which duplicates the row height and
  fights the responsive `max-height` clamp) or letting the tile collapse
  to a partial page's height. Mark every placeholder `aria-hidden="true"`
  so it is neither focusable nor counted as a list item by role queries
  (`getAllByRole('listitem')` still returns only the real rows). Canonical:
  `dashboard/components/ItemsTile.jsx`.

## Linting & Formatting

The frontend has a JS/JSX analogue of the Ruby side's lint + format
enforcement: **ESLint** (flat config) for correctness and **Prettier**
for formatting. See `agent/adr/core/frontend-lint-stack.md` for why this
stack, and `agent/styleguides/ci-and-coverage.md` /
`agent/styleguides/git-hooks.md` for where it runs.

- **Prettier owns formatting; ESLint owns correctness.** Config lives in
  `app_core/eslint.config.js` (flat, ESM) and `app_core/.prettierrc`
  (+ `.prettierignore`). `eslint-config-prettier` is applied **last** in
  the ESLint config specifically so ESLint's stylistic rules stay off and
  the two tools never disagree about formatting.
- **ESLint plugins:** `eslint-plugin-react` and
  `eslint-plugin-react-hooks`. The hooks rules are load-bearing — they
  catch the dependency-array/conditional-hook mistakes the conventions in
  this file assume are avoided, not just formatting.
- **Both are blocking.** `npm run lint` (`eslint app/frontend`) and
  `npm run format:check` (`prettier --check app/frontend`) fail CI and
  the `pre-commit` hook. Existing frontend files were reformatted once by
  Prettier; new/changed files must already pass `format:check` — don't
  hand-format against it.
- **No Stylelint and no `tsc`.** The CSS split (below) and the
  no-TypeScript stance in Component Conventions stay as-is; this stack
  deliberately adds only lint + format.

### MUST

- Run `npm run format` (not hand-editing) before committing a frontend
  change, and keep `npm run lint` clean.
- Keep `eslint-config-prettier` last in `eslint.config.js` — adding any
  ESLint config after it reintroduces the formatting conflicts the split
  exists to avoid.
- Add a new ESLint rule or plugin only to `eslint.config.js`, never as an
  inline `/* eslint-disable */` for anything broader than a single,
  explained line.

### MUST NOT

- Don't add ESLint stylistic rules (indentation, quotes, spacing) — that
  is Prettier's job; rely on `eslint-config-prettier` to disable them.
- Don't add Stylelint or a TS config without a separate decision (an ADR
  superseding `agent/adr/core/frontend-lint-stack.md`).

## Derived Data: `utils/`

Any computation over raw data — filtering, sorting, bucketing into time
series, formatting — is a pure function in `utils/`, never inlined in a
component's render body. Existing examples: `filters.js`
(`applyFilters`/`applySort`), `portfolioSeries.js`, `marketVolume.js`,
`itemSeries.js`, `bucketing.js` (the shared bucketing primitives both
series functions build on).

These functions:

- take plain data (arrays/objects already mapped into the island's own
  shape — `marketHashName`, `currentPriceCents`, `priceHistory`, etc.,
  not the raw snake_case API response) and return plain data;
- are null/empty-safe by construction, not by the caller checking first
  — e.g. `itemSeries` treats a missing `priceHistory` as `[]`;
  `portfolioSeries`/`marketVolume` both produce a sensible empty result
  (`[]` series, `0` totals) for an empty or not-yet-hydrated items array,
  rather than throwing or requiring a guard at the call site. Any new
  derivation function must do the same — a partially-loaded or
  empty-items state is a normal input, not an edge case to special-case
  outside the function.
- are covered by dedicated unit tests with no rendering involved (see
  Testing).

An island's own `chartConfig.js` is a sibling exception: it holds tuning
*constants* (range-set choices, tick counts), not derivation over request
data — it lives at the top level next to `reducer.js`, not inside
`utils/`, because it configures the chart components rather than
transforming data. The range-rendering *mechanics* shared by every
island's charts live in `shared/chartConfig.js` instead (see Structure).

## Reuse Across Islands

Once more than one island exists, a piece of code from one is sometimes
exactly what another needs too. Two different outcomes, by one test: is
the piece pure/stateless and already generic, or is it coupled to its
owning island's own reducer/state shape?

- **Live in `shared/`, imported directly, never duplicated**, once a
  piece has no dependency on any one island's action types, state tree,
  or data shape — it just takes plain data/props and returns a value or
  markup. `shared/components/Sparkline.jsx` is the canonical example: per
  `agent/adr/core/sparkline-vs-recharts.md` it's already the one accepted
  way to render a small, repeated, decorative trend line, so every island
  needing the same visualization imports it
  (`import { Sparkline } from '../../shared/components/Sparkline'`)
  rather than growing a near-identical copy. `shared/utils/format.js`'s
  `fmtPrice`/`conditionAbbr`/`fmtUSD`/`fmtDateTime` are the same case for
  formatting — pure functions over plain values with no reducer/state
  dependency, imported directly rather than re-exported or copied. A
  shared component may have a narrower contract than a specific new use
  needs — adapt at the call site, don't fork the component for it.
  `shared/components/Pagination.jsx`'s contract is **1-indexed**, the same
  base as the API's `page`/`per_page`/`total_count` metadata and every
  island reducer. It computes its own `start`/`end` display range from a
  `pageSize` the caller passes in, and both an in-memory list
  (`dashboard/`'s client-side-sliced array) and a server-paginated list
  (`inventories/`) pass their 1-based page straight through — no `- 1`
  translation at the call site. It guards the empty result itself
  (`Math.max(totalPages, 1)` for the page indicator and disabled state),
  so `totalPages = 0` renders `1 / 1`, never `1 / 0`. Fork it into a new
  component only once a genuinely different *display* shape is needed,
  not merely a different indexing convention.
- **Write an island-local version instead**, when the piece is coupled to
  the owning island's own reducer's action types or state shape, even if
  it looks structurally or visually similar to something another island
  already has. `dashboard/components/ItemsToolbar.jsx`,
  `FilterDropdown.jsx`, `SortDropdown.jsx`, and `tracked_items/`'s own
  equivalents are this case: each dispatches its own island's
  `reducer.js`-specific action types and assumes its specific state shape
  (e.g. `dashboard/`'s in-memory `Pagination` usage assumes a fixed
  `PAGE_SIZE` and 1-based in-memory page index, while `inventories/`'s
  usage of the *same* shared `Pagination` component drives real
  server-side pages — the component is shared, the surrounding
  toolbar/reducer wiring is not). A second island with a materially
  different data-loading shape (e.g. one driving server-side pagination
  against a large catalog, where per-page size is user-selectable and
  every filter change triggers a new request instead of an in-memory
  re-slice) gets its own version of these, following the same
  presentational conventions (Component Conventions above) rather than
  generalizing the existing ones to serve incompatible state shapes
  through configuration.

Don't force a shared abstraction across islands just because two
components look alike — the dividing line is whether the *state
contract* is shared, not whether the *markup* is. And don't duplicate a
piece that passes the first test just because it currently has only one
consumer inside its original island — once a second island needs it
verbatim, move it to `shared/` rather than cross-importing from the
original island's directory (see Structure's `app/frontend/shared/`
subsection for why: an island's directory name describes that one
island, not a shared library, so a second cross-import is the signal to
extract, not a second place to import from).

## State & Data Loading

**UI state** (filters, sort, pagination, selection, open dropdown) is one
`useReducer(<name>Reducer, initialState)` **per page**, owned by that
page's root component — never one per tile/sub-component within a page,
and never shared across pages or islands. For a single-page island this
means exactly one reducer, owned by that island's root component
(`dashboardReducer`/`reducer.js` for `dashboard/`) — the rule this file
originally stated ("one reducer for the whole dashboard, not one per
tile") is the single-page instance of this same rule, written before
there was more than one page to have one of. For a multi-page island
(`admin-panel/`), each `<Resource>Page.jsx` owns its own reducer
(`itemsReducer`, `priceLogsReducer`, `userInventoriesReducer`,
`inventoryValueLogsReducer`) — four reducers total, not one shared across
all four pages and not one per table/toolbar/dropdown within a single
page either. The root component (`AdminPanel.jsx`) owns only navigation
state (which page is active, via `useHashRoute()`) — it is not where a
page's table/pagination/selection state lives, even though it's the
"root component" in the Structure sense.

Action types are flat strings (`'RANGE_CHANGED'`, `'ITEM_ROW_CLICKED'`,
`'WEAPON_FILTER_TOGGLED'`, ...), each returning a full new state object
via spread. Multi-select filter state is a plain object of `Set`s
(`{weapons: Set, conditions: Set, stattrakOnly: bool}`), toggled through a
shared `toggleSetMember` helper — follow this shape for a new
multi-select filter rather than inventing a different collection type.

**Data loading** is a custom hook per *distinct* data-loading need. For
the dashboard, there's exactly one need, so there's exactly one hook
(`useDashboardData(fetcherUrl, bridgeToken)`). For the admin panel, all
four pages have the *same* need — paginated reads against one of four
structurally identical `Api::Admin::` index endpoints, differing only in
resource path and per-page defaults — so this is one generic hook,
`useAdminList(resourcePath, { page, perPage })`, parametrized and reused
by every page, rather than four bespoke ones that would be identical
apart from a literal string. This isn't a deviation from "a custom hook
per data source" — it's the same rule applied to four sources that
happen to share one shape; a future admin resource whose data-loading
need is genuinely different (a nested/embedded sub-collection, a
non-paginated detail fetch) gets its own hook rather than being forced
into `useAdminList`. For a public, unauthenticated island (`inventories/`),
each distinct endpoint still gets its own hook
(`useInventoryCatalog`/`useInventoryDetail`) — no bridge token to thread
through, just `fetcherUrl` and that endpoint's own query params. A public
island's hooks are normally all against `app_fetcher`'s `Api::Public::`,
but it may have exactly one extra hook for an `app_core`-hosted endpoint
serving app_core-owned enrichment — see `architecture-layers.md`'s
app_core-owned enrichment carve-out: `inventories/`'s `useInventoryProfiles`
reads app_core's profile map (nickname/avatar) for the page's `steam_id`s
from the same-origin `/inventories/profiles`. Such a hook's failure must be
**non-fatal** — it resolves to an empty/degraded value and the page
renders its own fallback (`steam_id` + letter avatar) rather than entering
its error state, since the enrichment is additive to the `app_fetcher`-
sourced render, never a gate on it.

Regardless of island, every data-loading hook returns `{data, status,
error}` with `status` a flat string enum. Three rules that generalize
beyond today's exact handful of values:

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
  don't change whether the page is showable. Don't reach for this split
  just because an endpoint happens to be request-heavy, though — an
  endpoint that already returns one fully composed payload per request
  (`inventories/`'s detail endpoint) has nothing to split; a single flat
  status is correct there, not a smell to fix.
- A stage that fails after an earlier stage already produced showable
  data must not discard that data or force the whole hook back to an
  error state — only the specific stage's own status field reflects the
  failure. `status`/`data` regress to an error state only when the
  *first* (data-bearing) stage itself fails, since there is nothing
  meaningful to render without it.
- A status value beyond the generic `'error'` is justified when the UI
  genuinely renders something different for it — `inventories/`'s
  `useInventoryDetail` adds a `'not_found'` status (a 404 from
  `Api::Public::InventoriesController#show`) distinct from `'error'`,
  since the page shows a dedicated "this inventory isn't tracked" state
  rather than a generic failure message. Don't add a new status value for
  a failure mode the UI treats identically to an existing one.

## Mutations Against Nested Backend Routes

A flat/global list page (`PriceLogsPage`, `InventoryValueLogsPage` — see
`admin-api-controllers.md`'s flat-global-index pattern) reads from a
top-level, unnested endpoint, but the record it lists is still owned by a
nested resource on the backend — `PriceLog` only has a `destroy` route
nested under `item_id`, `InventoryValueLog` only has one nested under
`steam_id`; neither has a flat `destroy` route, only a flat `index`/
`global_index` read. A page's row action that mutates (delete, etc.) must
build the real nested URL using a parent key already present in that
row's own JSON (`item_id` for `PriceLog`, `steam_id` for
`InventoryValueLog`) — never assume a flat mutation route exists just
because the list read is flat. If a flat index's JSON doesn't yet carry
the parent key the nested route needs, add it there (the same category of
addition as `market_hash_name`/`steam_id` already added for display — see
`admin-api-controllers.md`), not a new flat mutation endpoint.

This was missed when `PriceLogsPage`/`InventoryValueLogsPage` were first
built — both called a flat `DELETE /api/admin/<resource>/:id` that was
never routed on the backend, caught only during manual browser
verification (Vitest mocks `fetch`, so a test asserting "the delete call
targets this URL" never validates that URL actually resolves to a real
Rails route). This rule generalizes that fix for any future flat/global
list page with a per-row mutation.

## Mutation Failure Handling

A mutation handler (`create`/`update`/`delete`/`refresh`/`sync`/cache-warm
— anything that calls `adminSend` (or the island's equivalent API wrapper)
and then refetches) must `catch` a rejected request and render the failure
inline in the page or form that triggered it. A rejected promise must
never escape the handler: an unhandled rejection leaves the operator with
no feedback and is not an acceptable "silent failure" mode for an
internal ops tool.

- **Keep the page's existing state.** A failed mutation renders the error
  without clearing the loaded list, pagination, selection, or open
  panel/menu — the same "a failed request surfaces an inline error
  without losing the rest of the page's state" contract the admin panel
  was built to meet. Do not fall back to the page-level load-error
  placeholder for a mutation failure; that placeholder means "there is
  nothing to render."
- **Form errors stay in the form.** Create/edit validation failures render
  inside the form that submitted them (the existing `createError` pattern
  in `ItemsPage`), not in a page-level banner.
- **Row/bulk errors use a page-level action error.** A failed row or
  toolbar mutation renders a page-level inline alert (not a toast,
  `alert()`, or `console.error`-only path), and the next mutation attempt
  clears the previous action error before dispatching.
- **Don't clear selection on failure.** Clear it only on a successful bulk
  action; a failed bulk action keeps the selection so the operator can
  retry.

Canonical: `admin-panel/pages/ItemsPage.jsx` — its create handler's
form-scoped error and its delete/refresh/cache handlers' page-level
`actionError` are the two branches of this rule.

## Charting: Recharts vs. hand-rolled SVG

Applies to any island's charts, not just the dashboard's — two different
tools for two different jobs, both already in the codebase — pick by
these criteria, don't default to "always use the charting library":

- **Recharts** (`shared/components/HeroChart.jsx`) for the one chart
  that needs axes, a tooltip, and real interactivity — it's rendered
  once per page view (dashboard's portfolio chart, an inventory detail
  page's portfolio chart, ...).
- **Hand-rolled inline SVG** (`shared/components/Sparkline.jsx`, used by
  `ItemRow` per row and by `inventories/`'s `InventoryItemRow`) for
  small, repeated, decorative visualizations with no axes/tooltip/legend.
  `Sparkline.jsx`'s own comment states the reasoning directly: it renders
  8-9+ times per page view, and a full charting-library instance per
  38×24px decorative line is the wrong tool for that multiplicity. Don't
  replace `Sparkline` with a Recharts-based mini-chart "for consistency"
  — the two exist for different rendering-cost profiles, not out of
  inconsistency.

## Styling

Plain CSS classes, BEM-ish naming (`tile`, `tile-hero`, `dropdown-panel`,
`chip`, `is-active`, `is-open`) — no CSS modules, no styled-components,
no Tailwind. Conditional classes are built with template-string
concatenation (`` `chip${active ? ' is-active' : ''}` ``), not a
`classnames`-style helper (none is a dependency).

**One stylesheet per island, plus one shared one.**
`shared/styles/tokens.css` holds the custom-property token block
(`--bg`, `--surface`, `--up`/`--down`, `--font-*`, `--radius-*`, etc.),
the font-face rules, and any chrome shared by more than one island's page
— the topbar, nav tabs, sign-in/sign-out markup — since that chrome is
rendered by plain ERB outside any one island and every island's page
loads it. A new island's own page-specific classes (its own tiles,
toolbar internals, list/grid layout) go in that island's own
`styles/<island>.css`, imported only by that island's own entrypoint —
not folded into `shared/styles/tokens.css`, which would otherwise
accumulate classes only one island ever uses, and not into
`dashboard/styles/dashboard.css` either, which is `dashboard/`'s own
page-specific stylesheet, not a second shared one. Every island's own
stylesheet relies on `shared/styles/tokens.css`'s custom properties
rather than redefining them, and every island's entrypoint imports
`shared/styles/tokens.css` before its own stylesheet.

## Testing

Applies to any island's tests. For a multi-page island, the "all tests
live flat under `__tests__/`" rule below still means one flat directory
per island, not one per page — `ItemsPage.test.jsx` sits next to
`PriceLogsPage.test.jsx`, the same way `ItemsTile.test.jsx` sits next to
`PortfolioTile.test.jsx` today.

Vitest (`vite.config.js`'s `test` block: `environment: 'jsdom'`,
`globals: true`, single setup file
`__tests__/setup.js` — which only pulls in
`@testing-library/jest-dom/vitest` matchers) + `@testing-library/react`
+ `@testing-library/user-event`. Every existing test file explicitly
`import { describe, test, expect } from 'vitest'` despite `globals:
true` being configured — follow that; don't rely on the implicit
globals even though they'd work.

### Structure

- All tests live flat under an island's own `__tests__/`, not colocated
  per-component — `ItemsTile.test.jsx` sits next to `filters.test.js`,
  not inside `components/`. Each island has its own `__tests__/`, and
  `shared/` has its own flat `__tests__/` too (`format.test.js` today) —
  there is no single cross-island test directory, the same way there is
  no shared cross-island `components/`/`utils/` beyond `shared/` itself.
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
  `ItemsTile.test.jsx`'s own header comment for the reasoning). For a
  root component that both owns the reducer *and* triggers its own data
  loading (e.g. `inventories/`'s `InventoriesIndex`/`InventoryDetail`,
  unlike `Dashboard.jsx` which delegates loading to a hook it merely
  calls), the same integration style applies directly to the root
  component itself — mock `fetch`, render the real component (no harness
  needed, since it already owns its own reducer), and drive it through
  `user-event`.

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

Every other island follows the identical shape against its own
`app_fetcher` namespace — `Api::Admin::*` with an admin bridge token for
`admin-panel/`, `Api::Public::*` with no auth header at all for
`inventories/` — see `architecture-layers.md` for the concrete per-stack
patterns.

## Canonical Implementations

- `app_core/app/frontend/dashboard/Dashboard.jsx`,
  `app_core/app/frontend/dashboard/reducer.js`
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js`
- `app_core/app/frontend/dashboard/components/ItemsTile.jsx` — the
  composition/derivation/testing pattern in one place
- `app_core/app/frontend/shared/components/Sparkline.jsx` vs.
  `app_core/app/frontend/shared/components/HeroChart.jsx` — the
  charting-tool boundary
- `app_core/app/frontend/shared/utils/trend.js` — the shared `up`/`down`/
  `flat` trend-direction helper every island's item row derives through
  (see Component Conventions)
- `app_core/app/frontend/shared/utils/priceFreshness.js` — the shared
  24-hour stale-price predicate/age label used by both islands' item
  rows (see Component Conventions)
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx`,
  `app_core/app/frontend/inventories/components/PortfolioHeroTile.jsx` —
  the hero-delta zero-hiding guard (see Component Conventions)
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx`,
  `useDashboardData.test.js`, `portfolioSeries.test.js`
- `app_core/app/frontend/admin-panel/AdminPanel.jsx`,
  `app_core/app/frontend/admin-panel/useHashRoute.js`,
  `app_core/app/frontend/admin-panel/adminApi.js`,
  `app_core/app/frontend/admin-panel/hooks/useAdminList.js` — the
  multi-page structure, per-page reducers, and shared data-loading hook
- `app_core/app/frontend/inventories/InventoriesIndex.jsx`,
  `app_core/app/frontend/inventories/InventoryDetail.jsx` — two
  single-page root components sharing one island, each owning its own
  reducer and hook, both reading `shared/` components directly; also the
  canonical root-component-owns-its-own-fetch integration test pattern
  (see Testing)
- `app_core/app/frontend/inventories/hooks/useInventoryProfiles.js` — the
  one sanctioned non-`app_fetcher` (app_core-owned enrichment) hook and
  its non-fatal failure fallback (see State & Data Loading)
- `app_core/app/frontend/inventories/components/InventoryCard.jsx` — an
  aggregate card delta deriving through `trendDirection` and hiding its
  badge when flat (see Component Conventions)
- `app_core/app/frontend/inventories/utils/rarity.js` — a pure derivation
  module with no reducer/state coupling, kept island-local (not moved to
  `shared/`) since `inventories/` remains its only consumer
- `app_core/eslint.config.js`, `app_core/.prettierrc` — the lint/format
  stack (see Linting & Formatting)

## Related ADR

- `agent/adr/core/multiple-react-islands.md` — why a second top-level
  feature is a new sibling island rather than a mode inside an existing
  one, the pure/stateless-vs-reducer-coupled test behind Reuse Across
  Islands above, and why the `shared/` extraction was deferred until a
  third island's concrete need confirmed it.
- `agent/adr/core/sparkline-vs-recharts.md` — why Recharts is scoped to
  the one hero chart and repeated sparklines are hand-rolled SVG instead.
- `agent/adr/core/component-tests-real-reducer.md` — why composite
  component tests drive a real `dashboardReducer` instead of mocking
  callback props.
