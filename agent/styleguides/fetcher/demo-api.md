---
description: app_fetcher demo API conventions — the read-only Api::Demo:: namespace, demo-token auth, the fixed Demo::Inventory showcase, Demo::PriceSeries synthetic data, Demo::Dataset assembly, and no-demo-writes testing rules.
---

# Demo API (`app_fetcher`)

See `agent/adr/fetcher/demo-api.md` for why demo reads get a separate
namespace and a generated dataset instead of persisted demo rows. This
file covers how that namespace and its collaborators are written.

## Purpose

Serve the demo dashboard and demo inventory page from one fixed
showcase dataset without a Steam identity and without persisting a demo
inventory. What belongs here: demo-token auth, fixed item composition,
deterministic synthetic price/history generation, demo response
assembly, and the item pool/seed task. What does not: demo session/
cookie/JWT ownership (that is `app_core`’s `core/demo-mode.md`), Steam
ingestion, or any demo writes to `UserInventory`/`InventoryValueLog`.

## When to Use

Use this pattern for any read that is scoped to a demo session rather
than a Steam identity. Not for public catalog reads (that is
`Api::Public::`), not for per-player reads (that is `Api::V1::`), and not
for admin reads (that is `Api::Admin::`). A demo read that would need to
write state is out of scope for this read-only namespace.

## Structure

- `app_fetcher/app/controllers/api/demo/base_controller.rb` —
  `Api::Demo::BaseController < ::ApplicationController`, demo-token
  auth, `StandardError` / `ActiveRecord::RecordNotFound` /
  `Api::Demo::UnsupportedParamError` handlers.
- `app_fetcher/lib/api/demo/unsupported_param_error.rb` —
  `Api::Demo::UnsupportedParamError < StandardError`, the namespace-local
  closed-enum validation error.
- `app_fetcher/app/controllers/api/demo/inventories_controller.rb` —
  `show` (dashboard skeleton), `summary`, and `detail`.
- `app_fetcher/app/controllers/api/demo/inventory_values_controller.rb` —
  portfolio history.
- `app_fetcher/app/controllers/api/demo/item_prices_controller.rb` —
  dynamics, trend, and per-item history.
- `app_fetcher/app/queries/demo/dataset.rb` — `Demo::Dataset`, the
  read-only fixed-data assembly.
- `app_fetcher/app/queries/demo/inventory.rb` — `Demo::Inventory`, the
  fixed showcase loader.
- `app_fetcher/app/queries/demo/price_series.rb` — `Demo::PriceSeries`,
  the deterministic synthetic price generator.
- `app_fetcher/app/queries/demo/item_pool.rb` — `Demo::ItemPool`, the YAML pool
  loader.
- `app_fetcher/config/demo_items.yml` — the curated catalog pool: 40–50
  real, marketable CS2 entries, each with `market_hash_name`, `rarity`,
  `category`, and `icon_url`.
- `app_fetcher/config/demo_inventory.yml` — the fixed showcase: 30
  `market_hash_name` + `base_price_cents` entries, all drawn from the
  pool.
- `app_fetcher/lib/tasks/demo.rake` — `demo:seed_items`.
- Routes are explicit under `namespace :api do; namespace :demo do ...`
  in `config/routes.rb`.

`Demo::Dataset`, `Demo::Inventory`, `Demo::PriceSeries`, and
`Demo::ItemPool` are deliberately **not** `ApplicationService`s (they do
not return `ApplicationService::Result`) and not flat
`<Resource>ListQuery` endpoint query objects (they do not read a
persisted demo resource). They are demo-specific read collaborators in a
namespaced `app/queries/demo/` subfolder.

## Interface

`Api::Demo::BaseController`:

- `before_action :authenticate_demo_token!`;
- decodes with `APP_DEMO_JWT_SECRET`, `algorithm: "HS256"`;
- requires `payload["aud"] == "demo"` and an integer `seed`;
- sets `@demo_seed` for token traceability; the seed no longer selects
  demo data;
- exposes `demo_seed` and a memoized `demo_dataset`;
- `demo_dataset` → `Demo::Dataset.new`.

Endpoints and payloads:

- `GET /api/demo/inventories` → `InventorySerializer.call(demo_dataset.items)`,
  same shape as V1’s inventory skeleton.
- `GET /api/demo/inventory_summary` → one object shaped exactly like an
  entry from `InventoryListSerializer` (reuse its single-summary shaping
  or a shared summary serializer).
- `GET /api/demo/inventory_detail?period=&sort=&page=&per_page=` →
  `InventoryDetailSerializer.call(demo_dataset.details(params))`, same
  shape as the public detail endpoint.
