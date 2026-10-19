# Queries / Serializers Polish — Research Report

> Research only. Not a development plan. Implementation starts after
> `create-dev-plan` + `styleguides-check`.
>
> Implemented follow-up: the final API uses `InventoryValueQuery.call` and
> `RarityBreakdownQuery.call`; see `agent/plans/queries-serializers-polish.md`.

## Task Understanding

Привести `app_fetcher`'s query/serializer layer к единому, более явному
виду:

- result-структуры называть по содержимому, а не по форме
  (`Page`/`Listing`/`Detail` → `InventoryValue`, `InventorySummaries`,
  `InventoryDetails`, `InventoryItems`, `ItemCatalog`, `ItemPriceHistory`);
- concern `InventoryValuation` переименовать в `InventoryValueQuery` и
  разложить на `ValueSnapshot` / `ValueDelta` / `ValueHistory` /
  `InventoryValue`;
- убрать публичную SQL-проекцию `AGGREGATE_COLUMNS` из catalog-запроса,
  спрятать её за API concern-а;
- убрать дублирование `HistoryPoint`, `complete`, `change_24h_percent`,
  `metadata`, `rarity_breakdown`, rarity counting;
- оставить JSON-контракты без изменений;
- включить в тот же полишинг `ItemCatalogQuery`, `ItemPriceHistoryQuery`
  и shared serializers;
- `InventoryCatalogSerializer` / `InventoryCatalogCache` переименовать
  вместе с query;
- `PriceHistoryCache` / `ItemTrendCache` не трогать: кэш остаётся
  hash-форматом, `ItemPriceHistorySerializer` покрывает только query-ветку.

## Relevant Files

### Queries

| Путь | Роль | Почему важно |
|---|---|---|
| `app_fetcher/app/queries/inventory_valuation.rb` | concern query: snapshot, history, baseline, SQL-агрегаты | переименование + основной объём рефакторинга |
| `app_fetcher/app/queries/inventory_catalog_query.rb` | список инвентарей | `AGGREGATE_COLUMNS`, positional row mapping, `InventorySummary` |
| `app_fetcher/app/queries/inventory_detail_query.rb` | detail одного инвентаря | giant `Page`, дублирует `Snapshot`/`Series`/`Point` |
| `app_fetcher/app/queries/inventory_value_history_query.rb` | V1 history adapter | вызывает `InventoryValuation.page`, результат `Page` |
| `app_fetcher/app/queries/item_catalog_query.rb` | каталог items | `Page`, `PriceStats`, `last_synced_at` String |
| `app_fetcher/app/queries/item_price_history_query.rb` | история цены item | `Page`, `Point#at` String, inline-map в контроллере |
| `app_fetcher/app/queries/appliers/*` | pagination/sort/filter | менять не планируем, кроме зависимости от aliases |
| `app_fetcher/app/queries/options/*` | enum-параметры | менять не планируем |

### Serializers

| Путь | Роль |
|---|---|
| `app_fetcher/app/serializers/inventory_catalog_serializer.rb` | список инвентарей; переименовать в `InventoryListSerializer` |
| `app_fetcher/app/serializers/inventory_detail_serializer.rb` | detail; input станет `InventoryDetails` |
| `app_fetcher/app/serializers/inventory_valuation_serializer.rb` | V1 values; переименовать в `InventoryValueSerializer` |
| `app_fetcher/app/serializers/item_catalog_serializer.rb` | items catalog; input станет `ItemCatalog` |
| `app_fetcher/app/serializers/item_price_dynamics_serializer.rb` | V1 dynamics; shared percent helper |
| `app_fetcher/app/serializers/inventory_serializer.rb` | V1 inventories/me; не меняется |
| новый `item_price_history_serializer.rb` | убрать inline-map из `ItemPricesController#history` |
| новый shared metadata/percent/rarity serializer | убрать дублирование между catalog/detail |

### Controllers / call sites

