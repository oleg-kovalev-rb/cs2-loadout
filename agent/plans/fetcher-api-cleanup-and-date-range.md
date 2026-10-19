---
status: implemented
app: fetcher
goal: Remove the dead inventory refresh endpoint, move inventory response shaping into a serializer, stop seeding inventory values on read, replace PricePeriod with Options::DateRange plus history query objects, and return a V1 404 for unknown items
created: 2026-10-20
---

# Development Plan

## Applicable Styleguides

- **`agent/styleguides/rails-layering.md`** — thin-controller invariant:
  period parsing/cutoffs move into query objects, response shaping into
  serializers, and the controller keeps cache/render orchestration.
- **`agent/styleguides/ruby-sorbet.md`** — `# typed: strict`, explicit
  sigs, the `Options::DateRange` `T::Enum`/`Param` shape (amended
  2026-10-20), and RBI expectations (none needed for non-AR enums/
  queries).
- **`agent/styleguides/rspec-conventions.md`** — query/serializer unit
  specs vs. request specs, zero-I/O serializer specs, and the
  `fix_me.md`-required VCR migration for
  `spec/requests/api/v1/inventories_spec.rb`.
- **`agent/styleguides/fetcher/internal-api-controllers.md`** — V1
  routes/auth, the `find_by!` + `rescue_from ActiveRecord::RecordNotFound`
  → `404 {"message":"Not found"}` contract, and the remaining
  `InventoriesController#show` cold-start service carve-out (amended
  2026-10-20).
- **`agent/styleguides/fetcher/public-api-controllers.md`** — public
  inventory-detail range validation through
  `Options::DateRange::Param` with `Api::Public::UnsupportedParamError`
  (amended 2026-10-20).
- **`agent/styleguides/fetcher/list-query-objects.md`** — query-object
  return structs, `Options::DateRange::Param`, query-owned cutoffs,
  `<Resource>HistoryQuery`, `<Resource>Serializer`, and zero-I/O
  serializer rules (amended 2026-10-20).
- **`agent/styleguides/fetcher/architecture-layers.md`** — layer map:
  read endpoints call query objects, and
  `InventoryValueRecordingService` is worker-only (amended 2026-10-20).
- **`agent/styleguides/fetcher/caching.md`** — `PriceHistoryCache`
  remains controller-owned and explicit-`period=30d` only; the history
  query never touches it (amended 2026-10-20).
- **`agent/styleguides/fetcher/services.md`** — confirms
  `InventoryValueRecordingService` stays a service despite losing its
  controller call site (ownership, not caller count).
- **`agent/styleguides/fix_me.md`** — `inventories_spec.rb` must be
  migrated to VCR on this touch, and its entry removed.
- **`agent/styleguides/ci-and-coverage.md`** — verification commands run
  through `docker compose`.
- **`agent/styleguides/git-commits.md`** — `[Scope] Imperative summary`
  commit format for the final local commit.

## Goal

Finish the controller-layer cleanup planned in
`agent/plans/fetcher-controller-layer-polish.md`:

1. Delete the unused `POST /api/v1/inventories/refresh` endpoint.
2. Move the `inventories/me` response shape into `InventorySerializer`.
3. Stop writing `InventoryValueLog` rows from a read request
   (`InventoryValuesController#index`).
4. Replace the model-level `PricePeriod` vocabulary with an
   `Options::DateRange` query option plus two history query objects, so
   models no longer own period constants or cutoff scopes.
5. Make an unknown `market_hash_name` in
   `item_prices#history` return V1's standard not-found response instead
   of `200 []`.

## Expected Behavior

### Removed refresh endpoint

- `POST /api/v1/inventories/refresh` no longer exists.
- `GET /api/v1/inventories/me` keeps its current behavior and response
  shape: `{ items_count, items: [{ market_hash_name,
  price_unavailable, metadata }] }`.

### Inventory values read path

- `GET /api/v1/inventory_values` returns the same JSON keys/values and
  the same period vocabulary (`24h` is still rejected).
- The request performs no writes: no `InventoryValueLog` row is created
  or updated by the controller.
- On a cold start (no stored rows), `current` is still computed live and
  `history` contains the single live point. `change.available` is `false`
  and `change.cents` is `0`.
- The first stored row now appears only after the next
  `InventoryValueUpdateWorker` run. The dashboard's live current value
  is unaffected.

### Period/range vocabulary