- `GET /api/demo/inventory_values?period=...` →
  `InventoryValueSerializer.call(demo_dataset.value(period: params[:period]))`.
- `GET /api/demo/item_prices/dynamics` →
  `ItemPriceDynamicsSerializer.call(demo_dataset.priced_items, 0)`.
- `GET /api/demo/item_prices/trend` → `demo_dataset.trends`, a hash
  shaped like `ItemTrendCache#fetch_for`.
- `GET /api/demo/item_prices/:market_hash_name/history?period=...` →
  `ItemPriceHistorySerializer.call(demo_dataset.history(demo_dataset.item!(name), period: ...))`.

`Demo::Dataset`:

- `items` → `T::Array[Item]`, the fixed 30 in-memory items;
- `priced_items` → `T::Hash[String, Item]` for the dynamics serializer;
- `summary` → `InventoryListQuery::InventorySummary`;
- `value(period:)` → `InventoryValueQuery::InventoryValue`;
- `details(params)` → `InventoryDetailQuery::InventoryDetails`;
- `trends` → `T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]`;
- `item!(market_hash_name)` → a fixed item or `ActiveRecord::RecordNotFound`;
- `history(item, period:)` → `ItemPriceHistoryQuery::ItemPriceHistory`;
- `rarity_counts` → `T::Hash[RarityTier, Integer]`.

`Demo::Inventory`:

- `entries` → `T::Array[Entry]` with `market_hash_name` and
  `base_price_cents`;
- `market_hash_names` → `T::Array[String]`.

`Demo::PriceSeries`:

- built from `market_hash_name` + `current_price_cents` (the anchor);
- `points_for(range)` → `T::Array[Point]` for `24h`/`7d`/`30d`/`1y`/`all`;
- `trend` → five points ending at the anchor;
- `current_price_cents` / `change_24h_cents` → values derived from the
  same series.

`Demo::ItemPool`:

- `entries` → YAML entries with `market_hash_name`, `rarity`, `category`,
  and `icon_url`;
- `market_hash_names` → `T::Array[String]`.

`demo:seed_items`:

- reads `Demo::ItemPool.entries`, parses each entry with `ItemParser`
  (including `icon_url`), find-or-initializes by `market_hash_name`,
  persists metadata, and enqueues `PriceUpdateWorker` for each row;
- creates a new row with all parsed metadata;
- on an existing row, fills only absent/nil metadata keys and never
  overwrites a populated value.

## Responsibilities

`Api::Demo::` controllers parse params, call `demo_dataset`, and render
through the existing serializers. They do not generate prices/history,
query Steam, or call the real price caches. `Demo::Dataset` owns the
fixed in-memory item construction, anchor selection, snapshot/history/
detail assembly, in-memory sorting, rarity counting, and item-history/
trend projection. `Demo::Inventory` owns the showcase YAML only.
`Demo::PriceSeries` owns deterministic series generation for one item.
`Demo::ItemPool` owns the catalog-pool YAML only. `demo:seed_items` owns
turning pool entries into real `Item` rows (including their icons),
filling missing metadata on existing rows, and enqueueing the existing
price worker; it is not required for the demo dataset to render.

## Dependencies

`Demo::Dataset` may depend on:

- `Demo::ItemPool`, `Demo::Inventory`, and `Demo::PriceSeries`;
- `Item` (read-only lookup of real current prices as anchors only);
- `ItemParser` (to build metadata for in-memory items);
- `InventoryValueQuery` structs (`ValueSnapshot`, `ValueDelta`,
  `ValueHistory`, `InventoryValue`);
- `InventoryListQuery::InventorySummary` and
  `InventoryDetailQuery::InventoryDetails` structs;
- `Options::DateRange`, `Appliers::Pagination`,
  `Options::ItemSortOption`, and `RarityTier`.

`Demo::PriceSeries` may depend only on standard-library digest/random
facilities and its own point struct. `Demo::Inventory` may depend only on
its checked-in YAML. `demo:seed_items` may depend on `Demo::ItemPool`,
`ItemParser`, `Item`, and `PriceUpdateWorker`.

Must not depend on `app_core`, a `User`/`UserInventory` row, a Steam
identity, or the real `ItemPriceCache`/`ItemTrendCache`/
`PriceHistoryCache`/`ItemPriceHistoryQuery` for demo values.

## Rules

### MUST

- Authenticate every demo endpoint with `APP_DEMO_JWT_SECRET` and
  `aud: "demo"`; reject missing, malformed, expired, wrong-secret, and
  wrong-audience tokens with `401` / `{ message: "Invalid demo token" }`.
- Keep the demo namespace read-only: no `UserInventory`,
  `UserInventoryItem`, or `InventoryValueLog` writes.