| Путь | Роль |
|---|---|
| `app_fetcher/app/controllers/api/public/items_controller.rb` | `ItemCatalogQuery` → `ItemCatalogSerializer` → cache/ETag |
| `app_fetcher/app/controllers/api/public/inventories_controller.rb` | list/detail query + `InventoryCatalogCache`/`InventoryDetailCache` |
| `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb` | `InventoryValueHistoryQuery` + `InventoryValuationSerializer` |
| `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` | `ItemPriceHistoryQuery` + inline point mapping |
| `app_fetcher/app/controllers/api/admin/items_controller.rb` | `warm_catalog_cache` использует `ItemCatalogQuery`/Serializer |

### Caches / models / services

| Путь | Роль |
|---|---|
| `app_fetcher/app/caching/inventory_catalog_cache.rb` | переименовать в `InventoryListCache`, обновить namespace/key version |
| `app_fetcher/app/caching/inventory_detail_cache.rb` | не меняется |
| `app_fetcher/app/caching/item_catalog_cache.rb` | не меняется |
| `app_fetcher/app/caching/price_history_cache.rb` | не меняется (hash payload, 30d branch) |
| `app_fetcher/app/caching/item_trend_cache.rb` | не меняется |
| `app_fetcher/app/models/item.rb` | scopes/metadata accessors, `marketable` |
| `app_fetcher/app/models/user_inventory.rb` | `items`, `steam_id`, `updated_at` |
| `app_fetcher/app/models/inventory_value_log.rb` | `complete?`, legacy nil counts |
| `app_fetcher/app/models/price_log.rb` | `created_at`, `lowest_price_cents`, `volume` |
| `app_fetcher/app/models/rarity_tier.rb` | `for_item`, star/Extraordinary/Contraband semantics |
| `app_fetcher/app/services/inventory_value_recording_service.rb` | вызывает `InventoryValuation.current`/`Snapshot` |

## Current Architecture

- Query objects возвращают `T::Struct`; serializers — чистые функции без I/O;
  контроллеры владеют cache read/write и `stale?`/ETag.
- `InventoryValueQuery` (сейчас `InventoryValuation`) — shared concern query:
  текущий snapshot, history series, baseline, SQL-выражения.
- `InventoryListQuery` (сейчас `InventoryCatalogQuery`) — endpoint query:
  группирует `UserInventory`, сортирует по aggregate aliases, применяет
  pagination, добирает rarity counts и baselines.
- `InventoryDetailQuery` — detail query: `find_by!`, текущий valuation,
  history, top items, priciest item, rarity, trends.
- `ItemCatalogQuery` / `ItemPriceHistoryQuery` — более простые endpoint queries.
- `Appliers::*` — resource-agnostic pagination/sort/filter.
- `Options::*` — closed-enum params.

## Current Flow

### Public items

```text
ItemsController#index
→ ItemCatalogCache.read(params) (TTL-only)
→ on miss: ItemCatalogQuery.call(params)
   → Item.marketable
   → Appliers::FilterApplier
   → COUNT/price stats pluck
   → Appliers::SortApplier
   → Appliers::Pagination
   → ItemTrendCache.fetch_for(page items)
→ ItemCatalogSerializer.call(page)
→ ItemCatalogCache.write
→ stale?(etag: payload[:meta][:last_synced_at])
```

### Public inventories list

```text
InventoriesController#index
→ InventoryCatalogCache.read(params)
→ on miss: InventoryCatalogQuery.call(params)
   → Pagination(24)
   → UserInventory.left_joins(...).group(...)
   → SortApplier(Options::InventorySortOption)
   → pluck(ids/steam_id/updated_at + InventoryValuation::AGGREGATE_COLUMNS)
   → rarity counts by inventory
   → InventoryValuation.baseline_for
→ InventoryCatalogSerializer.call(page)
→ InventoryCatalogCache.write
→ stale?(etag: payload)
```

### Public inventory detail