- `period` remains the external query parameter and the serialized values
  remain `24h`, `7d`, `30d`, `1y`, `all`.
- `inventory_values` accepts `7d`/`30d`/`1y`/`all`, defaults to `all`,
  and rejects `24h` and unknown values with
  `400 { message: "Unsupported period: <raw>" }`.
- `inventory_values` history is filtered by the resolved range inside
  `InventoryValuation`.
- Public inventory detail accepts `7d`/`30d`/`1y`/`all`, defaults to
  `7d`, and keeps rejecting `24h`/unknown values with
  `400 { message: "Unsupported period: <raw>" }`.
- `item_prices/:market_hash_name/history` accepts all five values,
  defaults to `30d`, and rejects unknown values with the same 400 shape.
- Its response shape stays `[{ at, price_cents, volume }]`.

### Item history cache and 404

- An explicit `period=30d` still serves the 30-day `PriceHistoryCache`
  fast path without querying `PriceLog`.
- An absent `period` follows the query path (where it resolves to
  `Last30Days`); the response is identical to the cache path, only the
  cache hit is skipped. This is accepted.
- An unknown `market_hash_name` returns
  `404 { message: "Not found" }` for every period, including explicit
  `30d`. A known item with no logs in the window still returns `200 []`.
- `ItemPricesController#history` resolves the item once with
  `Item.find_by!(market_hash_name: ...)` before branching. Because the
  item is already resolved, `ItemPriceHistoryQuery` accepts the `Item`
  record rather than re-looking it up by name.

## Scope

### In Scope

- Removing the refresh route, action, dedup constant, and request-spec
  block.
- `InventorySerializer` and its unit spec.
- Removing the inventory-values seed and updating its request specs.
- New `Options::DateRange` + `Options::DateRange::Param`.
- New `InventoryValueHistoryQuery` and `ItemPriceHistoryQuery`.
- Moving inventory-value cutoffs from model scopes into
  `InventoryValuation` / `ItemPriceHistoryQuery`.
- Updating `InventoryValuation`, `InventoryDetailQuery`,
  `InventoryDetailSerializer`, `InventoryValuesController`,
  `ItemPricesController`, and `Api::V1::BaseController`.
- Updating all affected model/query/request specs.
- Updating living styleguides, ADRs, and the dashboard user story.
- Migrating `spec/requests/api/v1/inventories_spec.rb` from hand-written
  `stub_request` bodies to VCR cassettes, as required by
  `agent/styleguides/fix_me.md` for the next touch of that file.

### Out of Scope

- Any `app_core`/frontend code change. `useItemHistory` already surfaces
  non-OK responses as an error state; the dashboard only requests names
  from the user's own inventory.
- Splitting `PriceHistoryCache` into separate `read`/`write` operations
  or caching ranges other than 30d.
- Unifying `Options::DateRange` with `FilterApplier` via a shared
  context.
- Extracting item-history point response shaping into a serializer; the
  controller keeps the small `Point -> Hash` mapping for now.
- Removing `PriceHistoryCache.fetch_for` or changing its callers
  (`PriceUpdateWorker`, admin warm-up).
- Changing `InventoryValueRecordingService` itself. It remains, but is
  called only from `InventoryValueUpdateWorker`.
- Historical plan files (`fetcher-controller-layer-polish.md`,
  `user-inventory-persistence.md`, etc.).

## Implementation Approach

### Date range option

`app_fetcher/app/queries/options/date_range.rb` owns the closed range
vocabulary:

- `Options::DateRange < T::Enum` with `Last24Hours`, `Last7Days`,
  `Last30Days`, `LastYear`, `AllTime`; serialized as the existing
  `24h`/`7d`/`30d`/`1y`/`all`.
- `#duration`, `#since`, `#since_date` move over unchanged from
  `PricePeriod`.
- Nested `Options::DateRange::Param` with
  `allowed_ranges:`, `default:`, `error_class:`, and `#parse(raw)`.
  Blank input resolves to `default`; a recognized but disallowed value
  (e.g. `24h` for inventory values) and an unknown value both raise
  `error_class` with `"Unsupported period: <raw>"`.
- No `RANGE_PARAM` constant. Each query object constructs its own
  `Param` inside `.call`.

`InventoryValuation::SUPPORTED_RANGES` is the inventory-values allow-list
(everything except `Last24Hours`). `ItemPriceHistoryQuery` uses
`Options::DateRange.values`.

