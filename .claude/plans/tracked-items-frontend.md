---
status: implemented
app: fetcher+core
goal: Build the "Tracked Items" public catalog page in app_core's React dashboard, consuming app_fetcher's existing GET /api/public/items
created: 2026-10-12
---

# Development Plan

## Goal

Add a second, publicly-viewable page to `app_core` — "Tracked Items" — that
renders the full `app_fetcher` items catalog (search, category/rarity
filters, StatTrak toggle, sort, ticker/grid view, pagination, per-item
sparkline) served by the already-built `GET /api/public/items` endpoint,
reachable via a nav tab alongside the existing "Portfolio" dashboard, visible
whether or not the visitor is signed in.

## Expected Behavior

**Normal behavior**

- Visiting `/tracked-items` (signed in or not) renders a topbar with
  "Portfolio" / "Tracked Items" nav tabs, a stat strip (items tracked /
  gaining today / losing today — counts only), a toolbar (search, a combined
  Filters dropdown with Category/Rarity/StatTrak sections, a Sort dropdown,
  a Ticker/Grid view toggle), and the item list itself, server-paginated.
- Typing in search debounces (300ms) before issuing a request; every other
  control (category/rarity chip, StatTrak toggle, sort choice, page change,
  per-page change) re-fetches immediately.
- Toggling Ticker ↔ Grid re-renders the already-fetched page of items in the
  other layout with no new request.
- Changing any filter/search/sort resets to page 1; changing per-page also
  resets to page 1.
