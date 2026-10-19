---
status: implemented
app: fetcher+core
goal: Fix the remaining review findings — stop calling the root fetcher ApplicationController "V1" in docs, remove dead code and a stale TODO, and unify the API/frontend vocabulary for periods, rarity breakdowns, 24h changes, sorting, and pagination
created: 2026-10-19
---

## Applicable Styleguides

- **`agent/styleguides/fetcher/internal-api-controllers.md`** — governs
  the `Api::V1::` contract that must stay unchanged and is the place to
  make the top-level `ApplicationController` note explicit; its
  Error Handling/Interface sections constrain the untouched V1 error
  shapes.
- **`agent/styleguides/fetcher/public-api-controllers.md`** — governs
  the public namespace's closed-enum param handling, clamping, error
  messages, and response shape; the plan renames `range`/`items_*` to
  `period`/`sort`/`page`/`per_page` and must update its wording.
- **`agent/styleguides/fetcher/list-query-objects.md`** — governs
  `InventoryDetailQuery`/`InventoryCatalogSerializer`,
  `PricePeriod.resolve`, `Appliers::SortApplier`/`Pagination`, and the
  serializer/query split; constrains the renamed params and the
  catalog `rarity_breakdown` reshaping.
- **`agent/styleguides/fetcher/caching.md`** — requires versioned
  normalized keys and bumping the version whenever the cached payload
  shape changes; constrains the cache-key renames and both version
  bumps.
- **`agent/styleguides/fetcher/admin-api-controllers.md`** — governs
  `Api::Admin::ApplicationController`; constrains removing the unused
  `current_admin_id` reader/ivar while keeping the admin token claim
  validation.
- **`agent/styleguides/fetcher/steam-response-objects.md`** — covers
  `Steam::Response`; confirms `SteamDataObjects` is an unused type alias
  and can be removed without changing the DTO contract.
- **`agent/styleguides/fetcher/architecture-layers.md`** — keeps the
  controller → query/serializer → model direction intact while names
  change; no new layer or collaborator is introduced.
- **`agent/styleguides/rails-layering.md`** — same cross-app
  dependency direction; removal of model/parser methods must not move
  their responsibilities into controllers.
- **`agent/styleguides/ruby-sorbet.md`** — every touched Ruby file
  keeps its sigil/`sig` discipline; removed methods/aliases must not
  leave dangling constants or type references.
- **`agent/styleguides/rspec-conventions.md`** — governs the updated
  fetcher specs and their level/example structure.
- **`agent/styleguides/core/react-dashboard.md`** — governs the
  dashboard/inventory/shared frontend structure, component naming,
  state/data-hook shape, and Vitest conventions; constrains the
  `PeriodToggle`/period-state/sort-key renames and test updates.
- **`agent/styleguides/core/architecture-layers.md`** — confirms the
  inventories island keeps reading the public, unauthenticated
  `app_fetcher` endpoints directly; no request-path change.
- **`agent/styleguides/git-commits.md`** — commit produced after
  implementation must follow the `[Scope] Imperative summary` format.

# Development Plan

## Goal

Resolve three review findings without changing any endpoint's actual
behavior beyond documented renames:

1. **#2 — base-controller naming drift.** Keep the real top-level
   `ApplicationController` where it is; update every current styleguide,
   ADR, and plan that calls it `Api::V1::ApplicationController`.
2. **#7 — dead code / stale comments.** Delete `Item#sorted_by`,
   `ItemParser.parse_collection`, `SteamDataObjects`, the unused
   `current_admin_id` reader/ivar, and the stale `SessionsController`
   TODO.
3. **#4 — one vocabulary per concept.** Rename the public-inventory
   detail contract and the matching frontend state/query params so the
   same concept always uses the same word: `period` (not `range`),
   `rarity_breakdown` (not `rarity_mix_percent`), `change_24h_desc`
   (not `delta_desc`), and `sort`/`page`/`per_page` (not
   `items_sort`/`items_page`/`items_per_page`). Per-endpoint defaults stay
   as they are.

## Expected Behavior

### #2 — docs only

- `app_fetcher/app/controllers/application_controller.rb` stays
  top-level and is still the base every `Api::V1::` controller inherits
  implicitly from inside its module.