### Query objects and cutoff ownership

- `InventoryValueHistoryQuery.call(steam_id, params)` resolves the range
  with `InventoryValuation::SUPPORTED_RANGES`, default `AllTime`, and
  `Api::V1::UnsupportedParamError`, then returns
  `InventoryValuation.page(steam_id, range)`.
- `ItemPriceHistoryQuery.call(item, params)` resolves the range with
  `Options::DateRange.values`, default `Last30Days`, and
  `Api::V1::UnsupportedParamError`, applies the cutoff to `PriceLog`
  (`where(created_at: range.since..)`, or no cutoff for `AllTime`), and
  returns a `Page` struct carrying `range` and ordered `Point` structs
  (`at`, `price_cents`, `volume`). It never touches
  `PriceHistoryCache`.
- `InventoryValuation.series/page` take `range` instead of `period`.
  `series` applies `range.since_date` to `InventoryValueLog` directly.
- `InventoryDetailQuery` resolves the range through the same `Param`
  (inventory allow-list, default `Last7Days`, `Api::Public::
  UnsupportedParamError`) and exposes it as `Page#range`.
- Models no longer know about ranges: delete `SUPPORTED_PERIODS` and
  `scope :for_period` from `InventoryValueLog` and `PriceLog`.

### Controller boundaries

- `InventoryValuesController#index` becomes: resolve through
  `InventoryValueHistoryQuery`, render
  `InventoryValuationSerializer.call(page)`.
- `ItemPricesController#history`:
  1. `item = Item.find_by!(market_hash_name: params[:market_hash_name])`;
  2. if `params[:period] == Options::DateRange::Last30Days.serialize`,
     use `PriceHistoryCache`;
  3. otherwise call `ItemPriceHistoryQuery.call(item, params)` and map
     its points to the existing JSON hash shape.
- `InventoriesController` keeps only `show`/`render_resolved`;
  `render_inventory` renders `InventorySerializer.call(items)`.
- `Api::V1::BaseController` adds
  `rescue_from ActiveRecord::RecordNotFound, with: :render_not_found`
  after the `StandardError` handler, rendering
  `404 { message: "Not found" }`.

## Files To Modify

- **`app_fetcher/app/controllers/api/v1/inventories_controller.rb`**
  - Remove `refresh`, `REFRESH_DEDUP_TTL`, and the direct hash shaping;
    use `InventorySerializer.call(items)` in `render_inventory`.
  - Reason: endpoint is unused; response shaping belongs in a serializer.

- **`app_fetcher/config/routes.rb`**
  - Remove `post "inventories/refresh"`.
  - Reason: route would otherwise point at a removed action.

- **`app_fetcher/app/controllers/api/v1/inventory_values_controller.rb`**
  - Remove `seed_if_empty`. Call `InventoryValueHistoryQuery` and render
    the serializer result.
  - Reason: the read endpoint must not write, and period resolution moves
    to the query layer.

- **`app_fetcher/app/controllers/api/v1/item_prices_controller.rb`**
  - Replace the period block and `find_by`/`nil` branch with
    `find_by!`, the explicit 30d cache branch, and
    `ItemPriceHistoryQuery`.
  - Reason: consistent 404, query-owned cutoff, cache still controller-only.

- **`app_fetcher/app/controllers/api/v1/base_controller.rb`**
  - Add the `RecordNotFound` rescue after `StandardError`, plus private
    `render_not_found`.
  - Reason: `find_by!` now raises in a V1 action.

- **`app_fetcher/app/models/inventory_value_log.rb`**
  - Remove `SUPPORTED_PERIODS` and `scope :for_period`.
  - Reason: range vocabulary/cutoff moves to the query layer.

- **`app_fetcher/app/models/price_log.rb`**
  - Remove `SUPPORTED_PERIODS` and `scope :for_period` (and the now
    unused `extend T::Sig` if no sigs remain).
  - Reason: same as above.

- **`app_fetcher/app/queries/inventory_valuation.rb`**
  - Add `SUPPORTED_RANGES`; rename `period:` to `range:`; apply the
    cutoff inside `series`; update `page` and sigs.
  - Reason: `InventoryValuation` remains the single owner of inventory
    series aggregation.

- **`app_fetcher/app/queries/inventory_detail_query.rb`**
  - Resolve `Options::DateRange::Param` (public error class, default
    `Last7Days`); rename `Page#period` to `Page#range`; pass `range` to
    `InventoryValuation`.
  - Reason: model no longer owns period resolution.