- Each row/card shows weapon+skin name, rarity (color dot + label from the
  item's own rarity string), condition abbreviation, StatTrak badge when
  applicable, current price, 24h % change (colored, arrowed), and a 7-point
  sparkline from `trend_7d`.
- "Portfolio" nav tab continues to work exactly as today (signed-in
  inventory view; shows the existing sign-in card when signed out).

**Edge cases**

- Zero items match the current filters → an empty-state row/message, same
  spirit as `ItemsTile`'s "No items match these filters."
- An item with `current_price_cents: null` (not yet priced) → price renders
  as `—`, no delta badge (mirrors `ItemRow`'s existing `hasPrice`/`showDelta`
  guards).
- An item with no `icon_url` → same-class empty placeholder span, per the
  optional-image convention already documented in `react-dashboard.md`.
- A rarity string with no known color mapping → falls back to a neutral/grey
  dot rather than crashing or rendering `undefined`.
- Last page with fewer than `per_page` items → pagination range/controls use
  the server's `total_count`/`total_pages`, not a client-computed guess.

**Failure behavior**

- Fetch failure (network error, non-2xx) → the page renders an error state,
  matching the existing `status === 'error'` convention on `Dashboard.jsx`.
- A request made right after a param change that's superseded by a newer one
  (e.g. rapid filter toggling) must not let the stale response clobber
  newer state — guard with a cancellation flag, same pattern as
  `useDashboardData`.

**Must remain unchanged**

- Everything about the existing Portfolio dashboard (`Dashboard.jsx`,
  `reducer.js`, its hooks/components) — this plan adds a sibling, it does
  not touch Portfolio's own behavior, only the shared topbar chrome around
  it.
- `app_fetcher`'s `/api/public/items` response shape, params, caching, and
  error behavior — out of scope to change; the only `app_fetcher` edit is
  the CORS allowlist (see below).

## Scope

### In Scope

- New `app_core` route/controller/view for `/tracked-items`.
- Shared topbar partial (nav tabs) used by both the Portfolio and Tracked
  Items pages.
- New React island (`app/frontend/tracked_items/`) with its own entrypoint,
  reducer, data-loading hook, components, styles, and tests, following
  `react-dashboard.md`'s conventions.
- Search (debounced), category filter, rarity filter, StatTrak-only toggle,
  sort (the API's actual 4 options), Ticker/Grid view toggle, pagination
  (page + per-page 25/50/100), stat strip (counts only, no avg%), per-row
  sparkline, icon placeholder.
- One `app_fetcher` change: extend `config/initializers/cors.rb` to allow
  `/api/public/*` for `APP_CORE_ORIGIN` (GET/OPTIONS only).

### Out of Scope

- Any change to `ItemCatalogQuery`/`ItemCatalogSerializer`/the public items
  route's params or response shape.
- A gold/"extraordinary" rarity tier distinction on the frontend — the
  serializer doesn't expose it; the frontend rarity color map targets only
  the raw Steam strings the API actually returns (`Consumer Grade`,
  `Industrial Grade`, `Mil-Spec Grade`, `Restricted`, `Classified`,
  `Covert`), plus a neutral fallback.
- An ascending/"losers first" change-sort option — the API doesn't support
  one; the Sort dropdown offers exactly the 4 values the backend accepts.
- Average %-change sub-labels on the gaining/losing stat tiles — the API's
  `meta` only has counts (`gaining_count`/`losing_count`), not an average;
  computing one from only the current page's items would be a
  page-dependent, misleading number, so it's dropped rather than faked.
- Real-time/auto-refresh of the catalog (matches the existing dashboard's
  own "reload for latest prices" posture — no new polling infrastructure).
- Any rate-limiting work on the public endpoint (explicitly flagged as
  future work in the endpoint's own plan/styleguide already).

## Implementation Approach

**Two pages, two routes, shared chrome.** Rather than folding "Tracked
Items" into the existing single-page `Dashboard.jsx`/`reducer.js`, this adds
a new route (`/tracked-items`) backed by its own thin controller, view, and
Vite entrypoint — a true sibling to the Portfolio dashboard, not a mode
switch inside it. Reasoning: `useDashboardData`/`reducer.js` are built
around "fetch the whole (small) inventory once, filter/sort/paginate
client-side in memory" — `PAGE_SIZE` is a fixed constant, pagination is a
0-based in-memory slice, and filters are plain client-side array/Set
predicates. The catalog is the opposite shape: large, server-paginated, with
every filter/sort/page/per-page change needing a fresh server round-trip and
a variable per-page size. Bolting a second, structurally incompatible data-
loading model onto the same reducer would make `reducer.js` a grab-bag of
two unrelated state machines connected only by which tile currently renders.
Two routes also cleanly answers the signed-out-visibility question: each
controller/view independently decides what it needs (Portfolio still mints
a bridge token and gates its body on `current_user`; Tracked Items mints
nothing and gates nothing), with no conditional plumbing threaded through a
shared component tree.

**Shared chrome via a view partial, not shared React state.** The topbar
(brand, nav tabs, profile chip / sign-in CTA) is plain server-rendered ERB
today (`dashboards/show.html.erb`), entirely outside the React island, per
`erb-interaction-patterns.md`. It gets extracted into a partial
(`shared/_topbar.html.erb`) taking an `active_tab:` local, and both pages
render it. The nav tabs themselves are plain `<a href>` links to `root_path`
/ `tracked_items_path` — ordinary Rails navigation, not a new zero-JS
interactivity pattern, since this is a real page change (different mount
point, different data, different URL), not an in-place disclosure or
confirm step that `erb-interaction-patterns.md`'s two named patterns are
scoped to.

**New sibling island, mirroring `react-dashboard.md`'s shape.**
`app/frontend/tracked_items/` follows the exact same structure as
`app/frontend/dashboard/`: one root component owning one `useReducer` +
one data-loading hook, `components/` for presentational pieces,
`utils/` for pure derivation/formatting, flat `__tests__/`. Two pieces are
reused directly from the existing island rather than duplicated, since
they're already generic and pure: `Sparkline.jsx` (per
`sparkline-vs-recharts.md`, it's the canonical small-repeated-trend-line
component — a second copy would contradict that ADR) and
`fmtPrice`/`conditionAbbr` from `dashboard/utils/format.js`. Everything
else — toolbar, dropdowns, list rendering, pagination — is new, because the
existing equivalents (`ItemsToolbar`, `FilterDropdown`, `SortDropdown`,
`Pagination`) are wired for the client-side/fixed-page-size shape and
don't fit a server-driven catalog without changing their contracts (which
would risk the Portfolio page's own behavior).

**Data loading**: `useItemsCatalog(fetcherUrl, params)` is the one fetch
hook, called with the reducer's fetch-relevant state
(`{search, categories, rarities, stattrakOnly, sort, page, perPage}` —
deliberately excluding `view` and `openDropdown`, which are pure rendering
concerns that must never trigger a refetch). Internally it debounces only
the `search` value (300ms via a `setTimeout`, same idiom `useItemPrices.js`
already uses for its retry schedule) before including it in the request;
every other param change fires immediately. It maps the response into the
dashboard's existing camelCase item shape (mirrors `useDashboardData`'s
`mapItem`) plus the `meta` block, and returns `{data, status, error}` with
the same 3-value status enum used everywhere else in the dashboard.

**One combined Filters dropdown, not three separate toolbar buttons.** The
mockup shows Category and Rarity as two separate dropdown buttons plus a
standalone StatTrak chip. The existing Portfolio toolbar already
established a single combined "Filters" dropdown (weapon + condition +
StatTrak sections, one button, a badge count, one Clear link) —
`FilterDropdown.jsx`. For product consistency between the two pages (same
app, same interaction vocabulary) and to avoid three new toolbar components
where one suffices, Tracked Items' toolbar reuses that same combined-
dropdown shape with Category/Rarity/StatTrak sections instead of
Weapon/Condition/StatTrak. This is the one deliberate deviation from the
mockup's literal toolbar layout — the mockup is an approximate reference,
and matching the app's own established pattern beats copying three
separate dropdown widgets.

**Styling**: shared chrome tokens/topbar/nav-tabs stay in the existing
`dashboard.css` (both pages load it, and it already owns exactly this kind
of shared chrome). Catalog-specific classes (stat strip, ticker table, grid
cards, rarity dot, glyph placeholder, catalog pager) go in a new
`tracked_items/styles/tracked_items.css`, imported only by the new
entrypoint — keeping `dashboard.css` from accumulating classes the
Portfolio page never uses, while still sharing the actual shared chrome in
one place.

## Files To Modify

- `app_core/config/routes.rb` — add
  `get "tracked-items", to: "tracked_items#show", as: :tracked_items`.
  Reason: new page needs a route.
- `app_core/app/views/dashboards/show.html.erb` — replace the inline
  topbar markup (brand + profile-group/signin stuff) with
  `<%= render "shared/topbar", active_tab: :portfolio %>`; no other change
  to this file's body (Portfolio behavior is unchanged). Reason: share
  chrome without duplicating ~40 lines of ERB.
- `app_fetcher/config/initializers/cors.rb` — add a second `resource`
  block inside the existing `allow do ... end` for `/api/public/*`
  (`methods: [:get, :options]`, `credentials: false`, same origin). Reason:
  the browser currently cannot call `/api/public/items` cross-origin at
  all; this is a hard blocker for the whole feature, not a nice-to-have.

## Files To Create

**`app_core` — routing/view layer**

- `app_core/app/controllers/tracked_items_controller.rb` — thin,
  `typed: strict`, single `sig { void } def show; end`. No bridge token,
  no auth guard — this page needs neither.
- `app_core/app/views/tracked_items/show.html.erb` — renders
  `shared/topbar` with `active_tab: :tracked_items`, then
  `<div id="tracked-items-root" data-fetcher-url="<%= ENV.fetch('APP_FETCHER_PUBLIC_URL') %>"></div>`,
  then the `tracked_items.jsx` Vite entrypoint tag. No signed-out gating of
  any kind — the whole point is this renders the same way for everyone.
- `app_core/app/views/shared/_topbar.html.erb` — extracted from
  `dashboards/show.html.erb`'s current topbar block, taking `active_tab:`.
  Adds the `.nav-tabs`/`.nav-tab` markup (two links) alongside the existing
  brand/profile-group/signin-CTA content, which moves here unchanged.

**`app_core` — React island**

- `app_core/app/frontend/entrypoints/tracked_items.jsx` — mirrors
  `entrypoints/dashboard.jsx`: imports the stylesheet, mounts
  `<TrackedItems fetcherUrl={...} />` into `#tracked-items-root`.
- `app_core/app/frontend/tracked_items/TrackedItems.jsx` — root component;
  owns `useReducer(trackedItemsReducer, initialState)` +
  `useItemsCatalog`; renders `CatalogSkeleton` while loading, an error
  message on failure, else `StatStrip` + `CatalogToolbar` +
  (`TickerView` or `GridView`) + `CatalogPagination`.
- `app_core/app/frontend/tracked_items/reducer.js` — `initialState` +
  `trackedItemsReducer`, action types: `SEARCH_CHANGED`,
  `CATEGORY_TOGGLED`, `RARITY_TOGGLED`, `STATTRAK_TOGGLED`,
  `SORT_CHANGED`, `VIEW_CHANGED`, `PAGE_CHANGED`, `PER_PAGE_CHANGED`,
  `FILTERS_CLEARED`, `DROPDOWN_TOGGLED`, `DROPDOWNS_CLOSED`. Shape:
  ```js
  {
    search: '', categories: new Set(), rarities: new Set(),
    stattrakOnly: false, sort: 'change_24h_desc', view: 'ticker',
    page: 1, perPage: 25, openDropdown: null,
  }
  ```
  Every filter/search/sort/per-page action resets `page` to `1`, same
  spirit as the existing reducer resetting `page` to `0` on any filter
  change. Reuses the existing `toggleSetMember` idea (re-implemented
  locally, since `reducer.js` isn't a shared module today) for
  `categories`/`rarities`.
- `app_core/app/frontend/tracked_items/hooks/useItemsCatalog.js` —
  `useItemsCatalog(fetcherUrl, {search, categories, rarities, stattrakOnly, sort, page, perPage})`.
  Debounces `search` (300ms) internally; builds the query string
  (`category[]`, `rarity[]`, `stattrak=true` only when true, `search`,
  `sort`, `page`, `per_page`); fetches `${fetcherUrl}/api/public/items?...`
  with no `Authorization` header; maps `meta` → camelCase and each item →
  the existing dashboard item shape plus `rarity`; returns
  `{data: {meta, items} | null, status, error}`.
- `app_core/app/frontend/tracked_items/components/StatStrip.jsx` — 3
  tiles: tracked (`totalCount`), gaining (`gainingCount`), losing
  (`losingCount`) — no avg% sub-labels.
- `app_core/app/frontend/tracked_items/components/CatalogToolbar.jsx` —
  composes the (inline) search input, `FilterDropdown`, `SortDropdown`,
  `ViewToggle`; same outside-click/Escape-to-close wiring as
  `ItemsToolbar.jsx` (`useRef` + `useEffect`).
- `app_core/app/frontend/tracked_items/components/FilterDropdown.jsx` —
  Category chips / Rarity chips (color dot + label) / StatTrak chip
  sections, badge count, Clear link — same shape as the existing
  `FilterDropdown.jsx`, different facets and dispatch actions.
- `app_core/app/frontend/tracked_items/components/SortDropdown.jsx` —
  the 4 real sort values only
  (`change_24h_desc`/`price_desc`/`price_asc`/`name_asc`) with labels
  matching the mockup's wording ("24h change", "Price: high to low",
  "Price: low to high", "Name A–Z").
- `app_core/app/frontend/tracked_items/components/ViewToggle.jsx` —
  Ticker/Grid pill pair, same presentational shape as `RangeToggle.jsx`.
- `app_core/app/frontend/tracked_items/components/CatalogSkeleton.jsx` —
  loading placeholder, mirrors `DashboardSkeleton.jsx`'s bar-shimmer shape.
- `app_core/app/frontend/tracked_items/components/TickerView.jsx` —
  table head + rows (row rendering inline/nested, no other caller);
  reuses `Sparkline` (imported from `../../dashboard/components/Sparkline`)
  and `fmtPrice`/`conditionAbbr` (imported from
  `../../dashboard/utils/format`).
- `app_core/app/frontend/tracked_items/components/GridView.jsx` — card
  grid (card rendering inline/nested); same reused imports as `TickerView`.
- `app_core/app/frontend/tracked_items/components/CatalogPagination.jsx`
  — range text + per-page `<select>` (25/50/100) + prev/next, driven by
  the server's `page`/`totalPages`/`totalCount`/`perPage` directly (no
  client-side math beyond the displayed range).
