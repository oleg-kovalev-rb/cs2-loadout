---
status: implemented
app: core
goal: Build app_core frontend pages for the public inventories list and public inventory detail, backed by app_fetcher's existing api/public/inventories endpoints
created: 2026-10-12
---

# Development Plan

## Goal

Add two new public, ungated pages to `app_core` — an inventories list page
and an inventory detail page — that render the design concept in
`FLOAT — Inventories.html` using data from app_fetcher's already-shipped
`GET /api/public/inventories` and `GET /api/public/inventories/:steam_id`
endpoints. No app_fetcher changes are in scope.

## Expected Behavior

### Normal behavior

- `GET /inventories` renders a paginated grid of public inventories
  (steam_id, total value, 24h change, item count, rarity mix bar, last
  synced time), sortable by value / item count / recently synced / 24h
  change, matching `Options::InventorySortOption`.
- Clicking a card navigates (full Turbo visit, real `<a href>`) to
  `/inventories/:steam_id`.
- `GET /inventories/:steam_id` renders: a portfolio-value hero chart with
  a range toggle (`24h`/`7d`/`30d`/`1y`/`all`, matching `PricePeriod`
  exactly — see Risks for the 24h caveat), three stat tiles (items count,
  avg item value, priciest item), a rarity breakdown (bar + legend with
  counts/percents), and a sortable, paginated top-items list with a
  per-item 7-day sparkline, matching `Options::ItemSortOption`.
- A link back to `/inventories` is always visible on the detail page.
- Both pages are reachable **without signing in** — no sign-in wall, no
  bridge token minted or required, since the backing endpoints are
  genuinely unauthenticated.
- The topbar gains "Portfolio" / "Inventories" nav tabs, shared across
  all three pages (`/`, `/inventories`, `/inventories/:steam_id`), with
  the current page's tab marked active. "Portfolio" still requires
  sign-in (unchanged existing behavior); "Inventories" never does.
- The index page's search field is present but disabled with a "coming
  soon" placeholder/tooltip — it performs no request (the backend
  ignores `search` entirely, since nickname isn't stored in app_fetcher).

### Edge cases / failure behavior

- Unknown `steam_id` on the detail page: app_fetcher returns 404; the
  page renders a distinct "this inventory isn't tracked" state (not the
  generic error state), with a link back to `/inventories`.
- Generic fetch failure (network/5xx) on either page: a simple error
  message, matching the dashboard's existing error-state convention.
- Empty inventories catalog (zero results): grid renders an empty state
  instead of an empty card grid.
- `priciest_item` may be `null` (empty inventory) — the priciest-item
  stat tile must handle this without crashing.

### Must remain unchanged

- The existing `/` dashboard page's behavior, sign-in gating, and all
  currently-passing specs (`spec/requests/dashboards_spec.rb`).
- `app_fetcher` is not modified at all.

## Scope

### In Scope

- New Rails route, controller, and views in `app_core` for
  `/inventories` and `/inventories/:steam_id`.
- A shared topbar/nav partial, extracted from the dashboard's view and
  reused by all three pages (this requires editing
  `app/views/dashboards/show.html.erb`, since it has no nav tabs today).
- Two new Vite entrypoints + a new `app/frontend/inventories/` React
  island (components, hooks, reducer, styles, tests), following the
  existing dashboard island's conventions.
- Extracting the handful of dashboard components/utilities that are
  fully generic and directly reusable (`Sparkline`, `RangeToggle`,
  `Pagination`, `HeroChart`, `ChartTooltip`, `format.js`, fonts, and the
  generic half of `chartConfig.js`) into a new `app/frontend/shared/`
  directory, so the new island doesn't duplicate them. This touches the
  existing dashboard island's import paths but not its behavior.
- Request specs for the new routes; Vitest unit/integration tests for
  the new React code.

### Out of Scope

- Any change to `app_fetcher` (routes, controllers, serializers,
  queries) — the API is already complete for this feature.
- Making the nickname search field functional (no backend support
  exists; it stays a disabled placeholder per explicit product decision).
- Any new app_core-side persistence, model, or background job — these
  pages render entirely from client-side fetches to app_fetcher.