- **`app_fetcher/app/serializers/inventory_detail_serializer.rb`**
  - Keep the external `period:` key but serialize `page.range`.
  - Reason: HTTP contract unchanged.

- **`app_fetcher/spec/requests/api/v1/inventories_spec.rb`**
  - Delete the entire `POST /api/v1/inventories/refresh` describe block.
  - Migrate the remaining Steam HTTP stubs from inline `stub_request`
    bodies to VCR cassettes (per `fix_me.md`).
  - Reason: endpoint removal + known test-mechanics deviation.

- **`app_fetcher/spec/requests/api/v1/inventory_values_spec.rb`**
  - Cold-start example must expect a live history point and **no**
    `InventoryValueLog` row.
  - Remove the duplicate-row and "does not recompute today's row"
    examples (no writes remain).
  - Keep the period-filter, unsupported-period, and unhandled-error
    contexts.
  - Reason: no-seed behavior.

- **`app_fetcher/spec/requests/api/v1/item_prices_spec.rb`**
  - Unknown `market_hash_name` now expects `:not_found` /
    `"Not found"`; add an explicit `?period=30d` case to prove the cache
    branch also 404s.
  - Change the warm-cache example to request `?period=30d` explicitly
    (an absent period now intentionally misses the cache).
  - Reason: changed contract and accepted cache nuance.

- **`app_fetcher/spec/models/inventory_value_log_spec.rb`**
  - Remove the `.for_period` block; keep `#complete?` coverage.
  - Reason: scope removed.

- **`app_fetcher/spec/models/price_log_spec.rb`**
  - Remove the `.for_period` block; delete the spec file if no examples
    remain.
  - Reason: scope removed.

- **`app_fetcher/spec/queries/inventory_valuation_spec.rb`**
  - Replace `PricePeriod::*` with `Options::DateRange::*` in `.series` /
    `.page` calls.
  - Reason: API rename.

- **`app_fetcher/spec/queries/inventory_detail_query_spec.rb`**
  - Replace `page.period` with `page.range`; use `Options::DateRange`
    constants; keep the exact error-message assertions.
  - Reason: struct field rename.

- **`app_fetcher/spec/models/price_period_spec.rb`**
  - Delete; replaced by `spec/queries/options/date_range_spec.rb`.
  - Reason: class relocation.

- **`agent/styleguides/fetcher/list-query-objects.md`**
  - Replace the `PricePeriod`/`SUPPORTED_PERIODS`/`for_period`
    conventions with `Options::DateRange::Param` (`allowed_ranges:`,
    `default:`, `error_class:`, `#parse`) and query-owned cutoffs.
  - Add `InventoryValueHistoryQuery` / `ItemPriceHistoryQuery` /
    `InventorySerializer` to the layer examples and testing rules.
  - Reason: living contract for the query/serializer layer.

- **`agent/styleguides/fetcher/internal-api-controllers.md`**
  - Remove the `#refresh` and inventory-values seed carve-outs; the only
    synchronous service call left is `InventoriesController#show`'s
    cold-start branch.
  - Replace the "V1 has no bang finders, so no `RecordNotFound` rescue"
    argument with the new `find_by!` + `rescue_from` shape and add the
    404 response shape to Error Handling.
  - Update `PricePeriod.resolve` references to `Options::DateRange::Param`.
  - Reason: the styleguide must not contradict the new code.

- **`agent/styleguides/fetcher/public-api-controllers.md`**
  - Update closed-enum period handling to `Options::DateRange::Param`.
  - Note that V1 now also renders a standard `404 { message: "Not found" }`
    for its bang finder, keeping the namespaces' behaviors distinct.
  - Reason: stale period guidance.

- **`agent/styleguides/fetcher/architecture-layers.md`**
  - Remove `#refresh` from the persisted-endpoint list; update
    `InventoryValueRecordingService` to worker-only.
  - Reason: flow description must match code.

- **`agent/styleguides/core/architecture-layers.md`**
  - Verify no stale references; update only if an inventory/refresh flow
    is described there.
  - Reason: cross-app layer map.

- **`agent/adr/fetcher/cross-scenario-service-layer.md`**
  - Remove the `InventoryValuesController#index` cold-start seed from
    the carve-out and adjust current-state statements that say the
    recording service has two callers. Preserve the historical decision
    record.
  - Reason: one call site remains.