```text
InventoriesController#show
→ InventoryDetailCache.read(steam_id, params)
→ on miss: InventoryDetailQuery.call(steam_id, params)
   → UserInventory.find_by!
   → DateRange::Param
   → InventoryValuation.current
   → InventoryValuation.series
   → top items sort + pagination
   → priciest item
   → rarity counts
   → ItemTrendCache
→ InventoryDetailSerializer.call(page)
→ InventoryDetailCache.write
→ stale?(etag: payload)
```

### V1 inventory values

```text
InventoryValuesController#index
→ InventoryValueHistoryQuery.call(current_steam_id, params)
   → DateRange::Param (7d/30d/1y/all, default all)
   → InventoryValuation.page(steam_id, range)
      → UserInventory.find_by
      → current snapshot (or nil)
      → series
→ InventoryValuationSerializer.call(page)
```

### V1 item price history

```text
ItemPricesController#history
→ Item.find_by!(market_hash_name)
→ if period == "30d": PriceHistoryCache.fetch_for([name])[name]  (hash points)
→ else: ItemPriceHistoryQuery.call(item, params).points.map { ... }  (inline)
→ render json: points
```

### Worker recording

```text
InventoryValueUpdateWorker
→ InventoryValueRecordingService.call(steam_id)
   → UserInventory.find_by
   → InventoryValuation.current(user_inventory)
   → skip if bootstrap/unpriced
   → upsert InventoryValueLog
```

### Admin warm catalog

```text
Api::Admin::ItemsController#warm_catalog_cache
→ ItemCatalogQuery.call(params)
→ ItemCatalogSerializer.call(page)
→ ItemCatalogCache.write(params, payload)
```

## Existing Patterns

- Query object returns typed `T::Struct`; no `Result` wrapper for sort/period
  errors — they raise namespace errors; missing resource raises
  `ActiveRecord::RecordNotFound`.
- Serializer only maps already-resolved data; no DB/cache access.
- Controller owns response-payload cache and conditional GET.
- `Options::*` enums own param behavior; `Appliers::*` are resource-agnostic.
- `InventoryValuation` is a concern query because its result is consumed by
  multiple queries/controllers/services.
- Cache variants: TTL-only (`ItemCatalogCache`, `InventoryCatalogCache`,
  `InventoryDetailCache`) vs bulk read-through (`ItemPriceCache`,
  `PriceHistoryCache`, `ItemTrendCache`) vs single-key read-through
  (`UserInventoryCache`).
- Specs: query/applier/option/serializer unit specs under `spec/queries/` and
  `spec/serializers/`; request specs cover JSON contracts and cache/ETag.

## Existing Tests

### Query specs

- `spec/queries/inventory_catalog_query_spec.rb` — aggregation, zero-item
  inventory, partial/stale baseline, rarity counts, sort, pagination.
- `spec/queries/inventory_detail_query_spec.rb` — 404, zero items, priciest
  item, avg, rarity, live value, completeness, period/history/change, top
  items, trends.
- `spec/queries/inventory_valuation_spec.rb` — `.current`, `.series`,
  `.baseline_for`, `.page`, unknown steam_id.
- `spec/queries/inventory_value_history_query_spec.rb` — default all,
  period filtering, unknown steam_id, rejected 24h/unknown.
- `spec/queries/item_catalog_query_spec.rb` — marketable scope, filters,
  pagination, counts/stats, trends, `last_synced_at`, invalid sort.
- `spec/queries/item_price_history_query_spec.rb` — default 30d, cutoffs,
  24h, 1y, all, invalid period.

### Serializer specs

- `item_catalog_serializer_spec.rb` — meta keys, item contract, percent,
  trend reshape, nil price.
- `inventory_catalog_serializer_spec.rb` — meta, 13 inventory keys, percent,
  complete, rarity breakdown.
- `inventory_detail_serializer_spec.rb` — top-level keys, portfolio keys,
  priciest item, rarity, top-items meta/entries.