- Current styleguides/ADRs describe it as `ApplicationController` (or
  explicitly "top-level `ApplicationController`") and explain that the
  V1 controllers inherit it; no current doc calls it
  `Api::V1::ApplicationController`.
- No application code changes for this finding.

### #7 — removals

- `Item.sorted_by` no longer exists; sorting is provided only by
  `Options::ItemSortOption`.
- `ItemParser.parse_collection` no longer exists.
- `Steam::SteamDataObjects` no longer exists.
- `Api::Admin::ApplicationController` no longer exposes
  `current_admin_id`, and no longer keeps `@current_admin_id`; the
  admin token's `admin_id` claim is still required/validated so a token
  without it remains rejected.
- `app_core/app/controllers/sessions_controller.rb` has no stale
  "Add rescue from" TODO; both existing `rescue` branches stay unchanged.

### #4 — vocabulary

Public inventory detail (`GET /api/public/inventories/:steam_id`):

- Query params are `period`, `sort`, `page`, `per_page`.
  - `period` defaults to `7d`, supports the existing
    `InventoryValueLog::SUPPORTED_PERIODS` set (no `24h`), and an
    unrecognized value returns
    `400 {"message":"Unsupported period: <value>"}`.
  - `sort` defaults to `price_desc` and accepts the existing
    `Options::ItemSortOption` values; an unrecognized value returns
    `400 {"message":"Unsupported sort: <value>"}`.
  - `page`/`per_page` default to `1`/`12` with the existing silent
    clamping.
- Response portfolio reports `period` instead of `range`.
- The rest of the detail response shape is unchanged, including
  `portfolio.change_cents`/`change_percent` (that change is scoped to
  the selected period, so it keeps its unqualified name).

Public inventory catalog (`GET /api/public/inventories`):

- Response key `rarity_mix_percent` becomes `rarity_breakdown`, using
  the same array shape as the detail endpoint:
  `[{ tier, count, percent }]` for all seven tiers.
- Everything else in the catalog response is unchanged.

Both public endpoints therefore expose exactly one rarity word
(`rarity_breakdown`) with one shape. Internally,
`InventoryDetailQuery`/`InventoryCatalogQuery` keep their
`rarity_counts` struct field because it is the raw count map the
serializers consume, not a response concept.

Frontend:

- PricePeriod state/props/components use `period`:
  `PeriodToggle`, `period`, `setPeriod`/`onPeriodChange`,
  `PERIOD_MS`, `generateAxisLabels(period)`,
  `PORTFOLIO_PERIODS`, `ITEM_PERIODS`, `INVENTORY_DETAIL_PERIODS`.
- Public detail hook sends `period`, `sort`, `page`, `per_page` and maps
  `portfolio.period`.
- Public catalog hook maps `rarity_breakdown`; both catalog cards and
  the detail legend derive percentages from the same breakdown array.
- Dashboard local sorting uses the server's value names:
  `change_24h_desc` / `change_24h_asc` (not `delta_desc` / `delta_asc`).
- Item mappings keep an explicit 24h name:
  `change24hCents` (not `changeCents`); unused `changeCents` fields are
  removed rather than renamed.
- The top-items sub-list uses `sort`/`page` state and props, matching its
  query params and its own `meta.page`/`meta.per_page` response.

### Unchanged

- Defaults stay per-endpoint: public detail `7d`, V1 inventory values
  `all`, V1 item history `30d`.
- `Api::V1::` request/response contracts are unchanged (they already use
  `period`).
- Admin endpoints, database columns (`change_24h_cents`), migrations, and
  authentication behavior are unchanged.
- No behavior change other than the renamed public query params/response
  keys and the catalog rarity shape.

## Scope

### In Scope

- Current-doc updates for the top-level `ApplicationController` name.
- Removal of the five dead-code/TODO items listed above and their
  now-orphaned specs.
- Public detail query-param/response-key renames, cache-key updates,
  serializers, query object, and specs.
- Public catalog `rarity_mix_percent` → `rarity_breakdown` response
  unification and specs.
- `app_core` frontend renames and test updates for the changed public
  contract and the unified vocabulary.
- Current-styleguide text updates for the renamed vocabulary.

### Out of Scope

- Moving `ApplicationController` into `Api::V1::` (explicitly declined;
  docs are corrected instead).