- **`agent/adr/fetcher/list-query-objects-layer.md`**
  - Update current-state references from `PricePeriod` + model scopes to
    `Options::DateRange` + query cutoffs, and note the inline usage is now
    migrated.
  - Reason: living ADR references.

- **`agent/adr/fetcher/service-result-contract.md`**
  - Update the `PricePeriod` precedent reference to `Options::DateRange`.
  - Reason: class rename.

- **`agent/adr/fetcher/public-api-namespace.md`**
  - Add the V1 `rescue_from ActiveRecord::RecordNotFound` to the current
    implementation constraints.
  - Reason: current-state accuracy.

- **`agent/styleguides/ruby-sorbet.md`**
  - Replace the `PricePeriod` / model `SUPPORTED_PERIODS` / `.resolve`
    example with `Options::DateRange` / `Options::DateRange::Param`.
  - Reason: the canonical enum example moved.

- **`agent/styleguides/rspec-conventions.md`**
  - Update the query-option example to include `Options::DateRange` (the
    layer mapping itself is unchanged).
  - Reason: keep canonical examples current.

- **`agent/US/dashboard-user-story.md`**
  - Status snapshot: remove manual refresh and `InventoryValueLog`
    self-seeding from "already live".
  - Step 5: first stored row comes from the nightly worker; the read does
    not seed.
  - Step 8: remove the manual-refresh section.
  - Endpoint reference: remove `POST /inventories/refresh`; update history
    default/cache wording and the new 404; mark `inventory_values` as
    read-only.
  - Data map: daily portfolio value is nightly-written, not self-seeded.
  - Reason: user story must not describe removed flows.

## Files To Create

- **`app_fetcher/app/queries/options/date_range.rb`**
  - `Options::DateRange` enum + nested `Param` parser.
  - Reason: closed range vocabulary with per-call allow-list/default/error
    configuration.

- **`app_fetcher/app/queries/inventory_value_history_query.rb`**
  - Resolves the V1 inventory range and delegates to
    `InventoryValuation.page`.
  - Reason: keeps period parsing out of the controller and gives the
    endpoint a query-object entry point.

- **`app_fetcher/app/queries/item_price_history_query.rb`**
  - Resolves the item-price range, reads `PriceLog`, returns a `Page` of
    `Point` structs.
  - Reason: replaces the inline `PriceLog` query in the controller.

- **`app_fetcher/app/serializers/inventory_serializer.rb`**
  - Pure `call(items)` shaping `{ items_count, items }`.
  - Reason: move the inventory response shape out of the controller.

- **`app_fetcher/spec/queries/options/date_range_spec.rb`**
  - Covers duration/since/since_date and `Param#parse` (blank default,
    allowed value, disallowed value, unknown value, exact error and
    message).
  - Reason: unit coverage for the shared parser.

- **`app_fetcher/spec/queries/inventory_value_history_query_spec.rb`**
  - Covers default `all`, explicit supported ranges, rejected `24h` /
    unknown, and delegation to `InventoryValuation.page`.
  - Reason: endpoint-level parsing and cutoff behavior.

- **`app_fetcher/spec/queries/item_price_history_query_spec.rb`**
  - Covers default `30d`, `24h`/`1y`/`all`, unknown rejection, ordering,
    cutoff inclusion/exclusion, and the returned point fields.
  - Reason: replaces controller-level query coverage.

- **`app_fetcher/spec/serializers/inventory_serializer_spec.rb`**
  - Unit spec with unsaved `Item` instances; asserts count, keys
    (`market_hash_name`, `price_unavailable`, `metadata`), and values.
  - Reason: lock the response shape without DB access.

- **`app_fetcher/spec/cassettes/.../inventories_me/*.yml`**
  - VCR cassettes for the remaining cold-start/failure contexts in
    `inventories_spec.rb` (created by recording or hand-writing the
    equivalent Steam response, matching the existing admin cassette
    format).
  - Reason: satisfy the request-level VCR rule flagged in `fix_me.md`.

## Test Plan

### Request specs

- `inventories_spec.rb`: `GET /inventories/me` behavior unchanged; no
  `POST /inventories/refresh` examples.