- `app_core/app/frontend/tracked_items/utils/format.js` — `rarityColor(rarity)`
  and `rarityDotStyle`-equivalent mapping for the 6 real Steam rarity
  strings plus a neutral fallback for anything unrecognized. Nothing else
  — `fmtPrice`/`conditionAbbr` are imported from the existing
  `dashboard/utils/format.js` at each call site rather than re-exported
  here, to keep one source of truth obvious.
- `app_core/app/frontend/tracked_items/styles/tracked_items.css` — stat
  strip, toolbar specifics (category/rarity dropdown panels, view toggle),
  ticker table, grid cards, rarity dot, glyph placeholder, catalog pager —
  built on the existing `--bg`/`--surface`/`--border`/`--text*`/`--up`/
  `--down`/`--accent`/`--font-*`/`--radius-*` custom properties already
  defined in `dashboard.css` (both stylesheets load on this page, so the
  tokens are in scope without redefinition).
- `app_core/app/frontend/tracked_items/__tests__/reducer.test.js` — pure
  reducer transitions (toggles, clears, page-reset-on-filter-change).
- `app_core/app/frontend/tracked_items/__tests__/useItemsCatalog.test.js`
  — hook test (`renderHook`/`waitFor`, `vi.stubGlobal('fetch', ...)`):
  asserts query-string construction per param, debounced search timing
  (fake timers), and that a superseded in-flight request doesn't clobber
  newer state.
