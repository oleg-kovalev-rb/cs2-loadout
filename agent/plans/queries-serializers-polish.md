---
status: implemented
app: fetcher
goal: Rename and simplify app_fetcher query/serializer result objects, centralize inventory value aggregation, and remove duplicated response shaping without changing API contracts
created: 2026-10-20
---

# Development Plan

## Goal

Polish `app_fetcher`'s query and serializer layers so every query result is
named after what it contains, the inventory-value calculation is expressed
through one typed concern API, and response-shaping math exists in one place
per concept — while keeping every HTTP JSON contract and database behavior
unchanged.

## Expected Behavior

- Public `GET /api/public/items`, `GET /api/public/inventories`, and
  `GET /api/public/inventories/:steam_id` return the same JSON keys and values
  for the same data/params as before.
- V1 `GET /api/v1/inventory_values` and
  `GET /api/v1/item_prices/:market_hash_name/history` return the same JSON
  shapes as before.
- Admin `POST /api/admin/items/warm_catalog_cache` still warms the same
  logical catalog cache entry and returns the same response.
- Inventory catalog/detail/V1 calculations share one `InventoryValueQuery`
  (renamed from `InventoryValuation`):
  - current value snapshot,
  - history series,
  - delta (cents/percent/basis/partial/available),
  - baseline selection,
  - aggregate SQL projection.
- Catalog inventory cards and detail/V1 responses keep identical change
  semantics:
  - catalog `change_basis_at` remains a date (`YYYY-MM-DD`);
  - detail/V1 `change_basis_at` remains a timestamp;
  - unavailable changes remain `0` cents / `0.0` percent with
    `available: false`;
  - partial/completeness flags keep their current meaning.
- Query result types no longer use the vague names `Page`, `Listing`,
  `Detail`, `Change`, `Snapshot`, or `Valuation`.
- `ItemCatalogQuery` is renamed to `ItemListQuery`, with its serializer/cache
  renamed consistently.
- Query objects still return `T::Struct`s; serializers still perform no I/O;
  controllers still own response caches and conditional GET.
- No database schema changes, no migrations, no `app_core` changes.

## Scope

### In Scope

- Rename and restructure:
  - `InventoryValuation` → `InventoryValueQuery`;
  - `InventoryCatalogQuery` → `InventoryListQuery`;
  - `ItemCatalogQuery` → `ItemListQuery`;
  - `InventoryCatalogSerializer` → `InventoryListSerializer`;
  - `ItemCatalogSerializer` → `ItemListSerializer`;
  - `InventoryCatalogCache` → `InventoryListCache`;
  - `ItemCatalogCache` → `ItemListCache`;
  - `InventoryValuationSerializer` → `InventoryValueSerializer`.
- Result-struct renames and composition:
  - `InventoryValueQuery::ValueSnapshot`, `ValueDelta`, `ValueHistory`,
    `ValueHistory::Point`, `InventoryValue`;
  - `InventoryListQuery::InventorySummaries` + `InventorySummary`
    (`snapshot`, `delta`, `last_synced_at`, `rarity_counts`);
  - `InventoryDetailQuery::InventoryDetails` + `InventoryItems`;
  - `ItemListQuery::ItemCatalog` + `PriceChangeStats`;
  - `ItemPriceHistoryQuery::ItemPriceHistory` + `PricePoint`.
- Replace `AGGREGATE_COLUMNS` exposure with
  `InventoryValueQuery.with_aggregates(scope)`; make SQL projection constants
  private; remove the unused `AGGREGATE_EXPRESSIONS` duplication or make it
  the single private source used by both paths.
- Compose `InventoryDetails` from `InventoryValueQuery::InventoryValue` +
  `InventoryItems`; delete `HistoryPoint`.
- Move baseline/change logic (`BASELINE_MAX_AGE_DAYS`, `change_for`) from
  `InventoryCatalogQuery` into `InventoryValueQuery#delta_for`.