- `inventory_values_spec.rb`:
  - cold start returns live `current` + one live history point and
    writes no `InventoryValueLog` row;
  - partial snapshot still returns live counts and writes no row;
  - existing log + live point response unchanged;
  - period filters (`all`, `30d`, `7d`, `1y`) unchanged;
  - `24h`/`3weeks` still `400` with the exact message;
  - no `InventoryValueUpdateWorker` jobs enqueued.
- `item_prices_spec.rb`:
  - unknown name → `404 { message: "Not found" }` for absent period and
    explicit `30d`;
  - known item with no logs in window → `200 []`;
  - explicit `period=30d` warm cache → zero `PriceLog` queries;
  - absent period → same points via the query path;
  - `1y`/`24h`/default windows unchanged.

### Unit specs

- `Options::DateRange` + `Param#parse`, including exact error classes and
  messages.
- `InventoryValueHistoryQuery` and `ItemPriceHistoryQuery` against real
  DB rows (query objects), no response-payload cache references.
- `InventoryValuation.series/page` with `Options::DateRange`, including
  cutoff filtering and `AllTime` no-cutoff.
- `InventorySerializer` with in-memory items, no `create`.
- Updated `InventoryDetailQuery` specs (`range`, public error class).

### Regression coverage

- Full `app_fetcher` RSpec suite must stay green.
- Public API request specs must keep the same statuses/messages.
- Admin request specs are unaffected except shared model changes.

## Implementation Steps

1. Add `spec/queries/options/date_range_spec.rb` and the new
   `Options::DateRange` implementation (RED → GREEN). Include `Param`
   parsing tests before implementing.
2. Move `PricePeriod`'s duration/since logic into `Options::DateRange`;
   delete `app/models/price_period.rb` and `spec/models/price_period_spec.rb`.
3. Update `InventoryValuation` to `SUPPORTED_RANGES` + `range` args +
   query-owned cutoff; update its spec.
4. Add `InventoryValueHistoryQuery` with specs; update
   `InventoryValuesController#index` to use it, removing `seed_if_empty`.
5. Update `inventory_values_spec.rb` for no-write cold start; remove the
   obsolete write/dedup examples.
6. Add `ItemPriceHistoryQuery` with specs; update
   `ItemPricesController#history` to `find_by!` + explicit 30d cache
   branch + query path.
7. Add the `RecordNotFound` rescue to `Api::V1::BaseController`; update
   `item_prices_spec.rb` for 404 and the explicit-30d cache assertion.
8. Add `InventorySerializer` + unit spec; update
   `InventoriesController#render_inventory`.
9. Remove the refresh action, dedup constant, route, and request-spec
   block.
10. Update `InventoryDetailQuery` (`range`) and
    `InventoryDetailSerializer` (`page.range.serialize`); update their
    specs.
11. Remove `SUPPORTED_PERIODS`/`for_period` from both models; update the
    model specs.
12. Migrate `inventories_spec.rb`'s remaining HTTP stubs to VCR
    cassettes and remove the `fix_me.md` entry for that file.
13. Verify the styleguides/ADRs already amended during styleguides-check
    still match the implemented code, and update the remaining living
    docs (`agent/US/dashboard-user-story.md` and any historical ADR
    notes that now read as current state).
14. Run the full verification suite below.

## Verification

From the repo root, using the project Docker setup:

- `docker compose exec app_fetcher bundle exec rspec spec/queries/options/date_range_spec.rb spec/queries/inventory_value_history_query_spec.rb spec/queries/item_price_history_query_spec.rb spec/queries/inventory_valuation_spec.rb spec/queries/inventory_detail_query_spec.rb spec/serializers/inventory_serializer_spec.rb`
- `docker compose exec app_fetcher bundle exec rspec spec/requests/api/v1/ spec/requests/api/public/ spec/requests/api/admin/`
- `docker compose exec app_fetcher bundle exec rspec`
- `docker compose exec app_fetcher bin/rubocop app/controllers app/models app/queries app/serializers spec/queries spec/serializers spec/requests`
- `docker compose exec app_fetcher bundle exec srb tc` — compare against
  the pre-change error count; only new errors count as regressions.
- `git diff --check`
- Grep for stale references:
  `grep -rn "PricePeriod\|SUPPORTED_PERIODS\|for_period\|inventories/refresh\|seed_if_empty" app_fetcher agent/styleguides agent/adr agent/US`
  — only historical plan files may still match.

Manual spot checks (optional):