- Serve one fixed `Demo::Inventory` showcase (30 entries) to every demo
  session. Do not vary item selection by `seed`; the token keeps `seed`
  for auth/traceability only.
- Keep every showcase name inside `Demo::ItemPool`; the inventory file
  supplies only `market_hash_name` + a positive `base_price_cents`
  fallback.
- Build demo items in memory from pool metadata (`ItemParser`) and use
  the real `Item#current_price_cents` only as an anchor when it is
  present and available; otherwise use the YAML base price. Never save
  these in-memory items.
- Generate the whole price story from one deterministic
  `Demo::PriceSeries` per item: current price = the last point,
  `change_24h_cents` = current − yesterday’s daily point, and the series
  ends at the anchor so current/history cannot jump.
- Make every history window cover the whole requested range the way the
  real endpoint does: daily points at `00:00 UTC` from `range.since_date`
  through yesterday, plus one live point at `Time.current` carrying the
  current value (the `InventoryValueQuery.history` cutoff-log + live-point
  shape). The `24h` window spans a full 24 hours inclusively
  (`now - 24h` through `now`). Do not slice “the last N points” as the
  window: N daily points span only N−1 days and leave the hero chart’s
  left edge empty.
- Compute portfolio history as the sum of the same item series at each
  date; the snapshot is the last portfolio point, complete with all
  items priced. Do not generate an independent portfolio walk.
- Mark the generated portfolio history complete and compute its delta
  from the previous point (or the same total when there is one point).
- Build `InventoryListQuery::InventorySummary` /
  `InventoryDetailQuery::InventoryDetails` and render through the
  existing serializers; do not invent a parallel demo response shape.
- Parse `period` through `Options::DateRange::Param`, sort the top-items
  list in memory using `Options::ItemSortOption` semantics, and page it
  with `Appliers::Pagination`, passing
  `Api::Demo::UnsupportedParamError` so the demo base controller renders
  `400`.
- Keep the checked-in pool at 40–50 unique, real, marketable CS2
  entries; every entry carries `market_hash_name`, `rarity`, `category`,
  and `icon_url`. Items are real catalog rows, never demo-flagged.
- Use only `RarityTier`-recognized `rarity` labels (`Consumer Grade`,
  `Industrial Grade`, `Mil-Spec Grade`, `Restricted`, `Classified`,
  `Covert`, `Extraordinary`, `Contraband`) and Steam inventory Type
  names for `category` (`Rifle`, `Sniper Rifle`, `Pistol`, `SMG`,
  `Shotgun`, `Machinegun`, `Knife`, `Gloves`). Knife and glove names
  keep their leading `★`, so `RarityTier.for` counts them as Gold.
- Give every entry a real Steam CDN `icon_url` in the
  `https://community.akamai.steamstatic.com/economy/image/...` form that
  `UserInventorySyncService` already stores. Icons are static
  checked-in metadata; do not fetch them during seeding or at runtime.
- Make `demo:seed_items` idempotent: find-or-initialize by
  `market_hash_name`; create new rows with the parsed metadata; on an
  existing row fill only absent/nil metadata keys and never overwrite a
  populated value; enqueue `PriceUpdateWorker` for the pool.
- Keep `config/demo_inventory.yml` at 30 unique entries and validate the
  inventory↔pool contract in specs; a broken fixed dataset is an
  implementation error, not a reason to fall back to random catalog
  items.
- Return item history from `Demo::PriceSeries`, never from
  `PriceHistoryCache`/`ItemPriceHistoryQuery`, and dynamics/trend from
  `Demo::Dataset`, never from `ItemPriceCache`/`ItemTrendCache`.
- Return `404` for an unknown item history via
  `Demo::Dataset#item!` raising `ActiveRecord::RecordNotFound`; the base
  controller renders the existing not-found shape.

### SHOULD

- Extract the reusable single-summary JSON shaping from
  `InventoryListSerializer` rather than duplicating its field list in the
  demo controller.
- Mirror the four `Options::ItemSortOption` semantics in Ruby for the
  in-memory `Demo::Dataset#details` list (`change_24h_desc`,
  `price_desc`, `price_asc`, `name_asc`), because synthetic prices cannot
  be sorted by SQL. Test all four against the same option enum.
- Keep the showcase broad but stable: cover all eight Steam Type
  categories and a mix of inexpensive skins, mid-tier skins, knives, and
  gloves. Update the inventory contract test only when intentionally
  changing the fixed list.

### MUST NOT

- Don’t put demo reads in `Api::Public::` (no caller identity) or
  `Api::V1::` (Steam identity/current_steam_id).
- Don’t add a `demo` claim to player/admin tokens or share their
  secrets.
- Don’t persist a demo inventory, demo value logs, or a fake `steam_id`.
- Don’t use `Rails.cache` for per-demo data; the existing caches are for
  shared item/price data only.