- Unifying per-endpoint period defaults.
- Renaming `Api::V1::` or admin params/response keys.
- Renaming the `change_24h_cents` DB column or the
  `portfolio.change_cents` key.
- Rewriting historical implemented plans (`public-inventory-endpoints.md`
  etc.) as if they had been written with the new names; the new plan is
  the record of the rename.
- Any change to caching TTLs, pagination limits, auth, or live-sync
  behavior.

## Implementation Approach

### Base-controller docs (#2)

Edit only prose references. In `internal-api-controllers.md`, make the
top-level nature explicit and note that `Api::V1::<X>Controller` resolves
`ApplicationController` to the root class; in
`public-api-controllers.md`, `public-api-namespace.md`,
`separate-admin-authentication.md`, and
`public-items-catalog-endpoint.md`, replace
`Api::V1::ApplicationController` with `ApplicationController` (or
"the top-level `ApplicationController`" where the sentence needs the
distinction). Do not change the ADR's architectural decision: `Api::Public::`
and `Api::Admin::` still have independent base controllers.

### Dead code (#7)

Delete the methods/type alias and their direct specs. For the admin base
controller, remove the `current_admin_id` reader and the
`@current_admin_id` assignment, but keep a `payload.fetch("admin_id")`
validation call so a token missing that claim still raises `KeyError`
and is rejected exactly as before.

### Public detail vocabulary (#4)

`InventoryDetailQuery` renames its `Page#range` to `Page#period` and
reads `params[:period]`, `params[:sort]`, `params[:page]`,
`params[:per_page]`, passing `param_name: "sort"` to
`Appliers::SortApplier`. Its error message becomes
`"Unsupported period: ..."`. `InventoryDetailSerializer` emits
`portfolio.period`. `InventoryDetailCache` normalizes the four renamed
params (and bumps its key version to invalidate old-shape payloads).

### Rarity vocabulary (#4)

`InventoryCatalogSerializer` returns `rarity_breakdown` as the same
seven-entry `[{ tier:, count:, percent: }]` array the detail serializer
already returns, computed from `summary.rarity_counts`. Bump
`InventoryCatalogCache::CACHE_KEY_VERSION` so a cached pre-rename
payload cannot be served. On the frontend, the catalog hook maps
`rarityBreakdown`, and `InventoryCard`/`RarityLegend` both derive the
percentage map for `RarityMixBar` from that array.

### Frontend vocabulary (#4)

Rename the shared `RangeToggle` component/file to `PeriodToggle` and its
`ranges`/`range` props to `periods`/`period`; rename `RANGE_MS` to
`PERIOD_MS` and `generateAxisLabels`'s parameter to `period`. Rename the
per-island constants and dashboard/inventory state keys to
`PORTFOLIO_PERIODS`, `ITEM_PERIODS`, `INVENTORY_DETAIL_PERIODS`,
`portfolioPeriod`, `itemPeriod`, and `PERIOD_CHANGED`. Keep the existing
option values (`24h`, `7d`, ...), defaults, and rendered labels.

Rename the dashboard local sort keys to `change_24h_desc`/
`change_24h_asc`; update its dropdown options/labels and pure sorter
tests. Remove the unused `changeCents` mapping from dashboard/tracked
items and use `change24hCents` where a 24h cents value is kept.

Rename inventory-detail state/props/query building from
`itemsSort`/`itemsPage`/`itemsPerPage` to `sort`/`page`/`perPage`, and
the dropdown identity from `itemsSort` to `sort`. The existing
`ItemsSortDropdown` file can keep its name; only its props/state keys
change to `sort`.

## Files To Modify

### `app_fetcher`

- `app_fetcher/app/queries/inventory_detail_query.rb` — `range` →
  `period`; `items_sort`/`items_page`/`items_per_page` →
  `sort`/`page`/`per_page`; error text.
- `app_fetcher/app/serializers/inventory_detail_serializer.rb` —
  `portfolio.range` → `portfolio.period`.
- `app_fetcher/app/serializers/inventory_catalog_serializer.rb` —
  `rarity_mix_percent` map → `rarity_breakdown` array.
- `app_fetcher/app/caching/inventory_detail_cache.rb` — renamed cache-key
  params; bump key version.
- `app_fetcher/app/caching/inventory_catalog_cache.rb` — bump key
  version for the changed payload shape.