- A client-side router / SPA-style view switching between list and
  detail (the static mockup's JS toggle) — real Turbo navigation between
  two real Rails routes is used instead, per explicit product decision.
- Enriching public inventories with app_core's own `User` data
  (nickname/avatar) — already decided against in
  `[[feedback_no_cross_app_profile_duplication]]`; cards/detail identify
  by `steam_id` only.

## Implementation Approach

### Rails routing & views

Add a standard resourceful route:

```ruby
resources :inventories, only: %i[index show], param: :steam_id
```

`InventoriesController` is a thin, routing-only shell (per
`architecture-layers.md` — no model access, no action/lib involved,
since there is nothing app_core-side to fetch; all data comes from the
browser calling app_fetcher directly, same as the dashboard). Both
actions just render; `show` doesn't need to validate `steam_id` servers-side
— a non-existent id simply results in app_fetcher returning 404 to the
client fetch, handled by the React island's own not-found state.

Neither view mints a bridge token or passes one to the client — `GET
api/public/inventories*` takes no `Authorization` header at all (unlike
the dashboard's `api/v1/*` calls). Views only embed
`APP_FETCHER_PUBLIC_URL` (and, for `show`, the `steam_id` path param) as
data attributes.

The dashboard's topbar markup (brand, profile chip, sign-in state) is
extracted into `app/views/shared/_topbar.html.erb`, parameterized by
`active_nav:` (`:portfolio` or `:inventories`), and gains the nav-tabs
markup the static mockup has but the current app doesn't
(`nav-tabs`/`nav-tab`/`is-active`, styled by the already-existing
`.nav-tabs`/`.nav-tab` CSS — those rules exist in the mockup's CSS and
should be ported into the shared stylesheet, see below). `Portfolio`
links to `root_path`; `Inventories` links to `inventories_path`. Both
`dashboards/show.html.erb` and the two new inventories views render this
partial.

### Frontend: `shared/` extraction

`react-dashboard.md` documents a single island's structure and doesn't
yet anticipate a second one. Five dashboard components
(`Sparkline.jsx`, `RangeToggle.jsx`, `Pagination.jsx`, `HeroChart.jsx`,
`ChartTooltip.jsx`) and `utils/format.js` have no dashboard-specific
knowledge baked in — they take plain data/callbacks and are exactly
what the new island needs (identical chart, sparkline, pagination, and
formatting behavior). Rather than duplicating ~400 lines of components
and CSS tokens, or having `inventories/` cross-import from a sibling
directory named `dashboard/` (semantically confusing), move these into
a new `app/frontend/shared/` directory:

- `shared/fonts/` — the 4 `.woff2` files (moved from `dashboard/fonts/`).
- `shared/styles/tokens.css` — the font-face rules, the `.dash-root`
  design-token block, and the genuinely page-agnostic primitives
  (topbar/nav-tabs, tile/card shell, dropdown, range-toggle, pager,
  tag/rarity-dot) extracted from `dashboard/styles/dashboard.css`. Both
  `dashboard.css` and the new `inventories.css` build on top of this.
- `shared/utils/format.js` (moved as-is).
- `shared/chartConfig.js` — only the generic pieces (`RANGE_MS`,
  `X_AXIS_TICK_COUNT`, `Y_AXIS_TICK_COUNT`, `generateAxisLabels`).
  `PORTFOLIO_RANGES`/`ITEM_RANGES` (dashboard's specific range-set
  choices, with their daily-granularity-caveat comment) stay in a
  trimmed-down `dashboard/chartConfig.js`.
- `shared/components/{Sparkline,RangeToggle,Pagination,HeroChart,ChartTooltip}.jsx`
  (moved as-is; their internal imports updated to the new `shared/`
  locations).
- `shared/__tests__/format.test.js` (moved as-is).

`Pagination.jsx` keeps its existing 0-indexed, client-slicing contract
unchanged — the inventories hooks/components translate app_fetcher's
1-indexed `meta.page` at the call site (`page: meta.page - 1` in,
`onNext`/`onPrev` do `± 1` then convert back when calling the API).
This avoids forking pagination logic or touching `Pagination`'s existing
(absent) test surface.

This is flagged explicitly for `styleguides-check`: `react-dashboard.md`
should be amended to document `shared/` as the home for cross-island
primitives, since it currently only describes one island.

### Frontend: `app/frontend/inventories/` (new island)

Mirrors `dashboard/`'s structure (per `react-dashboard.md`'s existing
conventions — named exports only, presentational components, derived
data in `utils/`, one reducer per root component, hooks own all
`fetch` calls, mapping from snake_case API JSON to the island's own
camelCase shape done inline in the hook, matching `useDashboardData.js`'s
`mapItem` precedent):

```text
app/frontend/inventories/
  InventoriesIndex.jsx        — root for /inventories
  InventoryDetail.jsx         — root for /inventories/:steam_id
  reducer.js                  — catalogReducer + detailReducer (two
                                 small reducers, one per root component,
                                 each with its own initialState)
  chartConfig.js               — INVENTORY_DETAIL_RANGES = ['24h','7d',
                                 '30d','1y','all'] (+ a comment on the
                                 24h/daily-granularity tension — see Risks)
  hooks/
    useInventoryCatalog.js     — GET /api/public/inventories
    useInventoryDetail.js      — GET /api/public/inventories/:steam_id
  components/
    InventoriesToolbar.jsx     — disabled search field + InventorySortDropdown
    InventorySortDropdown.jsx  — value_desc/items_desc/recently_synced/change_24h_desc
    InventoryGrid.jsx          — grid wrapper + empty state
    InventoryCard.jsx          — one catalog card (rank computed client-side
                                 from meta.page/meta.per_page + index, since
                                 the API has no rank field; identity shown as
                                 steam_id, no name/avatar)
    RarityMixBar.jsx           — the thin bar (used on cards AND the detail tile)
    RarityLegend.jsx           — dot/name/count/percent rows (detail page only)
    PortfolioHeroTile.jsx      — value + range toggle + shared HeroChart
                                 (read-only — no item-mode toggle, unlike
                                 dashboard's PortfolioTile)
    StatTile.jsx               — generic small stat box (items/avg/priciest)
    TopItemsList.jsx           — sortable, server-paginated items list
    InventoryItemRow.jsx       — one row: icon, name+tags, Sparkline(trend_7d),
                                 price+24h delta
    InventoryDetailSkeleton.jsx — loading state
    InventoryNotFound.jsx       — 404 state, link back to /inventories
  utils/
    rarity.js                  — single source of truth: tier order,
                                 display label, and CSS-var name per tier
                                 key (handles the `mil_spec` API key vs.
                                 `--rarity-milspec` CSS var naming mismatch)
  styles/
    inventories.css            — page-specific rules only (card grid,
                                 hero/stat/rarity/top-items tile layout),
                                 built on `shared/styles/tokens.css`
  __tests__/                   — flat, mirrors dashboard/__tests__
```

Each root component owns one `useReducer` (catalog state: `sort`, `page`,
`openDropdown`; detail state: `range`, `itemsSort`, `itemsPage`,
`openDropdown`) and one data-loading hook. Unlike the dashboard's
multi-hook progressive-hydration design (which exists because that
page's data genuinely arrives in independently-resolving stages), the
detail endpoint already returns one fully composed JSON payload per
request — so `useInventoryDetail` is a single hook with a flat
`'loading'|'success'|'error'|'not_found'` status, refetching whenever
`steamId`/`range`/`itemsSort`/`itemsPage` change. Do not replicate
dashboard's multi-hook split here; it would solve a problem this page
doesn't have.

Two new Vite entrypoints (`entrypoints/inventories_index.jsx`,
`entrypoints/inventory_detail.jsx`) each import
`shared/styles/tokens.css` + `inventories/styles/inventories.css`, then
mount `InventoriesIndex`/`InventoryDetail` onto their root divs — same
shape as `entrypoints/dashboard.jsx`.

## Files To Modify

- `app_core/config/routes.rb` — add
  `resources :inventories, only: %i[index show], param: :steam_id`.
- `app_core/app/views/dashboards/show.html.erb` — replace the inline
  topbar markup with `render "shared/topbar", active_nav: :portfolio`.
- `app_core/app/frontend/entrypoints/dashboard.jsx` — update the CSS
  import to include `shared/styles/tokens.css` alongside
  `dashboard/styles/dashboard.css`.
- `app_core/app/frontend/dashboard/styles/dashboard.css` — remove the
  font-face rules and page-agnostic primitives now living in
  `shared/styles/tokens.css`; keep only dashboard-page-specific rules.
- `app_core/app/frontend/dashboard/chartConfig.js` — trim to
  `PORTFOLIO_RANGES`/`ITEM_RANGES` only.
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx` —
  update imports: `format`/`RangeToggle`/`HeroChart` from `../../shared/...`.
- `app_core/app/frontend/dashboard/components/ItemRow.jsx` — update
  imports: `Sparkline`/`format` from `../../shared/...`.
- `app_core/app/frontend/dashboard/components/FilterDropdown.jsx` —
  update import: `format` from `../../shared/...`.
- `app_core/app/frontend/dashboard/components/ItemsTile.jsx` — update
  import: `Pagination` from `../../shared/...`.
- Delete (superseded by `shared/`): `dashboard/fonts/*`,
  `dashboard/utils/format.js`,
  `dashboard/components/{Sparkline,RangeToggle,Pagination,HeroChart,ChartTooltip}.jsx`,
  `dashboard/__tests__/format.test.js`.

## Files To Create

- `app_core/app/controllers/inventories_controller.rb` — `index`/`show`,
  routing-only.
- `app_core/app/views/inventories/index.html.erb`,
  `app_core/app/views/inventories/show.html.erb` — render shared topbar
  + root div with `data-fetcher-url` (+ `data-steam-id` for `show`) +
  vite entrypoint tag.
- `app_core/app/views/shared/_topbar.html.erb` — extracted topbar, with
  nav tabs.
- `app_core/spec/requests/inventories_spec.rb` — request specs (see Test Plan).
- `app_core/app/frontend/shared/fonts/*.woff2`,
  `shared/styles/tokens.css`, `shared/utils/format.js`,
  `shared/chartConfig.js`,
  `shared/components/{Sparkline,RangeToggle,Pagination,HeroChart,ChartTooltip}.jsx`,
  `shared/__tests__/format.test.js` — moved from `dashboard/` (see above).
- `app_core/app/frontend/entrypoints/inventories_index.jsx`,
  `app_core/app/frontend/entrypoints/inventory_detail.jsx`.
- `app_core/app/frontend/inventories/` — full new island as laid out in
  Implementation Approach (`InventoriesIndex.jsx`, `InventoryDetail.jsx`,
  `reducer.js`, `chartConfig.js`, `hooks/useInventoryCatalog.js`,
  `hooks/useInventoryDetail.js`, `components/*.jsx` listed above,
  `utils/rarity.js`, `styles/inventories.css`, `__tests__/*`).

## Test Plan

### Rails (RSpec request specs)

- `spec/requests/inventories_spec.rb`:
  - `GET /inventories` renders 200 when signed out and when signed in
    (no sign-in wall); response includes nav tabs with "Inventories"
    marked active; response does **not** include `data-bridge-token`.
  - `GET /inventories/:steam_id` renders 200 regardless of whether that
    steam_id exists in app_fetcher (Rails never validates it — the
    React island's own fetch handles the 404 case); embeds the
    `steam_id` as a data attribute; no `data-bridge-token`.
  - Topbar: "Portfolio" tab marked active on `/`, "Inventories" tab
    marked active on both new routes.
- Re-run `spec/requests/dashboards_spec.rb` unchanged — confirms the
  topbar extraction didn't alter the dashboard's existing sign-in/
  sign-out/avatar assertions.

### Frontend (Vitest)

- `shared/__tests__/format.test.js` — moved, same assertions.
- `inventories/__tests__/reducer.test.js` — `catalogReducer`
  (`SORT_CHANGED` resets `page`, `PAGE_CHANGED`, dropdown toggling) and
  `detailReducer` (`RANGE_CHANGED`, `ITEMS_SORT_CHANGED` resets
  `itemsPage`, `ITEMS_PAGE_CHANGED`, dropdown toggling) — pure, no
  rendering.
- `inventories/__tests__/rarity.test.js` — tier order, label, and
  CSS-var mapping, including the `mil_spec` → `--rarity-milspec` case.
- `inventories/__tests__/useInventoryCatalog.test.js` — `vi.stubGlobal`
  fetch mock: success mapping, loading→success, error on non-ok,
  refetch on page/sort change.
- `inventories/__tests__/useInventoryDetail.test.js` — same pattern,
  plus: 404 response maps to a distinct `not_found` status (not generic
  `error`); refetch on `steamId`/`range`/`itemsSort`/`itemsPage` change.
- `inventories/__tests__/InventoryCard.test.jsx` — rank computation
  from page/index, up/down delta direction, rarity-mix segment widths.
- `inventories/__tests__/InventoryItemRow.test.jsx` — icon-present vs.
  icon-missing placeholder (same pattern as `ItemRow.test.jsx`),
  stattrak tag, delta direction.
- `inventories/__tests__/InventoriesIndex.test.jsx` — integration-style
  harness with a real `catalogReducer`: changing sort / page triggers
  the expected re-fetch params and re-renders the grid; empty-result
  state.
- `inventories/__tests__/InventoryDetail.test.jsx` — integration-style
  harness with a real `detailReducer`: range toggle and items-sort/
  pagination trigger expected re-fetch params; `priciest_item: null`
  doesn't crash the stat tile; 404 renders `InventoryNotFound`.

## Implementation Steps

1. Rails: add the `inventories` route; create `InventoriesController`;
   extract `shared/_topbar.html.erb` (with nav tabs) out of
   `dashboards/show.html.erb` and re-render it from both the dashboard
   view and the two new inventories views; write
   `spec/requests/inventories_spec.rb`; confirm
   `spec/requests/dashboards_spec.rb` still passes unchanged.
2. Frontend `shared/` extraction: create `app/frontend/shared/`, move
   fonts/format/the generic half of chartConfig/Sparkline/RangeToggle/
   Pagination/HeroChart/ChartTooltip/their test into it, update every
   dashboard import site and `dashboard.css`/`dashboard.jsx` listed
   above, delete the superseded originals. Run the full existing
   frontend test suite (`npm test`) to confirm zero regressions before
   building anything new on top.
3. Build the index page: `reducer.js` (catalog half), entrypoint hooked
   up to Rails view, `useInventoryCatalog`, `InventoryCard`/`InventoryGrid`/
   `InventoriesToolbar`/`InventorySortDropdown`/`RarityMixBar`,
   `utils/rarity.js`, `inventories.css` (card-grid rules), wiring
   `InventoriesIndex.jsx` together. Write tests alongside each piece.
4. Build the detail page: `reducer.js` (detail half), entrypoint,
   `useInventoryDetail`, `PortfolioHeroTile` (reusing shared
   `HeroChart`/`RangeToggle` with `INVENTORY_DETAIL_RANGES`), `StatTile`,
   `RarityLegend` (reusing `RarityMixBar`), `TopItemsList`/
   `InventoryItemRow` (reusing shared `Sparkline`/`Pagination`),
   `InventoryDetailSkeleton`, `InventoryNotFound`, wiring
   `InventoryDetail.jsx` together. Write tests alongside each piece.
5. Wire the Turbo navigation: `InventoryCard` renders a real
   `<a href={`/inventories/${steamId}`}>`; the detail page's back-link
   is a real `<a href="/inventories">`. No client router, no
   `onClick`/`preventDefault` — plain anchors, Turbo Drive handles the
   rest.
6. Manual verification against a running dev stack (see Verification).
7. Note for `styleguides-check`: amend `react-dashboard.md` to document
   the new `shared/` directory and the `inventories/` island's structure
   (it currently only describes a single-island layout).

## Verification

- `bundle exec rspec spec/requests/inventories_spec.rb spec/requests/dashboards_spec.rb`
  (app_core).
- `npm test` (Vitest, app_core) — full suite, confirming both the moved
  `shared/` tests and the new `inventories/` tests pass, and nothing in
  the existing dashboard suite broke from the import-path changes.
- `bin/rubocop` / existing lint tooling on touched Ruby files, if
  configured for app_core (match whatever the repo already runs in CI).
- Manual check with the dev server running both apps: load
  `/inventories` (sorting, pagination, card → detail navigation, nav
  tabs, disabled search field), then `/inventories/:steam_id` for a real
  seeded public inventory (range toggle including `24h`, stat tiles,
  rarity legend, top-items sort/pagination, sparkline rendering) and for
  a non-existent steam_id (not-found state); repeat both pages while
  signed out and signed in to confirm no gating and correct nav-tab
  active state either way.

## Risks

- **`24h` range may render a near-flat/sparse chart.** The detail
  endpoint's history comes from `InventoryValueLog`, the same
  daily-granularity table `dashboard/chartConfig.js`'s existing comment
  says makes a 24h view "not meaningful" for the dashboard's own
  portfolio chart. Included anyway per explicit decision to match the
  endpoint's full formal capability (`PricePeriod` accepts `24h`) — this
  is a known, accepted tradeoff, not an oversight.
  See `[[project_price_cache_rework_planned]]` for related
  known-temporary backend behavior in this area.
- **`shared/` extraction touches previously-stable dashboard code.**
  Mechanical (import paths + file moves only, no behavior change) but
  real files move; mitigated by running the full existing test suite
  immediately after the move (step 2) before any new feature code is
  built on top of it.
- **No rank field from the API.** Client-side rank computation
  (`(meta.page - 1) * meta.per_page + index + 1`) is correct only as
  long as sort order is stable across the request; fine for a
  cache-backed, 2-minute-TTL read-only list, but would need revisiting
  if the catalog ever became more dynamic.

## Assumptions

- Turbo Drive is active in `app_core` (per `CLAUDE.md`'s description of
  the stack) such that a plain same-origin `<a href>` inside the React
  island gets intercepted and handled as a full-page Turbo visit with no
  extra wiring — not independently re-verified beyond that description.
- `per_page`/`items_per_page` are fixed constants (24 and 12,
  app_fetcher's own defaults) with no UI control to change them — the
  mockup has no such control either.

## Applicable Styleguides

- `.claude/styleguides/rails-layering.md` — constrains
  `InventoriesController` staying thin (routing/rendering only; no
  business logic beyond the `current_user` lookup already allowed
  directly in a controller).
- `.claude/styleguides/rspec-conventions.md` — constrains
  `spec/requests/inventories_spec.rb`: `type: :request` metadata,
  mirrors `dashboards_spec.rb`'s existing pattern (this is `app_core`'s
  canonical "HTML controller → request spec" example), explicit
  `aggregate_failures` block once an example exceeds 3 expectations.
- `.claude/styleguides/ruby-sorbet.md` — constrains
  `InventoriesController`: `# typed: strict`, `extend T::Sig`, a `sig`
  on both `index` and `show`.
- `.claude/styleguides/core/erb-interaction-patterns.md` — constrains
  the sign-out confirm-overlay markup carried over unchanged into
  `app/views/shared/_topbar.html.erb` (anchor-link `:target` shape,
  trigger stays a plain `<a>`, no Stimulus).
- `.claude/styleguides/core/architecture-layers.md` (amended) —
  constrains: `InventoriesController` has no `require_login` guard
  (reachable signed-in or signed-out); the new island's hooks call
  `Api::Public::*` with no `Authorization` header and no bridge token
  minted or embedded anywhere; `app/views/shared/_topbar.html.erb`
  rendered by `DashboardsController#show` and both
  `InventoriesController` actions alike.
- `.claude/styleguides/core/react-dashboard.md` (amended) —
  constrains: what moves into `app/frontend/shared/` and the
  `dashboard/chartConfig.js` vs. `shared/chartConfig.js` split;
  `inventories/` as a sibling island following the same Component/
  Derived-Data/State/Testing conventions as `dashboard/`, one reducer
  per root component; reusing `shared/components/Pagination.jsx`
  as-is via call-site index translation instead of forking it.
- `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md`
  — constrains: no `app_core` proxy endpoint for inventories data;
  both islands read `app_fetcher` directly from the browser.
- `.claude/adr/core/sparkline-vs-recharts.md` — constrains: reusing
  the existing `HeroChart`/`Sparkline` split as-is for the detail
  page's portfolio chart and per-item sparklines; no new charting
  decision to make.
- `.claude/adr/core/component-tests-real-reducer.md` — constrains:
  `InventoriesIndex.test.jsx`/`InventoryDetail.test.jsx` drive real
  `catalogReducer`/`detailReducer` instances, not mocked callback props.
- `.claude/adr/core/erb-overlays-over-stimulus.md` — constrains: the
  relocated sign-out confirm overlay stays zero-JS/CSS-`:target`-based.

## Completion Criteria

- Desired behavior, scope, affected files, test strategy, and
  implementation steps are all explicit above.
- Plan written to `.claude/plans/inventories-pages-frontend.md`.

# Implementation Summary

## Implemented

- **Rails**: `resources :inventories, only: %i[index show], param: :steam_id`
  in `config/routes.rb`; a thin `InventoriesController` (`# typed: strict`,
  no model access, no `require_login` guard); `app/views/inventories/
  {index,show}.html.erb`; `app/views/shared/_topbar.html.erb` extracted
  from the dashboard's inline topbar, gaining "Portfolio"/"Inventories"
  nav tabs (`link_to`, `active_nav:` local) and re-rendered from both
  `dashboards/show.html.erb` and the two new views.
- **Frontend `app/frontend/shared/`** (new cross-island directory): moved
  `fonts/`, `utils/format.js`, the generic half of `chartConfig.js`
  (`RANGE_MS`, tick counts, `generateAxisLabels`), and
  `components/{Sparkline,RangeToggle,Pagination,HeroChart,ChartTooltip}.jsx`
  out of `dashboard/`. Split `dashboard.css` into `shared/styles/
  tokens.css` (fonts, design tokens, topbar/nav-tabs, tile/card shell,
  dropdown, range-toggle, pager, mover-row/tag primitives) and a trimmed
  `dashboard.css` (dashboard-specific grid/filters/footer only). Updated
  every dashboard import site (`PortfolioTile`, `ItemRow`,
  `FilterDropdown`, `ItemsTile`, `dashboard.jsx`) accordingly.
- **Frontend `app/frontend/inventories/`** (new island): `reducer.js`
  (`catalogReducer` + `detailReducer`), `chartConfig.js`
  (`INVENTORY_DETAIL_RANGES` including `24h`), `hooks/
  {useInventoryCatalog,useInventoryDetail}.js` (both unauthenticated —
  no bridge token, no `Authorization` header), `utils/rarity.js`
  (tier order/label/CSS-var mapping), and components: `InventoryCard`,
  `InventoryGrid`, `InventoriesToolbar` (disabled "coming soon" search),
  `InventorySortDropdown`, `RarityMixBar`, `PortfolioHeroTile`,
  `StatTile`, `RarityLegend`, `TopItemsList`, `ItemsSortDropdown`,
  `InventoryItemRow`, `InventoryDetailSkeleton`, `InventoryNotFound`.
  Root components `InventoriesIndex.jsx`/`InventoryDetail.jsx`, wired to
  two new Vite entrypoints (`inventories_index.jsx`, `inventory_detail.jsx`)
  and `inventories/styles/inventories.css`.
- Card → detail navigation and the detail page's back-link are plain
  `<a href>` elements (Turbo Drive handles the visit); no client router.

## Tests

- `app_core/spec/requests/inventories_spec.rb` (new, 4 examples): no
  sign-in wall, no `data-bridge-token`, correct active nav tab on both
  routes, `data-steam-id` embedded on the detail view.
- Full Vitest suite grew from 67 → 109 tests across 20 files, including
  new: `rarity.test.js`, `reducer.test.js` (catalog + detail),
  `useInventoryCatalog.test.js`, `useInventoryDetail.test.js`,
  `InventoryCard.test.jsx`, `InventoryItemRow.test.jsx`,
  `RarityLegend.test.jsx`, `InventoriesIndex.test.jsx` (integration,
  mocked `fetch`, real `catalogReducer`), `InventoryDetail.test.jsx`
  (integration, mocked `fetch`, real `detailReducer`, covers the
  `priciest_item: null` and 404/not-found cases). `shared/
  __tests__/format.test.js` moved from `dashboard/__tests__/` unchanged.
- TDD followed throughout: every new reducer/hook/component with
  branching logic had its test written and run red (missing module /
  wrong behavior) before the implementation made it green — confirmed
  via actual `vitest run` output at each step, not assumed.

Commands actually executed (via `docker compose -p steam_project run
--rm --no-deps app_core ...`, reusing the base repo's shared Postgres/
Redis containers — see Deviations):

- `bundle exec rspec spec/requests/inventories_spec.rb` (red, then green)
- `bundle exec rspec spec/requests/dashboards_spec.rb spec/requests/
  inventories_spec.rb` (11 examples, 0 failures) after the Rails step
- `npm test` (full Vitest suite) after the `shared/` extraction and
  again after each page — 67 → 87 → 109 tests, all green at each stage
- `bundle exec rubocop config/routes.rb app/controllers/
  inventories_controller.rb spec/requests/inventories_spec.rb` — no
  offenses
- `bundle exec srb tc` — confirmed the new controller introduces zero
  new Sorbet errors (25 pre-existing errors, all already logged in
  `fix_me.md`, unchanged)
- `bundle exec rspec --exclude-pattern "spec/lib/admin/bridge_token_spec.rb"`
  (full suite) — 27 examples, 0 failures

## Verification

- **RSpec**: 27/27 examples pass (full suite minus one pre-existing,
  unrelated failure — see Deviations).
- **Vitest**: 109/109 tests pass across 20 files.
- **Rubocop**: 0 offenses on all 3 touched/new Ruby files.
- **Sorbet (`srb tc`)**: 0 new errors introduced by `InventoriesController`.
- **Manual browser verification**: not performed. Port 3000 (app_core)
  was already held by another process on this shared host at
  verification time; per user decision, skipped in favor of the fully
  green automated suite rather than risking further disruption to
  shared infrastructure (see Deviations).
- **Final diff review**: `git diff --stat` shows exactly the files the
  plan's "Files To Modify"/"Files To Create" sections named (23 modified
  — including 7 pure file-moves with no content change recognized by
  `git` as renames — + 10 new paths), no debug code (`console.*`,
  `debugger`) or TODO/FIXME left in the new `inventories/`/`shared/`
  code.

## Deviations

- **Shared Postgres/Redis containers, not a per-worktree stack.** This
  host runs multiple concurrent sessions against the same
  `docker-compose.yml`, which hardcodes host ports (redis `6380`, app_core
  `3000`). An early attempt to bring up this worktree's own stack
  collided with the base repo's already-running containers; recreating
  them under the base repo's project name (`steam_project`) to restore
  their original bind mounts fixed it (confirmed via `docker inspect`).
  All subsequent Ruby test runs used `docker compose -p steam_project
  run --rm --no-deps app_core ...` to reuse that shared `db_core`/`redis`
  pair rather than attempting another isolated stack. This is
  environmental, not a plan change.
- **Manual browser verification skipped.** Per the plan's Verification
  section, a live click-through of both pages (signed-in/out, sort,
  pagination, range toggle, 404 state) was planned. Port 3000 was
  occupied by an unrelated process on this shared host; rather than
  freeing it unilaterally, the user was asked and chose to rely on the
  automated suite instead. Not independently re-verified beyond that
  decision.
- **One pre-existing, unrelated RSpec failure left as-is**:
  `spec/lib/admin/bridge_token_spec.rb` (3 examples) fails in this
  environment because `APP_ADMIN_BRIDGE_JWT_SECRET` isn't wired into
  `docker-compose.yml`'s `app_core` service `environment:` block (only
  `APP_BRIDGE_JWT_SECRET` is). Confirmed unrelated to this plan: the file
  isn't touched by it, predates it, and `.env.example` doesn't mention
  the var either. Not fixed here — it's a shared docker-compose/env
  config gap, out of scope for a frontend feature plan.
- **`ItemsSortDropdown.jsx` added**, not explicitly named in the
  original "Files To Create" list, but required by `TopItemsList.jsx`'s
  planned sort capability (a distinct option set — `price_desc/
  price_asc/name_asc/change_24h_desc` — from the index page's
  `InventorySortDropdown`, per the plan's own note that these are "two
  separate option sets, not one shared component's config").
- **No dedicated test files for `InventoryGrid.jsx`, `TopItemsList.jsx`,
  `InventoriesToolbar.jsx`, `InventorySortDropdown.jsx`,
  `ItemsSortDropdown.jsx`, `RarityMixBar.jsx`, `StatTile.jsx`,
  `PortfolioHeroTile.jsx`, `InventoryDetailSkeleton.jsx`,
  `InventoryNotFound.jsx`** — each is either a thin presentational leaf
  (no branching worth isolating) or an orchestrating component whose
  wiring is covered by the root `InventoriesIndex.test.jsx`/
  `InventoryDetail.test.jsx` integration tests, matching
  `react-dashboard.md`'s existing "what gets a dedicated test file" line
  (`SortDropdown`/`Pagination`/`RangeToggle`/`HeroChart` have none today
  either).

## Remaining Issues

- Live browser verification of both pages (signed-in/out states, sort,
  pagination, the `24h` range toggle, the 404/not-found state, the
  disabled search field) is still genuinely outstanding — the user
  opted to skip it for this session rather than fight the shared host's
  port contention. Worth doing once a free port/environment is
  available.
- The ADR question raised during `styleguides-check` (whether the new
  `app/frontend/shared/` directory warrants its own ADR, comparable to
  `sparkline-vs-recharts.md`) was never explicitly answered — no ADR was
  created. Revisit if a third island/consumer makes the `shared/`
  boundary a recurring decision point worth writing down.
- `APP_ADMIN_BRIDGE_JWT_SECRET` missing from `docker-compose.yml`'s
  `app_core.environment` block (pre-existing, logged above) — a
  one-line docker-compose fix whenever that area is next touched.