- Shared serializers/helpers:
  - `ItemMetadataSerializer` for the public 7-key item metadata;
  - `PriceChangePercent` pure helper for `change_24h_percent`;
  - `RarityBreakdownSerializer` for the 7-tier breakdown;
  - `RarityBreakdownQuery` concern for per-inventory rarity counting.
- Add `ItemPriceHistorySerializer`; remove the inline point mapping from
  `Api::V1::ItemPricesController#history`.
- Keep query struct timestamps as `Time` (normalized UTC) and format with
  `.iso8601` in serializers.
- Update living docs:
  - `agent/styleguides/fetcher/list-query-objects.md`,
  - `agent/styleguides/fetcher/caching.md`,
  - `agent/styleguides/fetcher/architecture-layers.md`,
  - `agent/styleguides/fetcher/services.md`,
  - `agent/styleguides/fetcher/admin-api-controllers.md`,
  - `agent/adr/fetcher/list-query-objects-layer.md`,
  - `agent/adr/fetcher/cross-scenario-service-layer.md`,
  - `agent/US/dashboard-user-story.md`.
- Update query/serializer/cache/request/service specs and add unit specs for
  new shared helpers.

### Out of Scope

- Changing any public/V1/admin JSON key, status, error body, or ordering
  guarantee beyond equal-timestamp tie-breaking where explicitly noted.
- Changing filters, sort vocabularies, pagination defaults, cache TTLs, or
  error classes.
- Changing `PriceHistoryCache` / `ItemTrendCache` payload format or unifying
  them on a shared `PricePoint`.
- Refactoring `Appliers::*` or `Options::*` beyond any test-helper adjustment
  required by `with_aggregates`.
- `app_core`, dashboard/frontend changes.
- Database schema, migrations, backfills.
- Rewriting historical plan files in `agent/plans/`.
- Performance tuning beyond preserving current query counts.

## Applicable Styleguides

- `agent/styleguides/fetcher/list-query-objects.md` — query/result naming
  (`ListQuery`/`DetailQuery`/`HistoryQuery`/concern), content-named result
  structs, `with_aggregates(scope)`, UTC `Time`/`Date` boundaries, shared
  serializers/helpers, and testing rules.
- `agent/styleguides/ruby-sorbet.md` — `typed: strict`, sigs, `T::Struct`,
  `T.nilable`/`T.must`, private constants, and avoiding `T.untyped` in the
  rewritten query/serializer code.
- `agent/styleguides/fetcher/caching.md` — versioned cache keys, TTL-only
  cache behavior, and cache class rename/namespace rules.
- `agent/styleguides/fetcher/public-api-controllers.md` — Public list/detail
  controller flow, cache/ETag ownership, and error handling.
- `agent/styleguides/fetcher/internal-api-controllers.md` — V1 history/value
  controller flow and error handling.
- `agent/styleguides/fetcher/services.md` — `InventoryValueRecordingService`
  read-step dependency on the renamed concern query.
- `agent/styleguides/fetcher/admin-api-controllers.md` — admin
  `warm_catalog_cache` action and response shape.
- `agent/styleguides/fetcher/architecture-layers.md` — query/serializer/
  caching dependency boundaries and layer membership.
- `agent/styleguides/rails-layering.md` — cross-app one-directional layer
  dependency invariant.
- `agent/styleguides/rspec-conventions.md` — query/serializer unit-spec
  levels, path mirroring, and request-spec coverage.

Related ADR: `agent/adr/fetcher/list-query-objects-layer.md` — updated with
the `ListQuery` naming, content-named result structs, concern aggregate
projection, and shared serializer/helper decision.

## Implementation Approach

Work in four layers, keeping the app green after each phase:

1. **Concern first.** Rename `InventoryValuation` to `InventoryValueQuery`,
   introduce `ValueSnapshot` / `ValueDelta` / `ValueHistory` /
   `InventoryValue`, replace public aggregate columns with
   `with_aggregates(scope)`, and move baseline/delta logic into the concern.