- `POST /api/v1/inventories/refresh` → routing 404.
- `GET /api/v1/item_prices/<unknown>/history?period=30d` → `404 {"message":"Not found"}`.
- `GET /api/v1/inventory_values` on a cold user → live current/history,
  and no new `inventory_value_logs` row.

## Risks

- **Cache-branch/404 consistency.** Resolving the item with `find_by!`
  before branching is what keeps explicit `30d` and other ranges on the
  same 404 contract. Do not move the lookup after the cache branch.
- **Absent-period cache miss.** The warm-cache spec must request
  `period=30d` explicitly; an absent period intentionally goes through
  the query and will hit `PriceLog`.
- **Error ordering.** `rescue_from ActiveRecord::RecordNotFound` must be
  declared after `rescue_from StandardError`; otherwise the catch-all
  could turn a 404 into a 500.
- **Range cutoff semantics.** `InventoryValueLog` uses `since_date`
  (daily granularity); `PriceLog` uses `since` (timestamp). Keep those
  distinctions in the query objects and specs.
- **Empty allowed set/default mismatch.** `Param#parse` must raise on a
  recognized-but-disallowed value (`24h` for inventory values), not
  silently fall back to the default.
- **Public detail contract.** Renaming `Page#period` to `#range` must
  not change the serialized `period` key or its values.
- **Doc drift.** `PricePeriod` is referenced from multiple living docs;
  the final grep is the guard against half-migrated guidance.
- **VCR migration.** Cassettes must match the exact request URIs
  (per-context steam ids). If recording is impossible in this
  environment, hand-write them from the existing stub bodies in the same
  format as the admin cassette, and do not leave the stale `fix_me`
  entry.
- **No writes on read.** Removing the seed also removes the only
  controller write path for `InventoryValueLog`; verify the worker still
  covers every `UserInventory` and no spec relies on request-time
  creation.

## Assumptions

- `app_core` never calls `POST /api/v1/inventories/refresh` (verified: no
  frontend/backend call site; only the removed spec).
- The dashboard's live current value comes from the live valuation, not
  from a stored row, so removing the seed does not regress the first
  render.
- `PriceHistoryCache.fetch_for` returns the same point shape as the
  direct `PriceLog` query (`at`, `price_cents`, `volume`).
- The V1 404 body is intentionally generic (`"Not found"`), matching
  `Api::Admin::BaseController`, not the Public namespace's
  resource-named message.

## Completion Criteria

- The refresh endpoint, action, route, and spec block are gone.
- `InventorySerializer` owns the `inventories/me` response shape.
- `InventoryValuesController#index` performs no writes and uses
  `InventoryValueHistoryQuery`.
- No model references `Options::DateRange`, `SUPPORTED_PERIODS`, or
  `for_period`; cutoffs live in query objects.
- `PricePeriod` no longer exists; `Options::DateRange` and `Param#parse`
  are the only range vocabulary/parser.
- Unknown item history returns `404 { message: "Not found" }` on every
  period; known-but-empty history still returns `200 []`.
- Existing request-spec statuses/messages for valid ranges are unchanged.
- `inventories_spec.rb` no longer uses inline `stub_request` bodies and
  is removed from `agent/styleguides/fix_me.md`.
- Living docs contain no stale references to removed classes/flows.
- Full `app_fetcher` RSpec suite, RuboCop, and `srb tc` pass with no new
  errors.

---

# Implementation Summary

## Implemented

- Removed `POST /api/v1/inventories/refresh`, its action, dedup
  constant, route, and request-spec block.
- Added `InventorySerializer` and switched
  `InventoriesController#render_inventory` to it.
- Removed `InventoryValuesController#seed_if_empty`; the endpoint is now
  a pure read using `InventoryValueHistoryQuery`.
- Added `Options::DateRange` (`Last24Hours`, `Last7Days`, `Last30Days`,
  `LastYear`, `AllTime`) with nested `Options::DateRange::Param`
  (`allowed_ranges:`, `default:`, `error_class:`, `#parse`).
- Added `InventoryValueHistoryQuery` (V1 error class, default
  `AllTime`) and `ItemPriceHistoryQuery` (V1 error class, default
  `Last30Days`, accepts the resolved `Item`).
- Moved inventory-value cutoffs into `InventoryValuation#series` and
  item-price cutoffs into `ItemPriceHistoryQuery`; removed
  `SUPPORTED_PERIODS`/`for_period` from both models and deleted
  `PricePeriod`.