- `app_core/app/frontend/tracked_items/__tests__/format.test.js` — the new
  `rarityColor` mapping, including the unrecognized-rarity fallback case.
- `app_core/app/frontend/tracked_items/__tests__/TrackedItems.test.jsx` —
  composite/orchestration test in `ItemsTile.test.jsx`'s style: a harness
  owning the real `trackedItemsReducer`, fetch mocked at the boundary,
  driving filter → sort → view-toggle → paginate through
  `@testing-library/user-event`.

## Test Plan

- **`app_fetcher`**: add a context to the existing
  `spec/requests/api/public/items_spec.rb` asserting an `OPTIONS`
  preflight (or a plain `GET` with an `Origin` header) against
  `/api/public/items` returns an `Access-Control-Allow-Origin` header
  matching `APP_CORE_ORIGIN` — the smallest request-spec-level proof the
  CORS gap is actually closed, colocated with the endpoint it unblocks
  rather than a new file for one assertion.
- **`app_core` reducer**: `reducer.test.js` — every action type, with
  particular attention to "any filter/search/sort/per-page change resets
  `page` to 1" and `toggleSetMember`-equivalent behavior for
  categories/rarities.
- **`app_core` hook**: `useItemsCatalog.test.js` — param → query-string
  mapping (including array params and the opt-in-only `stattrak=true`
  shape matching the backend's actual semantics), debounce timing for
  `search` only, response mapping (meta + items, including the
  `rarity`/`trend_7d` fields), and the stale-response-ignored-on-
  cancellation case.
- **`app_core` pure utils**: `format.test.js` — `rarityColor` for each of
  the 6 known strings plus an unrecognized value.
- **`app_core` composite**: `TrackedItems.test.jsx` — real reducer,
  mocked fetch, drives: typing in search (debounce via fake timers) narrows
  results; toggling a category/rarity chip filters and resets to page 1;
  changing sort re-fetches with the new `sort` param; switching Ticker↔Grid
  re-renders without an extra fetch call; changing per-page resets to page
  1 and reflects the new range text; an item with `current_price_cents:
  null` renders `—` with no delta badge (mirrors the existing
  `ItemRow`/`ItemsTile` unpriced-item test).
- No dedicated test file for `StatStrip`, `FilterDropdown`, `SortDropdown`,
  `ViewToggle`, `CatalogSkeleton`, `TickerView`, `GridView`,
  `CatalogPagination` — none composes/orchestrates or carries branching
  logic worth isolating on its own; each is exercised indirectly through
  `TrackedItems.test.jsx`, consistent with `react-dashboard.md`'s existing
  dividing line (`SortDropdown`, `ItemsToolbar`, `FilterDropdown`,
  `Pagination`, `RangeToggle`, `Sparkline` have none today for the same
  reason).
- No new `app_core` request/system spec for `tracked_items_controller.rb`
  beyond what the Rails default app-level smoke coverage already gives
  controllers in this app (mirrors `dashboards_controller.rb` having no
  dedicated request spec today either — confirm during implementation; if
  one exists for `DashboardsController`, add the matching one for
  `TrackedItemsController` instead of leaving an asymmetry).

## Implementation Steps

1. **Fetcher CORS fix** (unblocks everything else being testable
   end-to-end in a browser): add the `/api/public/*` `resource` block to
   `cors.rb`; add the preflight-header context to `items_spec.rb`; run the
   fetcher spec.
2. **Shared topbar partial**: extract `shared/_topbar.html.erb` from
   `dashboards/show.html.erb`, parameterize with `active_tab:`, add nav-tab
   markup; update `dashboards/show.html.erb` to render it with
   `active_tab: :portfolio`; verify the Portfolio page is pixel-identical
   to before except for the new tabs.
3. **New route/controller/view**: add the `tracked-items` route,
   `TrackedItemsController#show`, `tracked_items/show.html.erb` rendering
   the partial with `active_tab: :tracked_items` plus the mount div and
   entrypoint tag.
4. **Reducer first (TDD)**: write `reducer.test.js` against the intended
   action shape, then `reducer.js` to satisfy it.
5. **Data hook (TDD)**: write `useItemsCatalog.test.js` (query-string
   construction, debounce, mapping, stale-response guard) against a mocked
   `fetch`, then `useItemsCatalog.js`.
6. **Pure utils (TDD)**: `format.test.js` for `rarityColor`, then
   `format.js`.
7. **Presentational components**: `StatStrip`, `FilterDropdown`,
   `SortDropdown`, `ViewToggle`, `CatalogSkeleton`, `TickerView`,
   `GridView`, `CatalogPagination`, `CatalogToolbar`, wiring reused
   `Sparkline`/`fmtPrice`/`conditionAbbr` imports.
8. **Root component + composite test**: `TrackedItems.jsx` wiring reducer
   + hook + components; write/finish `TrackedItems.test.jsx` against it.
9. **Entrypoint + styles**: `entrypoints/tracked_items.jsx`,
   `styles/tracked_items.css`, built against the mockup's visual spec
   (ticker/grid/stat-strip/toolbar/pager) using existing CSS custom
   properties.
10. **Manual verification in the browser** (per the project's preview
    workflow): start both apps, confirm the CORS fix actually unblocks the
    cross-origin fetch, exercise search/filter/sort/view/paginate
    signed-in and signed-out, confirm Portfolio is unaffected.

## Verification

- `app_fetcher`: `bundle exec rspec spec/requests/api/public/items_spec.rb`.
- `app_core`: `bin/rails test` (or the project's existing Ruby test
  invocation) for any controller-level coverage touched;
  `npm run test` (Vitest) for all new/changed JS.
- Sorbet (`srb tc`) in both apps, since both touched controllers are
  `typed: strict`.
- Manual browser verification (per repo convention for UI changes):
  Portfolio page unchanged; Tracked Items reachable signed-in and signed-
  out; every toolbar control re-fetches (or doesn't, for the view toggle)
  as specified; empty-filter and unpriced-item edge cases render correctly;
  responsive check at a narrow viewport (the mockup has a `max-width:640px`
  breakpoint worth carrying over).

## Risks

- **CORS fix scope**: widening `/api/public/*` is safe because that
  namespace is defined (per its own styleguide) to never depend on caller
  identity and never mutate state — but double-check no future
  `Api::Public::` endpoint is added later assuming it's *not*
  browser-reachable before extending this pattern further.
- **Partial extraction risk**: moving the topbar into a partial touches the
  one existing view/test (if any) that currently renders
  `dashboards/show.html.erb` directly — must confirm no existing request
  spec asserts on topbar markup in a way the extraction's output would
  break (should be a pure refactor, but verify).
- **Debounce + cancellation interaction**: the hook must guard against a
  slow earlier request resolving after a faster later one (e.g. clearing a
  filter right after typing); the existing `useDashboardData` cancellation-
  flag pattern handles this, but it needs re-verifying under the debounce
  timer specifically, not just the fetch itself.

## Assumptions

- `APP_FETCHER_PUBLIC_URL` (already used by `dashboards_controller`/
  `show.html.erb`) is the correct, already-CORS-relevant base URL for the
  new page's fetch calls too — no new env var needed.
- No existing request spec for `DashboardsController`/`TrackedItemsController`
  asserts topbar markup in a way that would need updating for the partial
  extraction — could not be verified without a full spec-suite read; to be
  confirmed at implementation time (see Risks).
- A plain `get "tracked-items", ...` route (rather than a RESTful
  `resource :tracked_items`) is acceptable, matching the existing
  singleton-page precedent (`root "dashboards#show"`) more than the
  resourceful `resource :session` one — either is a reasonable reading of
  current conventions.

## Applicable Styleguides

- `.claude/styleguides/core/react-dashboard.md` — constrains the entire
  `app/frontend/tracked_items/` portion of Files To Create: structure
  (root component/`reducer.js`/`hooks/`/`components/`/`utils/`/
  `__tests__/`), component conventions (named exports, presentational
  components, optional-image placeholder), derived-data placement, state/
  data-loading shape (one reducer, one hook per data source, the 3-value
  `status` enum), the charting boundary (reuse `Sparkline.jsx`, no new
  Recharts instance), the CSS split (shared `dashboard.css` vs. the new
  island's own `tracked_items.css`), and the testing conventions (flat
  `__tests__/`, what gets a dedicated test file, the three test styles).
  Amended during this check (see `.claude/adr/core/multiple-react-islands.md`)
  to confirm these conventions govern any island, not only `dashboard/`,
  and to add the Reuse Across Islands rule this plan's Sparkline/
  `format.js` reuse and island-local toolbar/dropdown/pagination
  components both depend on.
- `.claude/adr/core/multiple-react-islands.md` — the ADR backing the above:
  confirms a second top-level feature with an incompatible data-loading
  shape is a new sibling island (Implementation Approach's "Two pages, two
  routes" decision), not a mode inside `dashboard/`'s existing reducer, and
  that `Sparkline.jsx`/`format.js`'s `fmtPrice`/`conditionAbbr` are
  imported directly while `ItemsToolbar`/`FilterDropdown`/`SortDropdown`/
  `Pagination` each get an island-local reimplementation.
- `.claude/styleguides/core/architecture-layers.md` +
  `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  constrains `TrackedItemsController#show` (stays a trivial, no-model-
  lookup action) and `useItemsCatalog` (fetches `app_fetcher`'s
  `/api/public/items` directly from the browser, never through an
  `app_core` proxy endpoint).
- `.claude/styleguides/core/erb-interaction-patterns.md` — checked and
  confirmed not to apply to the new nav tabs: they're plain `<a href>`
  links between two full-page routes/controllers, not an in-page
  disclosure or confirm-before-action overlay, so neither of this file's
  two named patterns (nor a new one) is needed here.
- `.claude/adr/core/sparkline-vs-recharts.md` — constrains `TickerView`/
  `GridView` to reuse `Sparkline.jsx` for the per-row/per-card trend line
  rather than a new Recharts instance.
- `.claude/styleguides/fetcher/public-api-controllers.md` +
  `.claude/adr/fetcher/public-api-namespace.md` — confirmed the CORS
  widening to `/api/public/*` is orthogonal to this namespace's no-caller-
  identity posture; neither document needed a change.
- `.claude/styleguides/rspec-conventions.md` — confirms request specs run
  the full Rack middleware stack by default, which is why the plan's CORS
  test (a context added to the existing `items_spec.rb`, asserting
  `Access-Control-Allow-Origin` on a request carrying an `Origin` header)
  is the right level, with no new spec file or type needed.
- `.claude/styleguides/git-commits.md` — applies at commit time during
  `implement-plan`, not to the plan's content itself.

## Completion Criteria

- Desired behavior, scope, affected files, test strategy, and steps are
  explicit above.
- Plan is written to `.claude/plans/tracked-items-frontend.md`.
- Styleguide check complete: `react-dashboard.md` amended and
  `multiple-react-islands.md` ADR created and approved (see Applicable
  Styleguides); no other gaps found.
- Next: `implement-plan`.

# Implementation Summary

## Implemented

Everything in Files To Modify/Files To Create, following Implementation
Steps in order:

- `app_fetcher/config/initializers/cors.rb`: added a second `resource
  "/api/public/*"` block (GET/OPTIONS, `credentials: false`) alongside the
  existing `/api/v1/*` one.
- `app_fetcher/spec/requests/api/public/items_spec.rb`: added a context
  asserting `Access-Control-Allow-Origin` on a request carrying an
  `Origin` header.
- `app_core/app/views/shared/_topbar.html.erb` (new): extracted from
  `dashboards/show.html.erb`'s topbar, parameterized by `active_tab:`,
  with `.nav-tabs`/`.nav-tab` markup added (plain `<a>` links to
  `root_path`/`tracked_items_path`).
- `app_core/app/views/dashboards/show.html.erb`: topbar block replaced
  with `render "shared/topbar", active_tab: :portfolio`; rest of the file
  untouched.
- `app_core/config/routes.rb`: added
  `get "tracked-items", to: "tracked_items#show", as: :tracked_items`.
- `app_core/app/controllers/tracked_items_controller.rb` (new): thin,
  `typed: strict`, single empty `show` action — no bridge token, no auth
  guard.
- `app_core/app/views/tracked_items/show.html.erb` (new): renders the
  shared topbar (`active_tab: :tracked_items`), the `#tracked-items-root`
  mount div (fetcher URL only, no bridge token), and the
  `tracked_items.jsx` entrypoint tag.
- `app_core/spec/requests/tracked_items_spec.rb` (new): request spec
  mirroring `dashboards_spec.rb`'s conventions — signed-in/signed-out
  rendering, active nav tab, no bridge token in the signed-out case.
- `app_core/app/frontend/tracked_items/` (new island, mirrors
  `dashboard/`'s structure per the amended `react-dashboard.md`):
  - `reducer.js` + `__tests__/reducer.test.js` — `initialState`/
    `trackedItemsReducer` with the planned action set
    (`SEARCH_CHANGED`/`CATEGORY_TOGGLED`/`RARITY_TOGGLED`/
    `STATTRAK_TOGGLED`/`SORT_CHANGED`/`VIEW_CHANGED`/`PAGE_CHANGED`/
    `PER_PAGE_CHANGED`/`FILTERS_CLEARED`/`DROPDOWN_TOGGLED`/
    `DROPDOWNS_CLOSED`), plus `activeFilterCount`.
  - `hooks/useItemsCatalog.js` + its test — fetches
    `/api/public/items` directly (no Authorization header), debounces
    only `search` (300ms), builds the query string per param
    (opt-in-only `stattrak`, repeated `category[]`/`rarity[]`), maps
    the response to the dashboard's existing camelCase item shape plus
    `rarity`/`category`, and guards against a superseded in-flight
    request clobbering a newer one.
  - `utils/format.js` (`rarityColor`, 6 known Steam rarities + neutral
    fallback) and `utils/options.js` (`categoriesPresent`/
    `raritiesPresent`, mirroring `dashboard/utils/filters.js`'s
    `weaponTypesPresent`/`conditionsPresent` pattern) — both with
    dedicated unit tests.
  - `components/`: `StatStrip`, `FilterDropdown` (combined
    Category/Rarity/StatTrak — one deliberate deviation from the mockup's
    three separate toolbar widgets, for consistency with the existing
    Portfolio toolbar's one-combined-dropdown pattern), `SortDropdown`
    (the API's real 4 sort values only), `ViewToggle`, `CatalogSkeleton`,
    `TickerView`, `GridView`, `CatalogPagination`, `CatalogToolbar`.
    `Sparkline.jsx` and `fmtPrice`/`conditionAbbr` are imported directly
    from `dashboard/`, not duplicated, per the new Reuse Across Islands
    rule.
  - `TrackedItems.jsx` (root component) + `__tests__/TrackedItems.test.jsx`
    (composite/orchestration test, real reducer, mocked `fetch`).
  - `styles/tracked_items.css` (new, catalog-specific classes) +
    `dashboard.css` additions (`.nav-tabs`/`.nav-tab`/`.pip`, and a
    `.topbar` layout tweak so the tabs stay anchored next to the brand
    whether or not `.profile-group` is present).
  - `app_core/app/frontend/entrypoints/tracked_items.jsx` (new):
    mounts `<TrackedItems>` into `#tracked-items-root`, importing both
    stylesheets.
- `.claude/styleguides/core/react-dashboard.md`: amended (scope broadened
  from `dashboard/`-only to any island; new "Reuse Across Islands"
  section; CSS-split guidance; minor Structure/Testing clarifications) —
  approved by the user before implementation.
- `.claude/adr/core/multiple-react-islands.md` (new): the ADR backing that
  amendment — approved by the user before implementation.

## Tests

Commands actually executed (all via the Docker images built for this
worktree, Ruby 3.3.6 inside the container — the host's rbenv Ruby 3.3.0
can't load this Gemfile.lock at all, unrelated to this change):

- `docker compose run --rm -e RAILS_ENV=test app_fetcher bundle exec rspec spec/requests/api/public/items_spec.rb`
  → **25 examples, 0 failures**.
- `docker compose run --rm -e RAILS_ENV=test app_core bundle exec rspec spec/requests/dashboards_spec.rb spec/requests/tracked_items_spec.rb`
  → **10 examples, 0 failures**.
- `docker compose run --rm -e RAILS_ENV=test app_core bundle exec rspec` (full suite)
  → **29 examples, 26 passed, 3 pre-existing failures** unrelated to this
  change (`spec/lib/admin/bridge_token_spec.rb` — missing
  `APP_ADMIN_BRIDGE_JWT_SECRET` env var for the separate, earlier
  admin-panel-backend feature; confirmed this worktree's `.env` simply
  never had that key, nothing in this diff touches admin auth).
- `npx vitest run` (from `app_core/`, host Node, no Docker needed) →
  **16 test files, 109 tests, all passed** (14 reducer + 7 hook + 8
  format + 6 options + 6 TrackedItems composite = 41 new; 68 pre-existing,
  unaffected).

## Verification

- Sorbet (`docker compose run --rm app_fetcher bundle exec srb tc` and
  the `app_core` equivalent): both show pre-existing, project-wide
  errors (missing RBI generation for RSpec/FactoryBot/JWT gem constants,
  affecting every spec file and a couple of unrelated `lib/` files) that
  exist identically with or without this diff — confirmed by grepping the
  output for every file this change touches or adds
  (`tracked_items_controller.rb` appears zero times;
  `tracked_items_spec.rb` appears only for the same pre-existing
  RSpec-constant gap every other spec file hits). No new Sorbet error
  introduced by this change.
- Manual browser verification (Docker-run dev servers, seeded 40
  synthetic items + price history via a one-off `rails runner` script,
  not committed): confirmed in a real Chromium instance via the preview
  tool —
  - the browser's direct cross-origin `fetch` from the app_core origin to
    `/api/public/items` succeeds (`200 OK` in the network log) — the
    actual proof the CORS fix works, since RSpec request specs never
    enforce CORS at all;
  - `/tracked-items` renders signed-out with no `data-bridge-token`, nav
    tabs correct (`Tracked Items` active, `Portfolio` not), stat strip
    reflecting real counts from the API's `meta`;
  - toggling a category chip sends `category[]=...&page=1`, updates the
    filter badge, re-renders filtered rows, and the stat strip's "items
    tracked" count drops to the server's filtered `total_count` — proving
    the whole page is server-driven, not a client-side illusion;
  - typing in search debounces and sends `search=...` only once settled;
  - switching Ticker → Grid re-renders (25 ticker rows → 25 `.item-card`s)
    with no additional network request;
  - computed styles confirm the dark theme tokens and a rarity dot's
    color (`Covert` → `rgb(235, 75, 75)` = `#eb4b4b`) render correctly;
  - responsive check at 375px confirms the stat strip collapses to one
    column.
  - Portfolio (`/`) re-checked after the topbar extraction: unchanged
    render, confirmed both by `dashboards_spec.rb` (all passing) and by
    loading it directly in the browser.

## Deviations

- **One combined `FilterDropdown`** instead of the mockup's separate
  Category/Rarity dropdowns + standalone StatTrak chip — documented and
  justified in the plan's own Implementation Approach before
  implementation, not an improvised change.
- **`utils/options.js`** (`categoriesPresent`/`raritiesPresent`) was not
  in the plan's original Files To Create list. The plan specified working
  category/rarity filter chips but didn't say where their option lists
  come from; `app_fetcher` has no "distinct categories/rarities" endpoint
  and no enumerated list anywhere (category/rarity are open, Steam-sourced
  strings — see `public-api-controllers.md`'s own "open string-set array
  params" rule), so a hardcoded frontend list would be an unverified
  guess. Resolved by mirroring the existing, already-accepted
  `weaponTypesPresent`/`conditionsPresent` pattern from
  `dashboard/utils/filters.js` (derive options from whichever page is
  currently loaded) — a small, grounded gap-fill rather than a plan
  contradiction, with its own dedicated tests.
- **Local-only dev environment files**, not part of the plan and not
  committed (confirmed absent from `git status`): this worktree's `.env`
  was copied from the main checkout and its `APP_FETCHER_PUBLIC_URL`/
  `APP_CORE_ORIGIN` repointed to `23001`/`23000`, and a
  `docker-compose.override.yml` was added remapping `app_core`/
  `app_fetcher`/`redis`'s host ports to `23000`/`23001`/`26380` — both
  exist solely because several other worktrees' Docker stacks were
  already occupying the default `3000`/`3001`/`6380` on this shared
  machine. Both are gitignored/untracked and were necessary to run any
  RSpec suite or dev server for this worktree at all. **Flagging this
  explicitly**: if you run `docker compose up` in this worktree later
  expecting the default ports, it will come up on `23000`/`23001`/`26380`
  instead until/unless `docker-compose.override.yml` is removed (and
  `.env` repointed back) — intentionally left in place since removing it
  would just reproduce the same conflict again next time this worktree is
  used alongside the others.
- The app_fetcher development/test DBs in this worktree now contain 40
  synthetic items (seeded via an uncommitted one-off script, not
  `db/seeds.rb`) purely for the manual browser check — harmless local-only
  data, not part of the diff.

## Remaining Issues

- The 3 pre-existing `Admin::BridgeToken` spec failures (missing
  `APP_ADMIN_BRIDGE_JWT_SECRET` in this worktree's `.env`) are unrelated
  to this change and were not fixed, per scope.
- Sorbet's pre-existing RBI-generation gaps (RSpec/FactoryBot/JWT/Sidekiq
  constants unresolved project-wide) were not fixed, per scope — confirmed
  this diff introduces none of its own.
- No new ADR/styleguide-level rate-limiting work was done for
  `Api::Public::`, consistent with the plan's explicit Out of Scope.
