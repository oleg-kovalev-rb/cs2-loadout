---
status: implemented
app: fetcher+core
goal: Unify portfolio/inventory valuation on one live last-known-price source, keep InventoryValueLog as a completeness-annotated history series, and align 24h change semantics across dashboard, catalog, and detail
created: 2026-10-18
---

# Development Plan

## Goal

Make "what this inventory is worth right now" a single server-side
computation over the latest known price of each item, used identically by
the dashboard hero, the public inventories catalog, and the public
inventory detail page. `InventoryValueLog` stops being the source of the
current number and becomes a daily, completeness-annotated history series.

The change also separates two states that are currently conflated:

- **stale price** — a price exists but was not refreshed for a while; it
  still counts at its last known value and is not "partial";
- **never priced** — no price has ever been recorded for a pricable item;
  the inventory value is a lower bound and is marked partial.

Finally, 24h change at the inventory/portfolio level is derived from the
value series (so a day without price updates cannot fabricate a wrong
delta), while per-item 24h change keeps its existing "as of last
successful fetch" meaning and gains an explicit freshness timestamp.

## Research Summary

Current behavior (verified in code):

| Surface | Current value source | Change source |
|---|---|---|
| Dashboard hero (`/`) | `InventoryValueLog` via `usePortfolioHistory` → `/api/v1/inventory_values`; client-side partial sum only while "estimating" | last minus first series point |
| Inventory detail hero (`/inventories/:id`) | `InventoryDetailQuery`: `logs.last&.total_value_cents \|\| live sum` | first/last log in the selected range |
| Inventory detail items / avg / priciest | live `items.current_price_cents` | per-item `items.change_24h_cents` |
| Inventory catalog (`/inventories`) | live `SUM(items.current_price_cents)` | `SUM(items.change_24h_cents)` |

Relevant facts:

- `InventoryValueRecordingService` gates the **entire day** on every
  marketable item having a price. That gate was introduced by
  `agent/plans/portfolio-first-snapshot-race.md` to avoid a `0` first
  snapshot for a brand-new account; it is also applied to nightly
  updates, which creates history gaps and lets the hero stick to an old
  log value.
- `PriceUpdateService` sets `items.current_price_cents` only on a
  successful fetch; failures and `not_found` leave the last known price
  in place. So "use the last known price when there is no fresh log" is
  already the data-layer behavior.
- `PriceUpdateService` computes `change_24h_cents` as the latest price
  minus the latest log at least 24h old (or the oldest log if none). The
  value is only recomputed on a successful fetch; when an item is not
  fetched for a day, the stored delta describes a 24h window ending at
  the last fetch, not "now".
- `UserInventorySyncService` does not write a value log; logs are written
  by the nightly `InventoryValueScheduler` (only for steam_ids that
  already have one) or by the `/api/v1/inventory_values` self-seed.
- `items.updated_at` is not a reliable price timestamp: admin item
  updates touch it too.
- Public caches (`InventoryCatalogCache`, `InventoryDetailCache`) are
  TTL-only, 2 minutes, keyed by request params.

## Expected Behavior

### Current value (all surfaces)

- The current value is the sum of each owned item's latest known
  `current_price_cents`; `nil` contributes `0`.
- The same `steam_id` produces the same value on `/`,
  `/inventories`, and `/inventories/:steam_id`, within the 2-minute
  response-cache TTL of the public endpoints.
- A stale price still counts at its last known value and is **not**
  partial.
- `complete` is true when every *pricable* item (`marketable` and not
  `price_unavailable`) has at least one known price. Non-marketable and
  `price_unavailable` items never block completeness.
- An empty inventory is worth `0` and is complete.
- An inventory whose items are all non-marketable or `price_unavailable`
  is worth `0` (unless a last price exists) and is complete.
- An inventory with at least one pricable item that has never been
  priced is partial: the value is the sum of known prices,
  `complete: false`, with `priced_items_count` / `pricable_items_count`.
- The UI shows the value plus a partial badge (for example
  `38/40 priced`) for incomplete inventories.

### Recording: bootstrap vs steady state

Recording mode is decided by whether the `steam_id` already has any
`InventoryValueLog` row.

**Bootstrap (no rows yet)** — preserve the original intent of the gate:

- no `UserInventory` row → skip, write nothing;
- empty inventory, or no pricable items → write a `0` row (a genuine
  zero);
- pricable items exist, none priced → skip (do not create a `0` point);
- some prices are missing and the inventory is younger than 48 hours →
  skip and wait;
- some prices exist and the inventory is at least 48 hours old → write a
  partial row (`complete: false`) and thereafter behave as steady state.

**Steady state (at least one row exists)**:

- write every day, using the latest known price for every item, even if
  some items are stale or some newly added items are still unpriced;
- skip only when the inventory has items but **no** item has a price at
  all (`priced_items_count == 0 && pricable_items_count > 0`) — that is
  almost certainly a pricing failure, not a real zero;
- an empty inventory still writes `0`.

Every written row stores `items_count`, `pricable_items_count`, and
`priced_items_count`. Legacy rows without these columns are treated as
complete.

### History and change

- `InventoryValueLog` remains daily and one row per `(steam_id,
  log_date)`.
- The history returned by the API is the stored daily series **plus a
  live "now" point** built from the current valuation. If today's log
  row exists, the live point replaces its value so the chart's last
  point always equals the hero value.
- Portfolio/inventory change is computed against the first point in the
  selected range (`change_basis_at`); when there are fewer than two
  points, the change is unavailable and the UI hides the delta.
- `change_partial` is true when either the current point or the baseline
  point is incomplete. The UI hides the delta in that case and relies on
  the partial badge.
- Catalog cards show a 24h change derived from the daily series: current
  value minus the latest log on or before yesterday. If that baseline is
  missing or older than two days, the delta is unavailable (hidden)
  rather than shown as a misleading "24h" number.
- The change payload carries `change_basis_at` so the UI can show the
  real comparison date where useful.