- `InventoryDetailQuery::Page#period` became `#range`;
  `InventoryDetailSerializer` still emits the external `period:` key.
- `ItemPricesController#history` resolves the item with `find_by!` before
  branching, keeps the explicit `period=30d` `PriceHistoryCache` path,
  and delegates other ranges to `ItemPriceHistoryQuery`.
- `Api::V1::BaseController` now rescues
  `ActiveRecord::RecordNotFound` and renders
  `404 { message: "Not found" }`.
- Migrated `spec/requests/api/v1/inventories_spec.rb` from inline
  `stub_request` bodies to five VCR cassettes and removed its
  `fix_me.md` entry.
- Updated the applicable styleguides/ADRs and the dashboard user story.

## Tests

Added:

- `spec/queries/options/date_range_spec.rb` — durations/since/cutoffs
  and `Param#parse` default/allowed/disallowed/unknown/error-class cases.
- `spec/queries/inventory_value_history_query_spec.rb` — default all-time,
  explicit range, unknown steam_id, rejected `24h`/unknown values.
- `spec/queries/item_price_history_query_spec.rb` — default 30d, 24h/1y/all
  cutoffs, ordering, point fields, rejected unknown values.
- `spec/serializers/inventory_serializer_spec.rb` — envelope, item fields,
  empty inventory.
- `spec/cassettes/api_v1_inventories/*.yml` — cold start, unknown icon,
  unknown metadata, unpriced item, Steam failure.

Changed:

- `spec/requests/api/v1/inventories_spec.rb` — refresh block removed; VCR
  contexts; sync-once assertion via `UserInventorySyncService`.
- `spec/requests/api/v1/inventory_values_spec.rb` — cold start proves no
  `InventoryValueLog` write; obsolete write/dedup examples removed.
- `spec/requests/api/v1/item_prices_spec.rb` — unknown item is now 404
  (including explicit `30d`); warm-cache example uses `?period=30d`.
- `spec/queries/inventory_valuation_spec.rb`,
  `spec/queries/inventory_detail_query_spec.rb`,
  `spec/serializers/inventory_detail_serializer_spec.rb` — `PricePeriod`
  → `Options::DateRange`, `page.period` → `page.range`.
- `spec/models/inventory_value_log_spec.rb` — `for_period` block removed;
  `spec/models/price_log_spec.rb` and
  `spec/models/price_period_spec.rb` deleted.

Commands executed:

- `docker compose exec -T app_fetcher bundle exec rspec` — 474 examples,
  0 failures.
- `docker compose exec -T app_fetcher bundle exec rspec spec/requests/api
  spec/queries spec/serializers spec/models` — 339 examples, 0 failures.
- `docker compose exec -T app_fetcher bin/rubocop app/controllers/api/v1
  app/models/inventory_value_log.rb app/models/price_log.rb app/queries
  app/serializers config/routes.rb spec/models/inventory_value_log_spec.rb
  spec/queries spec/serializers spec/requests/api/v1` — 53 files, no
  offenses.
- `docker compose exec -T app_fetcher bundle exec srb tc` — no errors.
- `git diff --check` — clean.

## Verification

- Full `app_fetcher` RSpec suite: **474 examples, 0 failures**.
- RuboCop on all touched Ruby paths: **no offenses**.
- `srb tc`: **No errors**.
- No remaining `PricePeriod`/`SUPPORTED_PERIODS`/`for_period`/
  `inventories/refresh`/`seed_if_empty` references outside intentional
  negative rules and historical plan/ADR context.

## Deviations

- **VCR cassettes were hand-written**, matching the existing admin
  cassette format and the previously stubbed Steam bodies, rather than
  recorded against the live Steam API. This was deliberate and matches
  how the existing repository cassette is structured.
- **`ItemPriceHistoryQuery.call(item, params)` takes the resolved
  `Item`**, not `market_hash_name`, per the approved resolution of the
  30d-cache/404 contradiction. The controller resolves once with
  `find_by!` before branching.
- **`InventoryValueHistoryQuery` returns `InventoryValuation::Page`**
  directly rather than defining a duplicate page struct; it is already a
  `T::Struct` and carries everything the serializer needs.
- **`spec/models/price_log_spec.rb` was deleted** because its only
  examples covered the removed `for_period` scope.

## Remaining Issues

None. No frontend change was needed: `app_core` never called the removed
refresh endpoint, and `useItemHistory` already surfaces non-OK responses
as an error state.