2. **Inventory endpoint results.** Rename `InventoryCatalogQuery` to
   `InventoryListQuery` and compose `InventorySummaries`; restructure
   `InventoryDetailQuery` into `InventoryDetails` + `InventoryItems`; update
   `InventoryValueHistoryQuery` to return `InventoryValue`.
3. **Serializers/helpers.** Rename list/value serializers, add
   `ItemMetadataSerializer`, `PriceChangePercent`,
   `RarityBreakdownSerializer`, `RarityBreakdownQuery`, and
   `ItemPriceHistorySerializer`; update detail/item serializers to use them.
4. **Item queries + call sites/docs/tests.** Rename `ItemCatalogQuery` →
   `ItemListQuery`, rename its serializer/cache, update controllers/admin
   warm path, cache namespaces/versions, living docs, and specs.

No behavior should be changed to make the refactor easier. If a rename or
composition would change a JSON value, stop and preserve the old value in the
serializer instead.

### Concern API (concise)

Use this public API on `InventoryValueQuery`:

```ruby
InventoryValueQuery.snapshot_for(user_inventory)        # => ValueSnapshot
InventoryValueQuery.snapshot_from(record)               # => ValueSnapshot
InventoryValueQuery.delta_for(snapshot, baseline)       # => ValueDelta
InventoryValueQuery.history(steam_id, range, current:)  # => ValueHistory
InventoryValueQuery.call(steam_id, range)             # => InventoryValue
InventoryValueQuery.with_aggregates(scope)              # => ActiveRecord::Relation
InventoryValueQuery.baseline_for(steam_ids, since_date) # => Hash[String, InventoryValueLog]
```

`InventoryDetailQuery` composes `snapshot_for` + `history` +
`InventoryValue.new(...)`; `InventoryValueHistoryQuery` calls `call`.

## Files To Modify

### Query layer

- `app_fetcher/app/queries/inventory_valuation.rb` → rename to
  `inventory_value_query.rb`:
  - rename class and nested types;
  - `Snapshot` → `ValueSnapshot`, `Change` → `ValueDelta`,
    `Series` → `ValueHistory`, `Point` → `ValueHistory::Point`,
    `Page` → `InventoryValue`;
  - `.current` → `.snapshot_for`, `.series` → `.history`, `.page` →
    `.call`, `.change_for` → `.delta_for`;
  - add `.with_aggregates` / `.snapshot_from`;
  - make aggregate/SQL constants private;
  - move `BASELINE_MAX_AGE_DAYS` and baseline delta logic here;
  - normalize timestamps to UTC `Time`.
- `app_fetcher/app/queries/inventory_catalog_query.rb` → rename to
  `inventory_list_query.rb`:
  - class `InventoryListQuery`;
  - result `InventorySummaries`, summary fields `snapshot` + `delta` +
    `last_synced_at` + `rarity_counts`;
  - use `InventoryValueQuery.with_aggregates`, `snapshot_from`,
    `delta_for`, `baseline_for`;
  - use `RarityBreakdownQuery.call`;
  - remove `AGGREGATE_COLUMNS` and positional row destructuring.
- `app_fetcher/app/queries/inventory_detail_query.rb`:
  - `Page` → `InventoryDetails`; add nested `InventoryItems`;
  - delete `HistoryPoint`;
  - compose `InventoryValue` + `InventoryItems`;
  - use `RarityBreakdownQuery.call([ user_inventory.id ]).fetch(user_inventory.id, {})`;
  - timestamps as `Time`.
- `app_fetcher/app/queries/inventory_value_history_query.rb`:
  - return `InventoryValueQuery::InventoryValue`;
  - call `InventoryValueQuery.call`.
- `app_fetcher/app/queries/item_catalog_query.rb` → rename to
  `item_list_query.rb`:
  - class `ItemListQuery`;
  - `Page` → `ItemCatalog`; `PriceStats` → `PriceChangeStats`;
  - `DEFAULT_PER_PAGE = 25` passed explicitly;
  - `last_synced_at` as `T.nilable(Time)`;
  - keep `trends`/marketable/filter/sort behavior.