- Per-item 24h change keeps its stored value and gains
  `price_updated_at`. A price older than 24h is still displayed at its
  last known value with its last computed 24h delta, marked stale; it is
  never zeroed or turned into a fake "no change".

### API contracts

`GET /api/v1/inventory_values` changes from a bare array to:

```json
{
  "current": {
    "total_value_cents": 0,
    "items_count": 0,
    "pricable_items_count": 0,
    "priced_items_count": 0,
    "complete": true,
    "oldest_price_at": "2026-10-18T09:00:00Z"
  },
  "history": [
    {
      "at": "2026-10-18T00:00:00Z",
      "total_value_cents": 0,
      "complete": true,
      "priced_items_count": 0,
      "pricable_items_count": 0
    }
  ],
  "change": {
    "cents": 0,
    "percent": 0.0,
    "basis_at": null,
    "partial": false,
    "available": false
  }
}
```

When no `UserInventory` exists yet, `current` is `null`, `history` is
empty, and `change.available` is false.

`GET /api/public/inventories` cards gain
`priced_items_count`, `pricable_items_count`, `complete`,
`change_basis_at`, `change_partial`, and `change_available`.

`GET /api/public/inventories/:steam_id` adds the same completeness/change
metadata under `portfolio`, and `price_updated_at` to `priciest_item`
and every `top_items` entry.

`GET /api/v1/item_prices/dynamics` adds `price_updated_at` per item.

### Must remain unchanged

- `PriceUpdateService`'s per-item baseline rule (latest log at least 24h
  old, otherwise the oldest log) and its transaction boundary.
- `price_unavailable` behavior: a failed `not_found` fetch keeps the last
  known price and marks the item unavailable; it is excluded from the
  completeness denominator.
- Public API auth/namespace, sort/pagination contracts, conditional GET,
  and the 2-minute response caches (versions are bumped).
- Existing admin API shapes; new columns are not exposed there in this
  change.
- The behavior of `PriceScheduler` and the price warmup/dedup path.

## Scope

### In Scope

- `app_fetcher` migrations for `items.price_updated_at` and completeness
  counters on `inventory_value_logs`.
- One shared valuation calculation used by the recording service, the
  catalog query, the detail query, and the V1 values endpoint.
- Bootstrap/steady-state recording modes and the scheduler fan-out to
  every known `UserInventory`.
- Series-based change for catalog/detail/dashboard; per-item freshness
  metadata and stale marking.
- Updated public and internal JSON payloads and their consumers.
- Frontend completeness badges, delta suppression for partial values,
  stale-price marking, and removal of the now-duplicated client-side
  "fully priced / partial sum" helpers.
- Unit/request/component tests for all of the above.

### Out of Scope

- Price-only portfolio change (constant item set). This plan uses
  portfolio value change, which includes composition changes.
- Intraday price snapshots or true intraday 24h portfolio resolution;
  `InventoryValueLog` stays daily.
- Backfilling or repairing historical log rows beyond the one-time
  `price_updated_at` backfill (legacy nil counts are treated as complete).
- Admin UI changes for the new fields.
- Rate limiting, `WARMUP_CAP`, or Steam budget changes.
- Recomputing per-item 24h change on read.
- A manual-refresh button or any new endpoint triggering a sync.
- Non-marketable item valuation (they remain `0` unless a price already
  exists).

## Implementation Approach

### 1. Data model

**Migration: `AddPriceUpdatedAtToItems`**

- Add `items.price_updated_at` (datetime, nullable).
- Backfill `price_updated_at = updated_at` for every item with a
  non-null `current_price_cents` (best available approximation for
  pre-existing data).
- No index is required: the column is read through inventory-scoped
  joins, not looked up directly.

**Migration: `AddCompletenessToInventoryValueLogs`**

- Add nullable integer columns `items_count`,
  `pricable_items_count`, `priced_items_count`.
- Null means "written before this change"; such rows are treated as
  complete.

**`Item`**

- No new scopes are required; the valuation query owns its SQL
  aggregate expressions. The new column is an ordinary attribute.
- Regenerate `sorbet/rbi/dsl/item.rbi`.

**`InventoryValueLog`**

- Validate the three counters as non-negative integers when present.
- Add `complete?`: true when counts are absent (legacy) or
  `priced_items_count >= pricable_items_count`.
- Regenerate `sorbet/rbi/dsl/inventory_value_log.rbi`.

**Factories**

- `item`: default `price_updated_at { Time.current }`;
  `:without_price` also sets it to `nil`; add `:stale_price` (for
  example `2.days.ago`).
- `inventory_value_log`: keep counts nil by default (legacy shape); add
  `:partial` and `:complete` traits that set the three counters.

### 2. `InventoryValuation` (new shared read-only valuation query)

Add `app_fetcher/app/queries/inventory_valuation.rb`. It is a read-only
query object, not a service: it computes data and returns structs, takes
no HTTP params, and has no side effects.

Responsibilities:

- expose the SQL aggregate expressions for "current value" in one place
  so the single-inventory and catalog paths cannot drift;
- return a `Snapshot` (`total_value_cents`, `items_count`,
  `pricable_items_count`, `priced_items_count`, `oldest_price_at`) with
  `complete?`;
- build a `Series` for a `steam_id` + `PricePeriod`: stored log points in
  range, a live "now" point from the current snapshot, and the computed
  change (`cents`, `percent`, `basis_at`, `partial`, `available`);
- provide a `Page` for the internal values endpoint: the current
  snapshot plus the series in one call, so
  `Api::V1::InventoryValuesController#index` stays a single-collaborator
  action (apart from the already-sanctioned self-seed);
- provide a bulk `baseline_for(steam_ids, since_date)` lookup for the
  catalog (latest log on or before the date, one query for the page).

Aggregate definitions (expressed once, reused):

- `items_count`: `COUNT(items.id)` (not `COUNT(*)`, because the catalog
  uses a left join and a zero-item inventory must produce `0`);