- `app_fetcher/app/models/item.rb` — remove `sorted_by`.
- `app_fetcher/app/parsers/item_parser.rb` — remove
  `parse_collection`.
- `app_fetcher/lib/steam/response.rb` — remove `SteamDataObjects`.
- `app_fetcher/app/controllers/api/admin/application_controller.rb` —
  remove `current_admin_id` and `@current_admin_id`; keep `admin_id`
  claim validation.
- `app_fetcher/spec/models/item_spec.rb` — remove the `sorted_by`
  describe block.
- `app_fetcher/spec/parsers/item_parser_spec.rb` — remove the
  `parse_collection` describe block.
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb` — renamed
  params/fields/error messages.
- `app_fetcher/spec/serializers/inventory_detail_serializer_spec.rb` —
  `period` field and expectation.
- `app_fetcher/spec/serializers/inventory_catalog_serializer_spec.rb` —
  `rarity_breakdown` array shape.
- `app_fetcher/spec/caching/inventory_detail_cache_spec.rb` — renamed
  params.
- `app_fetcher/spec/requests/api/public/inventories_spec.rb` — renamed
  params, response keys, error messages, rarity shape.

### `app_core`

- `app_core/app/controllers/sessions_controller.rb` — remove stale TODO.
- `app_core/app/frontend/shared/components/RangeToggle.jsx` — rename
  file/component to `PeriodToggle.jsx`; `periods`/`period` props.
- `app_core/app/frontend/shared/components/HeroChart.jsx` — `period`
  prop; `PERIOD_MS`.
- `app_core/app/frontend/shared/chartConfig.js` — `PERIOD_MS`,
  `generateAxisLabels(period)`.
- `app_core/app/frontend/dashboard/chartConfig.js` — period-set names.
- `app_core/app/frontend/dashboard/reducer.js` — period state/actions.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — period props/actions;
  update hook arguments.
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx` —
  `PeriodToggle`, period props.
- `app_core/app/frontend/dashboard/utils/filters.js` — sort keys
  `change_24h_desc`/`change_24h_asc`.
- `app_core/app/frontend/dashboard/components/SortDropdown.jsx` — sort
  keys.