- `app_fetcher/app/queries/item_price_history_query.rb`:
  - `Page` → `ItemPriceHistory`; `Point` → `PricePoint`;
  - `at` as `Time`;
  - add `.order(:created_at, :id)`.
- `app_fetcher/app/queries/rarity_breakdown_query.rb` (new concern):
  - `.call(user_inventory_ids)` → per-inventory tier counts;
  - single-inventory callers pass `[id]` and fetch their entry;
  - preserve `RarityTier.for_item` semantics.

### Serializer layer

- `app_fetcher/app/serializers/inventory_catalog_serializer.rb` → rename to
  `inventory_list_serializer.rb`:
  - input `InventoryListQuery::InventorySummaries`;
  - use `snapshot`/`delta`; use `RarityBreakdownSerializer`;
  - format `change_basis_at` as date and `last_synced_at` as timestamp.
- `app_fetcher/app/serializers/inventory_detail_serializer.rb`:
  - input `InventoryDetailQuery::InventoryDetails`;
  - portfolio from `value.snapshot` + `value.history.delta`;
  - top items from `items`;
  - use `ItemMetadataSerializer`, `PriceChangePercent`,
    `RarityBreakdownSerializer`;
  - `T.must(details.value.snapshot)` for the always-present detail snapshot.
- `app_fetcher/app/serializers/inventory_valuation_serializer.rb` → rename to
  `inventory_value_serializer.rb`:
  - input `InventoryValueQuery::InventoryValue`;
  - current from `snapshot`, history from `history.points`, change from
    `history.delta`;
  - format timestamps with `.iso8601`.
- `app_fetcher/app/serializers/item_catalog_serializer.rb` → rename to
  `item_list_serializer.rb`:
  - input `ItemListQuery::ItemCatalog`;
  - use `PriceChangeStats`, `ItemMetadataSerializer`,
    `PriceChangePercent`;
  - format `last_synced_at`.
- `app_fetcher/app/serializers/item_price_dynamics_serializer.rb`:
  - use `PriceChangePercent`; output unchanged.
- `app_fetcher/app/serializers/inventory_serializer.rb`:
  - no behavior change (V1 `inventories/me`).
- `app_fetcher/app/serializers/item_metadata_serializer.rb` (new):
  - exactly the 7 public metadata keys.
- `app_fetcher/app/serializers/price_change_percent.rb` (new):
  - `.call(current_cents:, change_cents:)`; zero-base → `0.0`, otherwise
    `round(2)`.
- `app_fetcher/app/serializers/rarity_breakdown_serializer.rb` (new):
  - 7 tiers, counts/percent against classified total.
- `app_fetcher/app/serializers/item_price_history_serializer.rb` (new):
  - `call(ItemPriceHistoryQuery::ItemPriceHistory)` → array of
    `{ at:, price_cents:, volume: }`.

### Cache layer

- `app_fetcher/app/caching/inventory_catalog_cache.rb` → rename to
  `inventory_list_cache.rb`:
  - class `InventoryListCache`; key namespace `inventory_list`;
    bump `CACHE_KEY_VERSION`.
- `app_fetcher/app/caching/item_catalog_cache.rb` → rename to
  `item_list_cache.rb`:
  - class `ItemListCache`; key namespace `items_list`;
    bump `CACHE_KEY_VERSION`.
- `app_fetcher/app/caching/inventory_detail_cache.rb`,
  `price_history_cache.rb`, `item_trend_cache.rb`: unchanged.

### Controllers / services

- `app_fetcher/app/controllers/api/public/items_controller.rb`:
  - `ItemListQuery` / `ItemListSerializer`.
- `app_fetcher/app/controllers/api/public/inventories_controller.rb`:
  - `InventoryListCache` / `InventoryListQuery` / `InventoryListSerializer`;
  - detail path only changes local variable/type names.