- Don’t write synthetic demo prices into `items`, `price_logs`, or
  `inventory_value_logs`; the generated series stays in memory.
- Don’t mix a real price into a synthetic history (or vice versa). The
  anchor is the only real input; every displayed point comes from
  `Demo::PriceSeries`, and the portfolio is the sum of those series.
- Don’t read `ItemPriceCache`/`ItemTrendCache`/`PriceHistoryCache`/
  `ItemPriceHistoryQuery` from the demo path.
- Don’t return a demo-specific response envelope that forces a fork of
  the dashboard/inventory React components.

## Error Handling

- Auth failures: `401`, `{ message: "Invalid demo token" }`.
- Unsupported `period`/`sort`: raise `Api::Demo::UnsupportedParamError`
  from `Demo::Dataset`; the base controller renders `400` with
  `{ message: exception.message }`.
- Unknown item in history: `Demo::Dataset#item!` raises
  `ActiveRecord::RecordNotFound`; the base controller renders `404` with
  `{ message: "Not found" }`.
- Unexpected failures: rescue `StandardError` at the base controller,
  log via `Rails.logger.error`, and render
  `{ message: "Internal error" }` / `500`.
- A broken showcase/pool file is an implementation error, not a data
  condition to degrade from: fail loudly and cover the contract in specs
  rather than silently substituting real catalog items.

## Data / Transactions

- No writes. This namespace is a pure read path.
- `demo:seed_items` is the only writer, and it writes ordinary `Item`
  rows plus enqueues `PriceUpdateWorker`; it does not create demo
  inventories or value logs.
- Redis/session TTL cleanup is owned by `app_core`’s
  `Demo::SessionStore`; the fetcher does not read or write demo session
  state.

## Testing

General RSpec mechanics live in `agent/styleguides/rspec-conventions.md`.
Demo-specific expectations:

- Request specs must cover missing/garbage/expired/wrong-audience tokens,
  a player token rejected by `/api/demo`, and a demo token rejected by
  `/api/v1`.
- Every demo inventory request spec must assert that no
  `UserInventory`/`UserInventoryItem` rows were created, and demo
  price/history requests must assert no `PriceLog` rows were created.
- Request specs cover the fixed showcase item set, generated dynamics/
  trend/item-history payloads, and the fixed item set’s consistency with
  the portfolio total.
- `Demo::Dataset` is a unit spec: the fixed 30-item set is identical
  across instances/seeds; real prices are used as anchors and YAML base
  prices as fallback; current price equals the last series point;
  portfolio history equals the sum of item series; the summary matches
  the portfolio snapshot; detail honors period/all four sorts/page;
  item history/trends come from the same series; rarity counts and the
  priciest item match the in-memory set.
- `Demo::Inventory` is an offline unit spec over the real checked-in
  YAML: 30 unique entries, every name is in `Demo::ItemPool`, positive
  integer base prices, and all eight Steam Type categories are covered.
- `Demo::PriceSeries` is a unit spec: deterministic for the same name/
  anchor, ends at the anchor, positive prices, the expected window
  lengths, five trend points, and different names vary for the same
  anchor.
- `Demo::ItemPool` is an offline unit spec over the real checked-in
  YAML: 40–50 entries, unique names, required keys, every entry has a
  Steam CDN `icon_url`, every `rarity` resolves through `RarityTier`,
  and every `category` is in the recognized Steam Type set. Make no
  network requests in these specs.
- `demo:seed_items` is a focused task spec: new rows get the icon and
  metadata, existing rows get only missing keys backfilled, populated
  values are preserved, repeated runs do not duplicate rows, and price
  updates are enqueued with `Sidekiq::Testing.fake!`.
- Serializer regression: the existing `InventoryListSerializer` list
  output is unchanged when the single-summary shaping is extracted.

## Canonical Implementations

- `app_fetcher/app/queries/demo/item_pool.rb` +
  `app_fetcher/config/demo_items.yml` — the curated pool and its loader.
- `app_fetcher/app/queries/demo/inventory.rb` +
  `app_fetcher/config/demo_inventory.yml` — the fixed showcase and its
  loader.
- `app_fetcher/app/queries/demo/price_series.rb` — the deterministic
  anchor-based price series and its whole-window slices (cutoff day
  through a live “now” point).
- `app_fetcher/lib/tasks/demo.rake` — icon pass-through and
  fill-only-missing seeding.
- `app_fetcher/app/queries/demo/dataset.rb` — in-memory fixed items,
  series-derived portfolio (summed window plus live point),
  summary/detail/history/trend assembly.

## Related ADR

`agent/adr/fetcher/demo-api.md`