- `inventory_valuation_serializer_spec.rb` — current/history/change shape,
  nil current, empty history, nil oldest price.
- `item_price_dynamics_serializer_spec.rb` — priced/unpriced, percent,
  nil change, empty input.
- `inventory_serializer_spec.rb` — V1 inventories/me; unaffected.

### Request specs (contracts must not change)

- `spec/requests/api/public/items_spec.rb` — 7 metadata keys, trend shape,
  filters, sort, pagination, stats, `last_synced_at` global, cache hit,
  ETag, internal error.
- `spec/requests/api/public/inventories_spec.rb` — list 13 keys, rarity
  tiers, change/complete, sort, pagination, cache, ETag; detail top-level
  keys, portfolio 12 keys, period, top_items, cache, ETag, 404.
- `spec/requests/api/v1/inventory_values_spec.rb` — current/history/change,
  no-log cases, nil inventory, period filtering, errors.
- `spec/requests/api/v1/item_prices_spec.rb` — dynamics/trend/history,
  30d cache path, no DB hit, periods, empty array.
- `spec/requests/api/admin/items_spec.rb` — warm_catalog_cache warms default
  entry.

### Cache specs

- `inventory_catalog_cache_spec.rb` — rename/update.
- `inventory_detail_cache_spec.rb`, `item_catalog_cache_spec.rb`,
  `price_history_cache_spec.rb`, `item_trend_cache_spec.rb` — unchanged.

## Constraints and Risks

### Hard constraints

- JSON response shapes and key names must stay identical; request specs are
  the contract. This includes:
  - public items: 7 metadata keys, `trend_7d` at/price_cents;
  - public inventories list: 13 inventory keys, `change_basis_at` date-only
    (`YYYY-MM-DD`), `rarity_breakdown` 7 tiers;
  - public detail: `portfolio` 12 keys, `change_basis_at` timestamp,
    `top_items` meta/entries;
  - V1 values: `current`/`history`/`change`, `basis_at` timestamp;
  - V1 item history: bare array of `{ at, price_cents, volume }`;
  - admin warm cache response unchanged.
- `PriceHistoryCache` / `ItemTrendCache` payloads stay hash-based; no shared
  `PricePoint` refactor.
- `ItemCatalogQuery#last_synced_at` remains global (`Item.marketable.
  maximum(:updated_at)`), not filtered.
- `InventoryValueHistoryQuery` unknown `steam_id` remains `nil` current +
  empty history.
- `Options::InventorySortOption` orders by `total_value_cents`/`items_count`
  aliases; any aggregate API must keep them in `SELECT`.
- Historical plans in `agent/plans/` are records, not living docs; don't
  rewrite them. Living docs to update: `list-query-objects.md`,
  `architecture-layers.md`, `services.md`, `admin-api-controllers.md`,
  `list-query-objects-layer.md`, `cross-scenario-service-layer.md`,
  `US/dashboard-user-story.md`.

### Sorbet / type risks

- AR timestamps are `ActiveSupport::TimeWithZone`; if query structs use
  `Time`, normalize explicitly (`.to_time.utc`) and verify exact `iso8601`
  output.
- `InventoryValuation::Point#at` / `Series#change_basis_at` are currently
  strings; changing to `Time` requires serializer `.iso8601` and spec updates.
- `InventoryValueQuery::InventoryValue#snapshot` is nilable for the V1
  unknown-inventory case; `InventoryDetailQuery` always finds an inventory,
  so its serializer will need `T.must` or a non-nil variant.
- `snapshot_from(record)` reading aliased attributes via `read_attribute`
  returns `T.untyped`; verify aliases exist and normalize `oldest_price_at`.
- `private_constant` on `AGGREGATE_EXPRESSIONS`/`AGGREGATE_SELECTS` + Sorbet:
  verify `srb tc`.
- `T::Struct` nested `ValueHistory::Point` and `ItemPriceHistoryQuery::
  PricePoint` need consistent `Time` types.