- `app_core/app/frontend/dashboard/hooks/useItemPrices.js` — map
  `change24hCents` (not `changeCents`).
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js` — skeleton
  uses `change24hCents`.
- `app_core/app/frontend/tracked_items/hooks/useItemsCatalog.js` — map
  `change24hCents` (remove unused `changeCents`).
- `app_core/app/frontend/inventories/chartConfig.js` —
  `INVENTORY_DETAIL_PERIODS`.
- `app_core/app/frontend/inventories/reducer.js` — `period`/`sort`/`page`
  state keys/actions.
- `app_core/app/frontend/inventories/InventoryDetail.jsx` — period/sort/
  page props/actions.
- `app_core/app/frontend/inventories/components/PortfolioHeroTile.jsx` —
  `PeriodToggle`, `portfolio.period`.
- `app_core/app/frontend/inventories/components/TopItemsList.jsx` —
  `sort`/`page` props, dropdown key.
- `app_core/app/frontend/inventories/hooks/useInventoryDetail.js` —
  `period`/`sort`/`page`/`perPage` params and `portfolio.period` mapping.
- `app_core/app/frontend/inventories/hooks/useInventoryCatalog.js` —
  `rarityBreakdown` mapping.
- `app_core/app/frontend/inventories/components/InventoryCard.jsx` —
  rarity percentages derived from `rarityBreakdown`.
- `app_core/app/frontend/inventories/utils/rarity.js` — shared helper
  for turning a breakdown array into a tier→percent map.
- Frontend tests: `shared/__tests__/HeroChart.test.jsx`,
  `dashboard/__tests__/PortfolioTile.test.jsx`,
  `dashboard/__tests__/reducer.test.js`,
  `dashboard/__tests__/filters.test.js`,
  `dashboard/__tests__/useItemPrices.test.js`,
  `dashboard/__tests__/useDashboardData.test.js`,
  `dashboard/__tests__/Dashboard.test.jsx`,
  `tracked_items/__tests__/useItemsCatalog.test.js`,
  `inventories/__tests__/useInventoryDetail.test.js`,
  `inventories/__tests__/InventoryDetail.test.jsx`,
  `inventories/__tests__/reducer.test.js`,
  `inventories/__tests__/useInventoryCatalog.test.js`,
  `inventories/__tests__/InventoriesIndex.test.jsx`,
  `inventories/__tests__/InventoryCard.test.jsx` — renamed fixtures,
  query params, response keys, sort keys, and period wording.

### Docs/styleguides

- `agent/styleguides/fetcher/internal-api-controllers.md` — explicit
  top-level `ApplicationController` note.
- `agent/styleguides/fetcher/public-api-controllers.md` — replace
  `Api::V1::ApplicationController`; remove `range` as an alternative
  period word.
- `agent/styleguides/fetcher/list-query-objects.md` — period-only
  wording.
- `agent/styleguides/core/react-dashboard.md` — `PeriodToggle`,
  `PERIOD_MS`, period-set wording.
- `agent/adr/fetcher/public-api-namespace.md` — top-level
  `ApplicationController` references.
- `agent/adr/core/separate-admin-authentication.md` — same.
- `agent/plans/public-items-catalog-endpoint.md` — same.

## Files To Create

- `app_core/app/frontend/shared/components/PeriodToggle.jsx` — renamed
  from `RangeToggle.jsx`; same presentational behavior, period-named
  props.
- `agent/plans/fix-naming-and-dead-code.md` — this plan.

No new backend classes, services, or abstractions.

## Test Plan

### Fetcher

- `spec/models/item_spec.rb`: remove the four `sorted_by` examples; the
  remaining model-scope specs stay green.
- `spec/parsers/item_parser_spec.rb`: remove the two
  `parse_collection` examples; single-item parsing coverage stays.
- `spec/queries/inventory_detail_query_spec.rb`:
  - default period is still `7d` and `page.period` exposes it;
  - `period=all` includes the full history;
  - invalid `period`/`24h` raise
    `Unsupported period: ...`;
  - `sort=name_asc` works and invalid `sort` raises
    `Unsupported sort: ...`;
  - default `page`/`per_page` are `1`/`12`, oversized `per_page` clamps
    to `100`.
- `spec/serializers/inventory_detail_serializer_spec.rb`: portfolio has
  `period: "30d"`, not `range`.
- `spec/serializers/inventory_catalog_serializer_spec.rb`:
  `rarity_breakdown` is a 7-entry array with the same
  tier/count/percent values the detail serializer produces.
- `spec/caching/inventory_detail_cache_spec.rb`: renamed params still
  round-trip and do not collide.
- `spec/requests/api/public/inventories_spec.rb`:
  - catalog response key list and rarity shape;
  - detail accepts `period`, `sort`, `page`, `per_page`, reports
    `portfolio.period`, and rejects bad `period`/`sort` with the renamed
    messages;
  - no `range`/`items_*` keys remain in the contracted responses.

### Core

- `RarityLegend.test.jsx` / `InventoryCard.test.jsx` /
  `useInventoryCatalog.test.js` / `InventoriesIndex.test.jsx`: catalog
  and detail both consume/derive from `rarity_breakdown`.
- `useInventoryDetail.test.js` / `InventoryDetail.test.jsx`: requests
  use `period`, `sort`, `page`, `per_page`; changing the period re-fetches
  with `period=...`.
- `reducer.test.js` (inventories): period/sort/page actions update the
  renamed keys and reset to page 1 on sort.
- `PortfolioTile.test.jsx` / `HeroChart.test.jsx`: period props still
  render the same toggles/charts.
- `filters.test.js`: `change_24h_desc`/`change_24h_asc` sort correctly.
- `useItemPrices.test.js` / `useDashboardData.test.js` /
  `tracked_items/useItemsCatalog.test.js`: mapped items expose
  `change24hCents`, not `changeCents`.
- Existing Vitest suite stays green; no test asserts a removed name.

## Implementation Steps

1. Write the plan (this file) and run `styleguides-check`.
2. `app_fetcher`: update docs for the top-level `ApplicationController`
   (#2) — no code change.
3. `app_fetcher`: remove the dead scopes/methods/type alias/TODO and
   their orphaned specs (#7); keep the admin `admin_id` claim check.
4. `app_fetcher`: rename the detail query params/fields, serializer key,
   and cache keys; update cache-key versions (#4).
5. `app_fetcher`: unify catalog and detail rarity output to
   `rarity_breakdown` arrays; update the catalog cache version.
6. Update fetcher specs first where practical (rename assertions), then
   run the targeted specs to confirm the new contract.
7. `app_core`: rename shared/dashboard/inventory period vocabulary and
   the dashboard sort keys; remove unused `changeCents` mappings.
8. `app_core`: update the public-detail hook and rarity consumers; update
   all affected Vitest fixtures/assertions.
9. Update the current styleguides/ADR references to the new naming.
10. Run the full verification set below; fix any regressions without
    changing behavior beyond this plan.

## Verification

- `docker compose exec app_fetcher bundle exec rspec spec/models/item_spec.rb spec/parsers/item_parser_spec.rb spec/queries/inventory_detail_query_spec.rb spec/serializers spec/caching/inventory_detail_cache_spec.rb spec/requests/api/public/inventories_spec.rb`
- `docker compose exec app_fetcher bundle exec rspec` (full fetcher
  suite)
- `docker compose exec app_fetcher bundle exec srb tc`
- `docker compose exec app_fetcher bin/rubocop` on changed Ruby files.
- `docker compose exec app_core npm test` (Vitest; or the project's
  configured Vitest command from `app_core`/repo root).
- `docker compose exec app_core npm run lint` / Prettier check for
  changed frontend files.
- Grep verification that no current code/docs still reference
  `Api::V1::ApplicationController`, `sorted_by`,
  `parse_collection`, `SteamDataObjects`, `current_admin_id`,
  `items_sort`, `items_page`, `items_per_page`, `rarity_mix_percent`,
  or `delta_desc` outside historical plans.

## Risks

- **Breaking public contract:** `range`/`items_*` and
  `rarity_mix_percent` are currently consumed only by `app_core`, which
  this plan updates in lockstep. Any external/manual client must switch
  to the new names.
- **Catalog rarity shape change:** changing a map to an array is larger
  than a key rename. Both frontend consumers must derive percentages
  from the array; the shared helper keeps card and detail rendering
  consistent.
- **Cache staleness:** old cache entries use the old key/response shape.
  Bump both cache-key versions so no pre-rename payload survives the
  deploy.
- **Ruby constant lookups:** leaving `ApplicationController` at the root
  means V1 controllers still resolve it lexically; docs must not imply a
  namespaced class exists. This is the explicitly chosen fix.
- **Over-renaming:** `changeCents` is a legitimate period-scoped name for
  the portfolio delta; only the 24h item aliases are removed. Do not
  rename `portfolio.change_cents` or the DB column.

## Assumptions

- No external clients depend on the old public param/key names; the
  repository's only consumer is `app_core`.
- The catalog rarity array is acceptable as a slightly larger response
  in exchange for one shape and one name across both public endpoints.
- Per-endpoint period defaults remain intentionally different, per the
  user's decision not to unify them.

## Completion Criteria

- No current styleguide/ADR/plan calls the root base controller
  `Api::V1::ApplicationController`.
- All five dead-code/TODO items and their orphaned specs are gone.
- Public inventory detail uses `period`/`sort`/`page`/`per_page`, and
  both public endpoints expose `rarity_breakdown` arrays.
- Frontend uses the same vocabulary and sends the new query params.
- Defaults and all non-renamed behavior are unchanged.
- Fetcher specs, Sorbet, RuboCop, and Vitest are green.

---

# Implementation Summary

## Implemented

- **#2 (docs only):** kept the top-level
  `app_fetcher/app/controllers/application_controller.rb` in place and
  corrected every current doc reference that called it
  `Api::V1::ApplicationController` — `internal-api-controllers.md` now
  states explicitly that it is the top-level class the V1 controllers
  resolve lexically, and `public-api-controllers.md`, the public-api ADR,
  the admin-authentication ADR, and the public-items-catalog plan use the
  correct name.
- **#7 (dead code):** removed `Item#sorted_by` and its spec,
  `ItemParser.parse_collection` and its specs, the
  `Steam::SteamDataObjects` alias, and the stale
  `SessionsController` rescue TODO. Removed
  `Api::Admin::ApplicationController#current_admin_id` and its ivar; the
  `admin_id` claim is still required/validated via
  `payload.fetch("admin_id")`, so a token without it is still rejected.
  Current docs mentioning the removed items (`admin-api-controllers.md`,
  `steam-response-objects.md`, `list-query-objects-layer.md`) were updated.