- `pricable_items_count`: the same count filtered by
  `items.metadata @> '{"marketable": true}'::jsonb AND
  items.price_unavailable = FALSE`;
- `priced_items_count`: the pricable count additionally filtered by
  `items.current_price_cents IS NOT NULL`;
- `total_value_cents`: `COALESCE(SUM(items.current_price_cents), 0)`;
- `oldest_price_at`: `MIN(items.price_updated_at)` over priced pricable
  items, converted to a `Time`.

The single-inventory path uses `user_inventory.items.pick(...)`; the
catalog path uses the same expressions as aliased `pluck` columns inside
its existing grouped query. The catalog keeps sorting by the
`total_value_cents` / `items_count` aliases.

### 3. Recording service modes

`InventoryValueRecordingService.call(steam_id)`:

1. Find `UserInventory`; skip when absent.
2. Compute `InventoryValuation.current`.
3. Determine `bootstrapping` (no log rows for this `steam_id`).
4. Compute `pending = pricable_items_count - priced_items_count`.
5. Skip when:
   - `pricable_items_count > 0 && priced_items_count == 0` (nothing to
     value), or
   - `bootstrapping && pending > 0 && user_inventory.created_at >
     48.hours.ago` (waiting for the first prices).
6. Otherwise upsert today's row with the total and the three counters,
   and return `Ok` with the log. Skipped paths return `Skipped`.

Constants (typed with `T.let`): `BOOTSTRAP_MAX_WAIT = 48.hours`.

Multiple calls on the same day keep the existing upsert semantics
(`unique_by: [:steam_id, :log_date]`); a partial row can be replaced by a
later complete row on the same day if the service is called again.

### 4. Scheduler

`InventoryValueScheduler` fan-out changes from "steam_ids that already
have a log row" to **every** `UserInventory` (walked in batches), so

- users who never open the dashboard get a daily history point;
- the catalog's 24h baseline exists for every synced inventory after the
  first nightly run;
- new users still obey the bootstrap gate inside the service.