- `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb`:
  - `InventoryValueSerializer`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb`:
  - query branch calls `ItemPriceHistorySerializer.call(ItemPriceHistoryQuery.call(...))`;
  - 30d cache branch remains unchanged.
- `app_fetcher/app/controllers/api/admin/items_controller.rb`:
  - `ItemListQuery` / `ItemListSerializer` in `#warm_catalog_cache`;
  - route/method name `warm_catalog_cache` stays unchanged.
- `app_fetcher/app/services/inventory_value_recording_service.rb`:
  - `InventoryValueQuery.snapshot_for` + `ValueSnapshot` types.

### Documentation

- `agent/styleguides/fetcher/list-query-objects.md`
- `agent/styleguides/fetcher/caching.md`
- `agent/styleguides/fetcher/architecture-layers.md`
- `agent/styleguides/fetcher/services.md`
- `agent/styleguides/fetcher/admin-api-controllers.md`
- `agent/adr/fetcher/list-query-objects-layer.md`
- `agent/adr/fetcher/cross-scenario-service-layer.md`
- `agent/US/dashboard-user-story.md`

## Files To Create

- `app_fetcher/app/queries/rarity_breakdown.rb` — shared per-inventory
  rarity counting used by list/detail queries.
- `app_fetcher/app/serializers/item_metadata_serializer.rb` — public
  7-key metadata shaping.
- `app_fetcher/app/serializers/price_change_percent.rb` — shared percent
  calculation.
- `app_fetcher/app/serializers/rarity_breakdown_serializer.rb` — 7-tier
  breakdown response shaping.
- `app_fetcher/app/serializers/item_price_history_serializer.rb` — query
  branch point serialization.
- Specs:
  - `app_fetcher/spec/queries/rarity_breakdown_spec.rb`
  - `app_fetcher/spec/serializers/item_metadata_serializer_spec.rb`
  - `app_fetcher/spec/serializers/price_change_percent_spec.rb`
  - `app_fetcher/spec/serializers/rarity_breakdown_serializer_spec.rb`
  - `app_fetcher/spec/serializers/item_price_history_serializer_spec.rb`

## Test Plan

### Query specs

- Rename/move:
  - `spec/queries/inventory_valuation_spec.rb` →
    `inventory_value_query_spec.rb`;
  - `spec/queries/inventory_catalog_query_spec.rb` →
    `inventory_list_query_spec.rb`;
  - `spec/queries/item_catalog_query_spec.rb` →
    `item_list_query_spec.rb`.
- Update assertions to the new nested results:
  - `summary.snapshot.items_count`, `summary.delta.cents`,
    `summary.last_synced_at` as `Time`;
  - `details.value.snapshot...`, `details.value.history...`,
    `details.items.entries`;
  - `catalog.items`, `catalog.price_change_stats`,
    `catalog.last_synced_at` as `Time`;
  - `history.points.first.at` as `Time`.
- Add direct `InventoryValueQuery` cases:
  - `.snapshot_for` / `.snapshot_from` aliased aggregates;
  - `.delta_for` nil baseline, stale baseline, partial baseline;
  - `.history` empty/single/multiple points and live point replacement;
  - `.call` unknown `steam_id` (`snapshot: nil`, empty history);
  - `.with_aggregates` keeps aliases used by sort.
- Add `RarityBreakdownQuery` cases:
  - per-inventory grouping;
  - star-prefixed / Extraordinary / Contraband → Gold;
  - unknown rarity omitted;
  - empty ids.

### Serializer specs

- Rename/move:
  - `inventory_catalog_serializer_spec.rb` → `inventory_list_serializer_spec.rb`;
  - `inventory_valuation_serializer_spec.rb` → `inventory_value_serializer_spec.rb`.
- Update inputs to new structs and `Time` values; assert output keys/values
  are unchanged.
- Add unit specs for:
  - `ItemMetadataSerializer` (exactly 7 keys);
  - `PriceChangePercent` (nil/zero base, positive/negative, rounding);
  - `RarityBreakdownSerializer` (all tiers, zero classified total);
  - `ItemPriceHistorySerializer` (array shape, empty, timestamp format).