- **#4 (public detail params/response):** renamed the public inventory
  detail contract to `period`, `sort`, `page`, `per_page`;
  `InventoryDetailQuery::Page#period` replaces `#range`;
  `InventoryDetailSerializer` emits `portfolio.period`; error messages
  are now `Unsupported period: ...` / `Unsupported sort: ...`; the cache
  key uses the new names and its version was bumped to `3`.
- **#4 (rarity vocabulary):** `InventoryCatalogSerializer` now emits
  `rarity_breakdown` as the same seven-entry
  `[{ tier, count, percent }]` array as the detail endpoint.
  `InventoryCatalogCache::CACHE_KEY_VERSION` was bumped to `3`.
  Internally the query structs keep `rarity_counts` because that is the
  raw count source, not a response concept.
- **#4 (frontend):** renamed `RangeToggle` → `PeriodToggle` (file,
  component, props, CSS classes), `RANGE_MS` → `PERIOD_MS`,
  `generateAxisLabels(period)`, `PORTFOLIO_*`/`ITEM_*`/`INVENTORY_DETAIL_*`
  period constants and state/actions, and the detail hook/API params.
  Catalog and detail rarity consumers both derive percentages from
  `rarityBreakdown` via `rarityPercentages`. Dashboard local sorting is
  now `change_24h_desc`/`change_24h_asc`; unused `changeCents` aliases
  were replaced with `change24hCents`. The admin `changePercent` helper's
  parameter is now `change24hCents`.