Add the missing explicit `retry: 3` while touching the file (and remove
the corresponding `fix_me.md` entry, per that file's process).

### 5. Catalog

`InventoryCatalogQuery`:

- replace the ad-hoc aggregate list with `InventoryValuation`'s
  expressions plus `user_inventories` fields;
- extend `InventorySummary` with `priced_items_count`,
  `pricable_items_count`, `oldest_price_at`, `change_basis_at`,
  `change_partial`, `change_available`;
- after pagination, bulk-load the 24h baselines for the page's
  `steam_id`s (one query), then compute the card change:
  `current_total - baseline_total`;
- `change_available` is false when there is no baseline or the baseline
  is older than two days; `change_partial` is true when either side is
  incomplete.

`InventoryCatalogSerializer`:

- emit `priced_items_count`, `pricable_items_count`, `complete`,
  `change_basis_at`, `change_partial`, `change_available`;
- keep `change_24h_percent` derived from `total_value_cents` and the
  change, defaulting to `0.0` when unavailable.

### 6. Detail

`InventoryDetailQuery`:

- get `items_count` and `total_value_cents` from
  `InventoryValuation.current` (no `logs.last` for the current number);
- compute `avg_item_value_cents` from the live total and live item
  count;
- build the history and change through
  `InventoryValuation.series(steam_id, range, current:)`;
- carry `complete`, counts, `oldest_price_at`, `change_basis_at`,
  `change_partial`, `change_available` on the `Page`;
- keep `priciest_item`, rarity counts, top items, and trends unchanged
  (they are already live).

`InventoryDetailSerializer`:

- add the completeness/change fields under `portfolio`;
- add `price_updated_at` to `priciest_item` and every `top_items` entry.

### 7. Internal values endpoint and dashboard

`Api::V1::InventoryValuesController#index`:

- keep the period validation and the existing self-seed (only when the
  `steam_id` has zero log rows);
- after the self-seed, make one `InventoryValuation.page(steam_id,
  period)` call for the response payload, preserving the guide's
  one-collaborator rule (the self-seed is the already-sanctioned
  exception);
- the page includes the current snapshot even when no log row was
  written, so a partial inventory can be rendered immediately;
- return `{ current, history, change }` as described above, with the
  live point appended/replacing today's log;
- when no `UserInventory` exists, return `current: null` and empty
  history rather than erroring.

`app_core` dashboard:

- `usePortfolioHistory` consumes the new object shape, returns
  `{ series, current, change, status }`, and retries on the same bounded
  schedule as `useItemPrices` while `current` is missing or incomplete;
- `Dashboard.jsx` stops deriving `isFullyPriced` / `pricedTotalCents`
  from items. It passes `current`, `change`, and the estimating flag
  from the hook. `marketableNames` (not all names) feed `useItemPrices`
  so its coverage retry ignores non-marketable items;
- `PortfolioTile` uses the live current value and the backend change;
  it shows the value plus the partial badge/Estimating caption and
  suppresses the delta when incomplete or `change.partial`;
- delete `dashboard/utils/valuation.js` and its test — the rule now
  lives on the server;
- move the shared retry schedule to `shared/utils/retrySchedule.js` and
  use it from both `useItemPrices` and `usePortfolioHistory`.

### 8. Per-item freshness

- `PriceUpdateService` writes `price_updated_at: Time.current` in the
  same transaction as the price log and item price update.
- `Api::V1::ItemPricesController#dynamics` includes
  `price_updated_at` for every returned item.
- `InventoryDetailSerializer` includes it for priciest/top items.
- Frontend maps it to `priceUpdatedAt` (milliseconds) and adds a shared
  `shared/utils/priceFreshness.js` with a 24h threshold and a human
  age label.
- `ItemRow` and `InventoryItemRow` mark a stale price (muted/`is-stale`
  styling and a `title`/caption with the last update time) while still
  rendering the last price and its last computed delta.
- Bump `ItemPriceCache` and `UserInventoryCache` key versions because
  cached `Item` objects change shape.

### 9. Cache versions

Bump `CACHE_KEY_VERSION` for every cached payload whose shape changes:

- `ItemPriceCache` (cached `Item` now has `price_updated_at`),
- `UserInventoryCache` (same reason),
- `InventoryCatalogCache` (new card keys),
- `InventoryDetailCache` (new portfolio/item keys).

No change to TTLs.

### 10. Sorbet and RBI

- New query, constants, structs, and predicates use `# typed: strict`,
  `extend T::Sig`, and `sig`s.
- Wrap constants in `T.let`.
- Regenerate model DSL RBIs with
  `bin/tapioca dsl Item InventoryValueLog` and commit the output.

### 11. Styleguides amended during `styleguides-check`

- `agent/styleguides/fetcher/list-query-objects.md` — document the
  shared, non-endpoint-specific valuation/aggregate query shape
  (`InventoryValuation`), including the page/series helpers and the bulk
  baseline, so a future reader does not mistake it for a rogue query
  object.
- `agent/styleguides/fetcher/services.md` — add read-only
  `app/queries/` objects to the service layer's allowed dependencies
  (`InventoryValueRecordingService` calls `InventoryValuation`).
- `agent/styleguides/core/react-dashboard.md` — extend the hero-delta
  rule: hide the delta when the valuation is incomplete or
  `change_partial`, not only when it is zero; document the partial badge
  and stale-price marker.
- `agent/styleguides/fix_me.md` — remove the
  `inventory_value_scheduler.rb` missing-`retry:` entry once fixed.

## Files To Modify

### `app_fetcher`

- `app/models/inventory_value_log.rb` — counter validations and
  `complete?`.
- `app/services/inventory_value_recording_service.rb` — bootstrap vs
  steady-state modes, counters, 48h timeout.
- `app/schedulers/inventory_value_scheduler.rb` — fan out to all
  `UserInventory`; add `retry: 3`.
- `app/queries/inventory_catalog_query.rb` — shared aggregate columns,
  completeness/change fields, bulk baseline lookup.
- `app/serializers/inventory_catalog_serializer.rb` — new card keys.
- `app/queries/inventory_detail_query.rb` — live total/avg and
  series-based history/change.
- `app/serializers/inventory_detail_serializer.rb` — portfolio
  completeness/change fields and item `price_updated_at`.
- `app/controllers/api/v1/inventory_values_controller.rb` — object
  response with current/history/change and partial-inventory support.
- `app/controllers/api/v1/item_prices_controller.rb` — dynamics
  `price_updated_at`.
- `app/services/price_update_service.rb` — write `price_updated_at`.
- `app/caching/item_price_cache.rb` — bump cache version.
- `app/caching/user_inventory_cache.rb` — bump cache version.
- `app/caching/inventory_catalog_cache.rb` — bump cache version.
- `app/caching/inventory_detail_cache.rb` — bump cache version.
- `db/schema.rb` — generated after the migrations.
- `sorbet/rbi/dsl/item.rbi` — regenerated.
- `sorbet/rbi/dsl/inventory_value_log.rbi` — regenerated.
- `spec/factories/items.rb` — `price_updated_at` default/traits.
- `spec/factories/inventory_value_logs.rb` — counters and traits.
- `spec/queries/inventory_catalog_query_spec.rb` — completeness/change
  expectations and query-count coverage.
- `spec/queries/inventory_detail_query_spec.rb` — live total/avg,
  series, partial change.
- `spec/serializers/inventory_catalog_serializer_spec.rb` — new keys.
- `spec/serializers/inventory_detail_serializer_spec.rb` — new keys and
  item timestamp.
- `spec/requests/api/public/inventories_spec.rb` — contracted keys and
  partial/change behavior.
- `spec/requests/api/v1/inventory_values_spec.rb` — new response shape,
  partial current, self-seed behavior.
- `spec/requests/api/v1/item_prices_spec.rb` — `price_updated_at`.
- `spec/services/inventory_value_recording_service_spec.rb` — bootstrap
  skip/timeout, steady-state partial, zero-priced skip, counters.
- `spec/services/price_update_service_spec.rb` — timestamp write.
- `spec/schedulers/inventory_value_scheduler_spec.rb` — all-inventory
  fan-out.
- `spec/workers/inventory_value_update_worker_spec.rb` — steady-state
  partial behavior.

### `app_core`

- `app/frontend/dashboard/hooks/usePortfolioHistory.js` — new response
  shape, current/change, bounded retry.
- `app/frontend/dashboard/hooks/useItemPrices.js` — `priceUpdatedAt`
  mapping and shared retry schedule.
- `app/frontend/dashboard/Dashboard.jsx` — server-driven valuation,
  marketable names for price coverage.
- `app/frontend/dashboard/components/PortfolioTile.jsx` — partial
  state/badge and delta suppression.
- `app/frontend/dashboard/components/ItemRow.jsx` — stale-price marker.
- `app/frontend/inventories/hooks/useInventoryDetail.js` — map
  completeness/change and item `priceUpdatedAt`.
- `app/frontend/inventories/components/PortfolioHeroTile.jsx` —
  partial badge and delta suppression.
- `app/frontend/inventories/components/InventoryCard.jsx` — partial
  badge, change availability/partial gating, basis tooltip.
- `app/frontend/inventories/components/InventoryItemRow.jsx` —
  stale-price marker.
- `app/frontend/inventories/InventoryDetail.jsx` — pass completeness
  context to the hero/stats where needed.
- `app/frontend/shared/styles/tokens.css` — `.hero-partial`,
  `.inv-partial`, `.is-stale` styles.
- `app/frontend/dashboard/__tests__/usePortfolioHistory.test.js` — new
  shape and retry.
- `app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` — partial
  hero behavior.
- `app/frontend/dashboard/__tests__/useItemPrices.test.js` —
  `priceUpdatedAt` mapping.
- `app/frontend/dashboard/__tests__/ItemRow.test.jsx` — stale marker.
- `app/frontend/inventories/__tests__/useInventoryDetail.test.js` — new
  mapped fields.
- `app/frontend/inventories/__tests__/InventoryDetail.test.jsx` —
  partial hero badge/no delta.
- `app/frontend/inventories/__tests__/InventoryCard.test.jsx` — partial
  badge and delta gating.
- `app/frontend/inventories/__tests__/InventoryItemRow.test.jsx` —
  stale marker.
- `app/frontend/inventories/__tests__/InventoriesIndex.test.jsx` —
  updated page fixtures for the new card fields.

### Documentation

- `agent/styleguides/fix_me.md` — remove the fixed scheduler entry.
- `agent/styleguides/fetcher/list-query-objects.md` — amend in
  `styleguides-check`.
- `agent/styleguides/core/react-dashboard.md` — amend in
  `styleguides-check`.

## Files To Create

- `app_fetcher/db/migrate/<timestamp>_add_price_updated_at_to_items.rb`
  — new column plus one-time backfill.
- `app_fetcher/db/migrate/<timestamp>_add_completeness_to_inventory_value_logs.rb`
  — nullable counters.
- `app_fetcher/app/queries/inventory_valuation.rb` — shared current
  snapshot, series/change, bulk baseline, SQL aggregate definitions.
- `app_fetcher/spec/queries/inventory_valuation_spec.rb` — exhaustive
  unit coverage for the new query.
- `app_core/app/frontend/shared/utils/priceFreshness.js` — pure 24h
  staleness predicate/age label.
- `app_core/app/frontend/shared/utils/retrySchedule.js` — the bounded
  retry schedule shared by price and portfolio hooks.
- `app_core/app/frontend/shared/__tests__/priceFreshness.test.js` — unit
  tests for the threshold.

Deleted:

- `app_core/app/frontend/dashboard/utils/valuation.js`
- `app_core/app/frontend/dashboard/__tests__/valuation.test.js`

## Test Plan

### Backend

- **`spec/queries/inventory_valuation_spec.rb`** (new, unit):
  - empty inventory → zero counts, `complete?` true, total `0`;
  - all pricable items priced → correct total/complete;
  - one unpriced pricable item → partial, total excludes it;
  - unpriced non-marketable / `price_unavailable` items → complete;
  - priced `price_unavailable` item → its last price is included but it
    does not affect completeness;
  - `oldest_price_at` ignores unpriced and non-pricable items;
  - `complete?` for a legacy log with nil counters;
  - series: logs + live point, today's log value replaced by current,
    fewer than two points → unavailable change, partial endpoints →
    `change_partial`, change basis timestamp;
  - bulk baseline: one row per `steam_id`, latest on/before the date,
    missing ids omitted.
- **`spec/services/inventory_value_recording_service_spec.rb`**:
  - no `UserInventory` → `Skipped`, no row;
  - bootstrap, fully priced → writes a complete row with counters;
  - bootstrap, some prices missing, fresh inventory → `Skipped`;
  - bootstrap, some prices missing, older than 48h with at least one
    price → writes a partial row;
  - bootstrap, non-empty inventory with zero priced items → `Skipped`;
  - steady state, some prices missing → writes a partial row;
  - steady state, non-empty inventory with zero priced items →
    `Skipped`;
  - empty inventory → writes a zero complete row;
  - existing today row → updated in place, no duplicate.
- **`spec/schedulers/inventory_value_scheduler_spec.rb`**:
  - enqueues for inventories with and without existing logs;
  - enqueues once per `steam_id`;
  - no `UserInventory` rows → no jobs.
- **`spec/workers/inventory_value_update_worker_spec.rb`**:
  - steady-state partial inventory writes a row (the old
    "unpriced item → no row" case becomes bootstrap-only);
  - no inventory → no row.
- **`spec/queries/inventory_catalog_query_spec.rb`**:
  - total/items/counters together;
  - zero-item inventory gets zero aggregates via the left join;
  - completeness flags for partial inventories;
  - 24h change from the baseline log; no baseline → unavailable;
  - baseline older than two days → unavailable;
  - baseline incomplete → `change_partial`;
  - one baseline query for the page (no N+1);
  - existing sort/pagination tests stay green.
- **`spec/queries/inventory_detail_query_spec.rb`**:
  - total comes from live prices even when a stored log value differs;
  - avg uses the live total and live item count;
  - history includes the live point;
  - range change and `change_partial` flags;
  - an inventory with no logs still returns a live total and a live
    single-point history;
  - existing top-items/rarity/trend tests stay green.
- **Serializer specs**:
  - catalog contracted keys include the new fields; percent/availability
    behavior;
  - detail portfolio keys include completeness/change fields; item
    entries include `price_updated_at`; existing zero/empty behavior.
- **Request specs**:
  - public inventories: exact key contracts, partial badge data,
    unauthenticated access, 404 unchanged;
  - V1 inventory values: new object shape; period filtering; bootstrap
    skip returns `current` + empty history; self-seed writes one row;
    live point equals current; no `UserInventory` returns null current;
    unsupported period unchanged;
  - V1 item prices dynamics: `price_updated_at` present and nil for a
    never-fetched price (if such an item can be returned; otherwise
    assert the priced case).
- **`spec/services/price_update_service_spec.rb`**: successful fetch sets
  `price_updated_at`; a failed/unavailable path does not clear it (the
  worker's failure path is covered by its own spec).

### Frontend

- **`usePortfolioHistory.test.js`**: maps current/history/change;
  re-fetches when period changes; retries while incomplete, stops when
  complete; retries when `current` is null; error status.
- **`PortfolioTile.test.jsx`**: complete series behavior unchanged;
  partial current with a non-empty series shows the value + badge and
  hides the delta; unavailable change hides the delta; item mode
  unchanged.
- **`useItemPrices.test.js`**: maps `priceUpdatedAt`; existing retry
  behavior unchanged.
- **`ItemRow.test.jsx`**: stale price keeps the price/delta but gains the
  stale class/title; fresh price has no stale marker.
- **`useInventoryDetail.test.js`**: maps completeness/change fields and
  `priceUpdatedAt`; existing not-found/error tests unchanged.
- **`InventoryDetail.test.jsx`**: partial portfolio renders the badge
  and no delta; complete portfolio keeps the existing delta.
- **`InventoryCard.test.jsx`**: partial badge; no delta when
  `changePartial` or `changeAvailable` is false; existing up/down/flat
  cases unchanged when complete.
- **`InventoryItemRow.test.jsx`**: stale marker without hiding the
  price/delta.
- **`InventoriesIndex.test.jsx`**: updated fixtures with the new card
  fields; existing loading/error/enrichment behavior unchanged.
- **`priceFreshness.test.js`**: exactly 24h boundary, stale/fresh, nil.

## Implementation Steps

1. **Data model**: add both migrations, backfill `price_updated_at`,
   update `InventoryValueLog` validations/`complete?` and factories;
   run `bin/tapioca dsl Item InventoryValueLog`.
2. **`InventoryValuation`**: TDD the current snapshot, series/change,
   and bulk baseline against `inventory_valuation_spec.rb`.
3. **Recording service**: TDD the bootstrap/steady-state matrix against
   `inventory_value_recording_service_spec.rb`, then implement; update
   the worker spec.
4. **Scheduler**: switch the fan-out to all `UserInventory`, add
   `retry: 3`, update its spec, remove the `fix_me.md` entry.
5. **Catalog**: rewire the query to the shared aggregate and bulk
   baseline, extend the serializer and specs.
6. **Detail**: rewire the query/serializer to the live valuation and
   series, extend the specs.
7. **V1 values endpoint**: implement the new response shape and
   self-seed/partial-current behavior; update request specs.
8. **Per-item freshness**: write `price_updated_at` in
   `PriceUpdateService`, expose it in dynamics/detail, add the frontend
   helper and stale markers; update specs; bump cache versions.
9. **Dashboard frontend**: rewrite `usePortfolioHistory`, update
   `Dashboard.jsx`/`PortfolioTile`, remove `valuation.js`, move the
   retry schedule to `shared/`, update tests.
10. **Public detail/catalog frontend**: update `useInventoryDetail`,
    `PortfolioHeroTile`, `InventoryCard`, `InventoryItemRow`,
    `InventoryDetail`, styles, and tests.
11. **Full verification**: both RSpec suites, `srb tc`, RuboCop,
    Vitest, ESLint/Prettier; then a manual cross-surface check.

## Verification

- `app_fetcher`:
  - targeted specs for every touched file, then the full RSpec suite;
  - `bundle exec srb tc`;
  - `bin/rubocop` on touched Ruby files;
  - `bin/tapioca dsl Item InventoryValueLog` run and committed.
- `app_core`:
  - targeted Vitest files, then the full `npm test` suite;
  - `RAILS_ENV=test bundle exec rspec`;
  - `npm run lint` and `npm run format:check`.
- Manual, with a seeded local stack:
  - the same `steam_id` shows the same value on `/`, `/inventories`,
    and `/inventories/:steam_id`;
  - an inventory with an unpriced marketable item shows the partial
    value + badge and no delta on all three surfaces;
  - an item whose price is older than 24h shows the last price, its
    last 24h delta, and a stale marker, not `0`;
  - a brand-new account with no logs produces no `0` log while prices
    are missing, and produces a first log once prices arrive;
  - after the nightly scheduler runs, a previously log-less inventory
    gets a baseline and the catalog card shows a 24h delta (or hides it
    when the baseline is too old).

## Risks

- **Breaking the internal `/api/v1/inventory_values` response shape.**
  `app_core` is the only consumer; the hook and its tests are updated in
  the same change. Any missed caller would fail loudly in `npm test` or
  in manual verification.
- **Partial history can still look like a dip in the chart.** Values are
  marked `complete: false`, the UI suppresses the delta, and the badge
  explains the state. The chart itself still plots partial points; if
  this reads badly in manual verification, the follow-up is a distinct
  visual treatment for incomplete points (not part of this plan's
  correctness requirement).
- **Catalog change readability.** A baseline older than two days hides
  the 24h delta. That is deliberate: better an absent delta than a
  mislabeled one. Users with no nightly logs will see no delta until the
  first baseline exists.
- **The 2-minute response caches can still make two surfaces disagree
  briefly** after a price update. That is bounded TTL drift, not a
  different definition of value; cache versions are bumped for shape
  changes, but no cross-cache invalidation is introduced.
- **`price_updated_at` backfill from `updated_at` is approximate** for
  pre-existing rows (admin/metadata edits may have moved `updated_at`).
  New rows are exact; legacy freshness is best-effort.
- **Scheduler fan-out grows to one job per known inventory per night.**
  This is a linear increase in `:default` queue volume; the work is a
  DB-only aggregate + upsert, and the existing `retry: 3` bound applies.
- **`useItemPrices` can still retry for `price_unavailable` marketable
  items** because the frontend does not receive that flag. It stops
  after the existing five attempts; the hero no longer depends on that
  readiness signal, so the impact is limited to row prices.
- **The shared `InventoryValuation` query is a new shape in the
  `app/queries/` layer.** `styleguides-check` must amend
  `list-query-objects.md` (or redirect the placement) before
  implementation.

## Assumptions

- Portfolio-level change means portfolio value change (including
  composition changes from trades), not price-only change. This was the
  recommended option in the preceding design discussion.
- Hiding a delta whose endpoint is partial is acceptable; the value plus
  the partial badge carries the information.
- The 48-hour bootstrap timeout is an acceptable guard against a
  permanently unpriceable item blocking the first snapshot forever.
- Legacy `InventoryValueLog` rows with nil counters were written only
  when the inventory was fully priced under the old gate, so treating
  nil as complete is safe.
- `price_updated_at` tracks successful automated Steam price fetches;
  admin manual price edits do not update it (they are not a market
  fetch).
- The local `app_fetcher` timezone is UTC (no `time_zone` override), so
  `Date.current` matches the 00:00 UTC cron.
- All user-facing copy stays English, consistent with the rest of the
  app.

## Applicable Styleguides

### Shared

- `agent/styleguides/rails-layering.md` — the one-directional
  Controller → orchestration → Models invariant the new
  `InventoryValuation` query, the recording service, and the V1 endpoint
  must stay inside.
- `agent/styleguides/ruby-sorbet.md` — `# typed: strict`, `sig`,
  `T.let` constants, `T::Struct` value objects, and the
  `bin/tapioca dsl Item InventoryValueLog` regeneration workflow.
- `agent/styleguides/rspec-conventions.md` — unit specs for the query /
  service / scheduler / serializers, request specs for the public and
  V1 controllers, FactoryBot data, `aggregate_failures`, and the
  no-mocking-the-DB rule.
- `agent/styleguides/git-commits.md` — the change touches both apps, so
  the commit scope is `[Core+Fetcher]`.
- `agent/styleguides/ci-and-coverage.md`, `agent/styleguides/git-hooks.md`
  — how the verification commands run for both apps.
- `agent/styleguides/fix_me.md` — remove the fixed
  `inventory_value_scheduler.rb` retry entry; check any other touched
  file already listed there.

### `app_fetcher`

- `agent/styleguides/fetcher/services.md` — the recording service
  remains a `ServiceResult`-returning, single-`.call` service; it may
  now depend on a read-only query object but stays the only writer.
- `agent/styleguides/fetcher/list-query-objects.md` — the shared
  concern-query shape (`InventoryValuation`), its callers, the shared
  aggregate SQL, zero-I/O serializers, and the unit-spec expectations.
- `agent/styleguides/fetcher/architecture-layers.md` — the layer map now
  places shared concern queries in `app/queries/` and permits the
  service → query and `Api::V1::` → query edges.
- `agent/styleguides/fetcher/background-jobs.md` — the scheduler's
  query-and-fan-out responsibility and explicit `retry:` requirement;
  the worker remains DB-only.
- `agent/styleguides/fetcher/internal-api-controllers.md` — the V1
  values action keeps the named self-seed exception and one payload
  collaborator.
- `agent/styleguides/fetcher/public-api-controllers.md` — the public
  catalog/detail response shapes, exact-key contracts, and
  unauthenticated behavior.
- `agent/styleguides/fetcher/caching.md` — cache key version bumps for
  changed payloads, TTLs unchanged.
- `agent/adr/fetcher/cross-scenario-service-layer.md` (amended) — the
  service → read-only query dependency does not transfer write ownership.
- `agent/adr/fetcher/list-query-objects-layer.md` (amended) — the
  shared concern-query shape and its constraints.
- `agent/adr/fetcher/service-result-contract.md` — the recording
  service's `Ok`/`Skipped` outcomes.
- `agent/adr/fetcher/price-cache-invalidation.md` — the cache-version
  convention behind the bumps.
- `agent/adr/fetcher/rspec-testing-strategy.md` — spec levels and the
  real-DB/real-cache testing stance.

### `app_core`

- `agent/styleguides/core/architecture-layers.md` — each island keeps
  reading `app_fetcher` directly; no proxy/reserve endpoint is added.
- `agent/styleguides/core/react-dashboard.md` — the partial-valuation
  badge, delta suppression for incomplete/partial/unavailable change,
  stale-price marking, shared `utils/` placement, hook status shape, and
  Vitest/@testing-library conventions.
- `agent/adr/core/multiple-react-islands.md` — the shared
  `priceFreshness.js`/`retrySchedule.js` extraction follows the
  pure/stateless-across-islands rule.
- `agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  why the dashboard/detail islands consume the new payloads directly.
- `agent/adr/core/component-tests-real-reducer.md` — the component-test
  style for the updated tiles/cards.

## Completion Criteria

- [x] Desired behavior is explicit (current value, bootstrap/steady
      state, completeness, change semantics, freshness).
- [x] Scope is explicit (price-only changes, intraday history, admin UI
      excluded).
- [x] Affected backend and frontend files/components are identified.
- [x] Test strategy is defined for every new/changed behavior.
- [x] Implementation steps are ordered and executable.
- [x] Verification is defined, including the cross-surface manual check.
- [x] Plan checked against styleguides (`styleguides-check`).
- [x] Implemented (`implement-plan`).

# Implementation Summary

## Implemented

**Data model / valuation**

- Added `items.price_updated_at` (with a one-time backfill from
  `updated_at` for priced items) and nullable `items_count` /
  `pricable_items_count` / `priced_items_count` on
  `inventory_value_logs`.
- Added `InventoryValuation` (`app/queries/inventory_valuation.rb`): the
  single definition of current value, completeness, the daily-series +
  live-point series, change calculation, the V1 page payload, and the
  bulk catalog baseline. It shares one set of SQL aggregate expressions
  between the single-inventory and grouped catalog paths.
- `InventoryValueLog#complete?` treats legacy nil counters as complete.

**Recording / jobs**

- `InventoryValueRecordingService` now distinguishes bootstrap from
  steady state: waits for first prices (48h timeout, only when at least
  one price exists), writes partial daily rows in steady state, skips a
  non-empty inventory with no prices at all, and stores the completeness
  counters.
- `InventoryValueScheduler` fans out to every `UserInventory` (not only
  users with an existing log) and now declares `retry: 3`; the
  corresponding `fix_me.md` entry was removed.
- `PriceUpdateService` writes `price_updated_at` on a successful fetch.

**API / queries**

- `InventoryCatalogQuery` uses the shared valuation aggregates and a
  bulk 24h baseline; cards now expose completeness and change
  availability/partial/basis fields. A baseline older than two days
  makes the delta unavailable.
- `InventoryDetailQuery`/serializer use the live valuation for the hero
  total and average, return a live-appended history, and expose
  completeness/change flags plus per-item `price_updated_at`.
- `Api::V1::InventoryValuesController` returns `{ current, history,
  change }`, self-seeds only when no log exists, and returns a live
  partial snapshot even when the bootstrap gate skipped the write.
- `Api::V1::ItemPricesController#dynamics` includes
  `price_updated_at`.

**Frontend**

- `usePortfolioHistory` consumes the new object shape, drives the
  estimating state from `current.complete`, and retries on the shared
  bounded schedule while the valuation is incomplete or the inventory is
  not synced yet.
- `PortfolioTile` shows the live/partial value with an
  `Estimating…`/`n/m priced` badge, suppresses the delta for
  incomplete/partial/unavailable change, and uses the backend change.
- `PortfolioHeroTile` and `InventoryCard` gained the same partial badge
  and delta gating; cards title the delta with its comparison date.
- `ItemRow` and `InventoryItemRow` mark prices older than 24h with
  `is-stale` and a `Price updated <age>` title, while keeping the last
  price and delta.
- Added `shared/utils/priceFreshness.js` and
  `shared/utils/retrySchedule.js`; removed the now-duplicated
  `dashboard/utils/valuation.js` and its test.
- Bumped the cache key versions for `ItemPriceCache`,
  `UserInventoryCache`, `InventoryCatalogCache`, and
  `InventoryDetailCache`.

**Documentation**

- Amended `fetcher/list-query-objects.md`, `fetcher/architecture-layers.md`,
  `fetcher/services.md`, and `core/react-dashboard.md`, plus the two
  existing ADRs (`list-query-objects-layer.md`,
  `cross-scenario-service-layer.md`), as approved.

## Tests

Added/changed:

- `app_fetcher/spec/queries/inventory_valuation_spec.rb` (new, 14
  examples), `spec/models/inventory_value_log_spec.rb` (new, 4).
- Extended recording-service, scheduler, catalog/detail query, catalog/
  detail serializer, public inventories, V1 inventory values, V1 item
  prices, price-update service, and inventory-value worker specs.
- `app_core`: `priceFreshness.test.js` (new); updated
  `usePortfolioHistory`, `PortfolioTile`, `useItemPrices`, `ItemRow`,
  `useInventoryDetail`, `InventoryDetail`, `InventoryCard`,
  `InventoryItemRow`, and `useInventoryCatalog` tests; removed
  `valuation.test.js`.

Commands actually run:

```text
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"
docker compose run --rm -T app_fetcher bash -c "bundle exec srb tc"
docker compose run --rm -T app_fetcher bash -c "bin/rubocop -f simple"
docker compose run --rm -T app_core bash -c "npm test"
docker compose run --rm -T app_core bash -c "RAILS_ENV=test bundle exec rspec"
docker compose run --rm -T app_core bash -c "npm run format:check && npm run lint"
```

## Verification

- `app_fetcher`: 435 examples, 0 failures.
- `app_fetcher` `srb tc`: no errors.
- `app_fetcher` RuboCop: 152 files inspected, no offenses.
- `app_core` Vitest: 43 files, 269 tests, all passing.
- `app_core` RSpec: 50 examples, 0 failures.
- Prettier: clean. ESLint: 0 errors; one pre-existing
  `react-hooks/exhaustive-deps` warning in
  `tracked_items/TrackedItems.jsx` (untouched file).
- Manual API cross-surface check with seeded local data: the V1 payload,
  catalog cards, and detail portfolio all returned the same live total
  (`2234` for the complete inventory, `1234` for the partial one), with
  `complete`/`change_partial`/counts and the baseline-derived change
  (`234`) matching across surfaces.
- A full browser/Steam-login check was not performed (same environment
  limitation noted in prior plans).

## Deviations

- `InventoryDetail.jsx` itself needed no change: `PortfolioHeroTile`
  already receives the full `portfolio` object, so the badge/delta logic
  lives there. The `Avg. item value` stat still uses live
  `total / items_count`; no extra stat note was added.
- `InventoryValuation` owns the V1 page/series/baseline helpers instead
  of introducing a separate `InventoryValuesQuery`; this keeps one
  valuation definition and matches the amended query-layer guide.
- `change_partial` is `true` for a partial current valuation even when
  the change is unavailable (no baseline), so callers can distinguish
  "no comparison" from "complete but flat".
- Partial history points are exposed via `complete` on each point but
  the chart does not yet draw them differently; the badge/delta
  suppression carries the honesty requirement.
- `bin/ci` was not used as a single entry point: `app_fetcher/bin/ci` is
  still the pre-existing `LoadError` case noted in `fix_me.md`; the
  individual commands above are the same checks.

## Remaining Issues

- Browser-level manual verification of the estimating → complete
  transition and the three surfaces together still needs a live Steam
  login.
- The 2-minute response caches can still make catalog/detail/V1 values
  disagree briefly after a price update; this is bounded TTL drift, not
  a different valuation definition.
- Complex/partial chart styling is unchanged; only the delta and badge
  behavior marks a partial valuation.

## Follow-up: `price_unavailable` price coverage

- `GET /api/v1/inventories/me` now includes `price_unavailable` per item.
- `useDashboardData` maps it to `priceUnavailable`.
- `Dashboard.jsx` passes `priceableNames(items)` (marketable **and** not
  price-unavailable) to `useItemPrices`, so an unavailable item no longer
  keeps the bounded retry running. It still appears in `dynamics` when it
  has a last known price, so its row keeps that price.
- Added `dashboard/utils/priceCoverage.js` +
  `priceCoverage.test.js`; updated `useDashboardData` and the
  `app_fetcher` inventories request spec.
- Re-ran: `app_fetcher` 435 examples / 0 failures, `srb tc` clean,
  RuboCop clean; `app_core` 43 files / 269 tests passing, Prettier clean,
  ESLint 0 errors (same pre-existing warning).