- Keep `InventorySerializer` and `ItemPriceDynamicsSerializer` specs green.

### Request/cache/service specs

- Request specs should pass with only the `InventoryCatalogQuery` stub renamed
  to `InventoryListQuery`; no expected JSON changes.
- Rename `spec/caching/inventory_catalog_cache_spec.rb` →
  `inventory_list_cache_spec.rb`; update class references.
- Add/adjust `item_list_cache_spec.rb` rename only if `ItemCatalogCache` spec
  exists (it does).
- `InventoryValueRecordingService` spec should pass with the renamed concern
  types; no behavior changes.
- Verify `ItemPricesController#history` cached and query branches still
  return identical JSON for the same data.

## Implementation Steps

1. **Rename concern with behavior preserved.**
   - Rename `inventory_valuation.rb` to `inventory_value_query.rb`;
     rename types/methods; keep `.current`/`.series`/`.page` behavior
     temporarily if needed to keep call sites compiling, then update them.
   - Add `ValueDelta`, `ValueHistory`, `InventoryValue`, `with_aggregates`,
     `snapshot_from`, `delta_for`; make aggregate constants private.
   - Move baseline/delta logic from catalog into the concern.
   - Update `InventoryValueRecordingService` and its specs.
2. **Restructure inventory list query.**
   - Rename `InventoryCatalogQuery` → `InventoryListQuery`; introduce
     `InventorySummaries`/`InventorySummary`.
   - Replace `AGGREGATE_COLUMNS`/positional rows with
     `with_aggregates` + `snapshot_from`; use `RarityBreakdownQuery`.
   - Keep sort/pagination/count behavior identical.
3. **Restructure inventory detail query.**
   - Introduce `InventoryDetails` + `InventoryItems`; delete `HistoryPoint`.
   - Compose `InventoryValue` from snapshot + history; use `RarityBreakdownQuery`.
   - Preserve top-items pagination/sort/trends and priciest/avg behavior.
4. **Update inventory serializers + shared helpers.**
   - Rename list/value serializers; update detail serializer to the new
     structs.
   - Add `ItemMetadataSerializer`, `PriceChangePercent`,
     `RarityBreakdownSerializer`; replace duplicated logic.
   - Verify public inventory JSON contracts with request specs.
5. **Update V1 value history path.**
   - `InventoryValueHistoryQuery` returns `InventoryValue`;
     `InventoryValuesController` uses `InventoryValueSerializer`;
     keep unknown-`steam_id` behavior.
6. **Restructure item queries.**
   - Rename `ItemCatalogQuery` → `ItemListQuery`; result `ItemCatalog`,
     `PriceChangeStats`, `last_synced_at` as `Time`.
   - Rename serializer/cache consistently; update public/admin call sites.
   - Restructure `ItemPriceHistoryQuery` (`ItemPriceHistory`/`PricePoint`,
     `Time`, stable order); add `ItemPriceHistorySerializer` and use it in
     the controller.
7. **Rename caches and bump versions.**
   - `InventoryListCache` / `ItemListCache`; update cache specs and TTL
     assertions.
8. **Update living docs and styleguide references.**
   - Apply the names from this plan to the living docs listed above.
9. **Run the full verification suite and fix drift.**
   - Specs, RuboCop, Sorbet; then re-run request specs to confirm contracts.

## Verification

Run in `app_fetcher`:

- `bundle exec rspec spec/queries spec/serializers spec/caching`
- `bundle exec rspec spec/requests/api/public spec/requests/api/v1`
- `bundle exec rspec spec/services/inventory_value_recording_service_spec.rb`
- `bundle exec rspec` (full app suite)
- `bundle exec rubocop`
- `bundle exec srb tc`

`bin/ci` is currently broken in `app_fetcher` per
`agent/styleguides/fix_me.md`; run the individual commands above unless that
entry has been resolved separately.