## Tests

- Updated fetcher specs for the renamed params/fields, catalog rarity
  array, cache keys, and dead-code removals.
- Updated Vitest fixtures/assertions for period, sort/page/perPage,
  `change24hCents`, `change_24h_*` sorts, and catalog
  `rarity_breakdown` arrays.
- Added a render wait to the grid-view tracked-items test to remove a
  pre-existing race that surfaced when the full parallel suite ran
  slower; the assertion itself is unchanged.

Commands actually executed:

```text
docker run --rm --network gracious-nash-2953c3_default \
  -v "$PWD/app_fetcher:/app" -w /app -e RAILS_ENV=test \
  ... proud-engine-app_fetcher bundle exec rspec
docker run --rm -v "$PWD/app_fetcher:/app" -w /app \
  proud-engine-app_fetcher bundle exec srb tc
docker run --rm -v "$PWD/app_fetcher:/app" -w /app \
  proud-engine-app_fetcher bundle exec rubocop <changed fetcher files>
cd app_core && npm test
cd app_core && npm run lint
cd app_core && npm run format:check
```

## Verification

- Targeted fetcher specs: **106 examples, 0 failures**.
- Full fetcher suite: **463 examples, 0 failures**.
- `srb tc`: **No errors**.
- RuboCop on all changed fetcher Ruby/spec files: **no offenses**.
- Full Vitest suite: **49 files, 306 tests, 0 failures**.
- `npm run format:check`: all matched files formatted.
- `npm run lint`: **0 errors, 1 pre-existing warning** in
  `tracked_items/TrackedItems.jsx` (`react-hooks/exhaustive-deps`), a
  file untouched by this change.

## Deviations

- The plan's verification section named `docker compose` commands; the
  worktree had no running compose stack and the available image could not
  load this branch's Gemfile.lock, so an image from a sibling worktree
  (`proud-engine-app_fetcher`) was run against this worktree's mounted
  code on the existing `gracious-nash-2953c3_default` network. Same
  specs, Sorbet, and RuboCop, no application-code difference.
- Added the tracked-items grid test wait described above to make the full
  Vitest suite deterministic; this is test-only and outside the original
  file list.
- Updated three additional current docs for now-removed names
  (`admin-api-controllers.md`, `steam-response-objects.md`, and the
  list-query-objects ADR), which the plan's stale-reference sweep
  implicitly required.

## Remaining Issues

- Pre-existing `react-hooks/exhaustive-deps` warning in
  `app_core/app/frontend/tracked_items/TrackedItems.jsx`; out of scope
  here.
- Historical implemented plans (e.g. `public-inventory-endpoints.md`)
  intentionally keep the old `range`/`items_*`/`rarity_mix_percent`
  vocabulary as a record of what was originally planned; this plan is the
  record of the rename.