### Query/SQL risks

- `with_aggregates(scope)` appended via `select` must preserve aliases used by
  `Options::InventorySortOption`; verify Rails `select` appends and generated
  SQL works with `GROUP BY user_inventories.id`.
- `snapshot_from` must not be called on a scope without aggregate select;
  document/guard.
- `InventoryListQuery` still runs aggregate query + rarity query + baseline
  query + total count; no N+1 regression.
- `RarityBreakdown` shared query should keep `RarityTier.for_item` semantics
  (`★`, Extraordinary/Contraband → Gold) and the per-inventory grouping.
- `PriceHistoryCache` still uses `.order(:created_at)` without id tie-breaker;
  query will add `, :id`, so equal-timestamp order can differ between cache
  and query branches. Out of scope unless requested.
- `ItemPriceHistoryQuery` `range` is unused by the current bare-array response;
  serializer likely returns points only.

### Cache risks

- `InventoryListCache` rename: old `InventoryCatalogCache` keys become
  unreachable; 2-minute TTL bounds stale data. If keeping the old namespace,
  bump `CACHE_KEY_VERSION`; if changing namespace, old keys simply expire.
- Cache payload shape is unchanged; no migration/compat layer needed.
- `InventoryDetailCache`/`ItemCatalogCache` unaffected.

### Test impact

- Mechanical updates:
  - query specs: nested `snapshot`/`delta`/`value`/`items`;
  - serializer specs: new input structs, `Time` instead of strings;
  - cache specs: `InventoryListCache` rename;
  - request specs: mostly unchanged; only stub class name in public
    inventories spec.
- New coverage:
  - `ItemPriceHistorySerializer` unit spec;
  - `InventoryValueQuery.delta_for` direct cases (nil/stale/partial baseline);
  - `InventoryValueQuery.with_aggregates` / `snapshot_from`;
  - `RarityBreakdown` shared query;
  - shared metadata/percent/rarity serializers.
- No DB migrations, no schema changes, no app_core changes expected.

## Existing Documentation to Update

Living docs (not historical plans):

- `agent/styleguides/fetcher/list-query-objects.md` — names, `ListQuery`
  variant, result struct names, canonical implementations, concern query name.
- `agent/styleguides/fetcher/architecture-layers.md` — `InventoryValuation`
  references.
- `agent/styleguides/fetcher/services.md` — `InventoryValuation` references.
- `agent/styleguides/fetcher/admin-api-controllers.md` —
  `InventoryCatalogSerializer` references.
- `agent/adr/fetcher/list-query-objects-layer.md` — `InventoryValuation`,
  `Page`, catalog naming.
- `agent/adr/fetcher/cross-scenario-service-layer.md` —
  `InventoryValuation` reference.
- `agent/US/dashboard-user-story.md` — `InventoryValuation` reference.

## Open Questions

1. `AGGREGATE_COLUMNS`: `with_aggregates(scope)` vs
   `snapshots_for(ids)` — final choice depends on sort alias/SQL behavior.
2. Exact `InventoryValueQuery` method signatures:
   `.snapshot_for`, `.history`, `.report`, `.delta_for` vs alternatives.
3. `InventoryValueQuery::InventoryValue#snapshot` nilable for detail:
   use `T.must` in serializer or introduce a non-nil detail value.
4. `ItemPriceHistorySerializer` returns bare array (current API) or
   `{ range:, points: }` — request contract points to bare array.
5. Shared serializer helper shape: `ItemMetadataSerializer` +
   `PriceChangePercent` + `RarityBreakdownSerializer`, or one item-entry
   serializer with options.
6. Whether to add id tie-breakers to `PriceHistoryCache`/`ItemTrendCache`
   for ordering parity (currently out of scope).
7. Whether `ItemCatalogQuery` should also become `ItemListQuery` for naming
   consistency, or stay `CatalogQuery` because it is a genuine catalog.