Manual/structural checks:

- `grep` confirms no remaining `InventoryValuation`, `InventoryCatalog*`,
  `ItemCatalogQuery`, `Page`/`Listing`/`Detail` result names in app code and
  living docs (historical plans excluded).
- Public/V1 request specs confirm identical JSON keys/values.
- `Options::InventorySortOption` specs still exercise aggregate sorting
  through `InventoryValueQuery.with_aggregates`.
- Cache key specs confirm no cross-namespace collisions; old namespaces are
  not read by new classes.

## Risks

- **Timestamp type/format drift.** Converting query structs from strings to
  `Time` can change `iso8601` output (`Z` vs `+00:00`) or timezone. Normalize
  to UTC and rely on request specs to lock the exact strings.
- **Sorbet `Time` vs `ActiveSupport::TimeWithZone`.** AR attributes are
  time-zone-aware; use explicit `.to_time.utc` normalization for struct
  fields typed as `Time`.
- **Nilable detail snapshot.** `InventoryValue#snapshot` is nilable for V1
  unknown inventories; detail serializer must handle the always-present case
  with `T.must` or an explicit branch.
- **Aggregate alias sort.** `with_aggregates` must keep
  `total_value_cents`/`items_count` in `SELECT`; otherwise
  `Options::InventorySortOption` breaks.
- **`select` append behavior.** `with_aggregates` assumes Rails appends to an
  existing `select` list; verify with the query specs and generated SQL.
- **Rarity semantics.** `RarityBreakdownQuery` must preserve `RarityTier.for_item`
  behavior for `★`, Extraordinary, and Contraband; add explicit specs.
- **Cache rename.** Old cache keys become unreachable; 2-minute TTL bounds
  staleness. Bump version/namespace deliberately.
- **No-op search cache key.** `InventoryListCache` must keep excluding
  `search` from the key (current behavior/spec).
- **Route/method names.** Keep `warm_catalog_cache` route/method names even
  after renaming the query/serializer/cache, to avoid an admin API change.
- **Documentation drift.** Many living docs reference old names; update only
  living docs, not historical plans.

## Assumptions

- `ItemListQuery::ItemCatalog` keeps `ItemCatalog` as the content-based result
  name even though the query is `ItemListQuery`.
- `ItemCatalogSerializer`/`ItemCatalogCache` are renamed to
  `ItemListSerializer`/`ItemListCache` for consistency, while the admin route
  and method name `warm_catalog_cache` remain unchanged.
- `ItemPriceHistorySerializer` returns a bare array, matching the current API.
- Query structs use UTC `Time` for timestamps; serializers keep the existing
  date vs timestamp formatting per endpoint.
- `PriceHistoryCache` / `ItemTrendCache` remain hash-based and untouched.
- Historical plan files in `agent/plans/` are not rewritten.

## Completion Criteria

- All query result objects use the new content-based names and compose shared
  value types instead of duplicating fields.
- `InventoryValueQuery` owns aggregate SQL, snapshot/history/delta, and
  baseline selection; catalog/detail/V1 all use the same API.
- Shared serializer helpers remove duplicated metadata/percent/rarity logic.
- Public/V1/admin request specs pass without JSON contract changes.
- Query/serializer/cache/service specs pass; new helper/concern specs cover
  edge cases.
- `bundle exec rubocop` and `bundle exec srb tc` pass.
- Living docs reference the new names; historical plans are untouched.

# Implementation Summary

## Implemented

- Renamed and restructured the query layer:
  - `InventoryValuation` → `InventoryValueQuery` with `ValueSnapshot`,
    `ValueDelta`, `ValueHistory`, `ValueHistory::Point`, `InventoryValue`;
  - `InventoryCatalogQuery` → `InventoryListQuery` with
    `InventorySummaries` / `InventorySummary`;
  - `InventoryDetailQuery::Page` → `InventoryDetails` + `InventoryItems`;
  - `ItemCatalogQuery` → `ItemListQuery` with `ItemCatalog` +
    `PriceChangeStats`;
  - `ItemPriceHistoryQuery::Page` → `ItemPriceHistory` with `PricePoint`.
- Added `InventoryValueQuery.with_aggregates(scope)` and
  `snapshot_from(record)`; made aggregate SQL constants private; removed the
  positional `AGGREGATE_COLUMNS` concatenation from the list query.
- Moved baseline/delta logic into `InventoryValueQuery#delta_for`; catalog,
  detail, V1 history, and the recording service now share it.
- `InventoryValueQuery.call(steam_id, range)` is the concern's primary
  report entry; `InventoryValueHistoryQuery` delegates to it.
- Added `RarityBreakdownQuery.call(user_inventory_ids)` and removed duplicated
  rarity counting from the list/detail queries.
- Added shared serializers/calculations:
  `ItemMetadataSerializer`, `PriceChangePercent`,
  `RarityBreakdownSerializer`, `ItemPriceHistorySerializer`.
- Renamed serializers/caches:
  `InventoryListSerializer`, `ItemListSerializer`,
  `InventoryValueSerializer`, `InventoryListCache`, `ItemListCache`.
- Updated public/V1/admin controllers, `InventoryValueRecordingService`, and
  living docs/ADR references.
- Preserved JSON contracts and cache payload shapes; `PriceHistoryCache` and
  `ItemTrendCache` were left unchanged.

## Tests

- Renamed query/serializer/cache specs to mirror the new files.
- Updated query specs for content-named results and `Time` timestamps.
- Updated serializer specs for the new structs and shared helpers.
- Added unit specs:
  - `spec/queries/rarity_breakdown_spec.rb`
  - `spec/serializers/item_metadata_serializer_spec.rb`
  - `spec/serializers/price_change_percent_spec.rb`
  - `spec/serializers/rarity_breakdown_serializer_spec.rb`
  - `spec/serializers/item_price_history_serializer_spec.rb`
- Request specs changed only where query class stubs were renamed; expected
  JSON remained unchanged.

Commands executed in the `app_fetcher` container:

- `bundle exec rspec`
- `bundle exec srb tc`
- `bundle exec rubocop`

## Verification

- `bundle exec rspec` — 487 examples, 0 failures.
- `bundle exec srb tc` — no errors.
- `bundle exec rubocop` — 176 files inspected, no offenses.
- Request specs for public items/inventories, V1 inventory values/item prices,
  and admin item cache warming all passed with unchanged response contracts.

## Deviations

- `ItemListQuery::ItemCatalog` keeps the content-based `ItemCatalog` name even
  though the query/serializer/cache are named `ItemList*`.
- `RarityBreakdownQuery` returns typed hashes for lookups/counts rather than a
  `T::Struct`, matching the updated styleguide rule for typed count maps.
- `AGGREGATE_EXPRESSIONS` was retained as the single private source used by
  both `snapshot_for` and `AGGREGATE_SELECTS`, rather than removed.
- `InventoryValueQuery::InventoryValue#snapshot` remains nilable for the V1
  unknown-inventory contract; detail serialization uses `T.must` because the
  detail query already raises on a missing inventory.
- `ItemListCache` was renamed alongside `ItemListQuery`; the admin route and
  method name `warm_catalog_cache` were intentionally left unchanged.
- `PriceHistoryCache` / `ItemTrendCache` remain hash-based; the history
  serializer covers only the non-cache query branch.

## Remaining Issues

- `PriceHistoryCache` / `ItemTrendCache` still order by `created_at` without
  an id tie-breaker; this was explicitly out of scope.
- `InventoryValueQuery#snapshot_for` uses `T.unsafe` around the dynamically
  sized aggregate expression splat, required by Sorbet; behavior is covered by
  query specs.
- Historical plan files under `agent/plans/` were not rewritten, by design.
- `app_fetcher/bin/ci` remains broken per `agent/styleguides/fix_me.md`;
  individual checks were run instead.
