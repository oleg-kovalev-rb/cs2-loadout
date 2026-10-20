---
description: app_fetcher demo API conventions — the read-only Api::Demo:: namespace, demo-token auth, Demo::Dataset/Demo::ItemPool, deterministic seed-based generation, the YAML item pool and seed task, and no-demo-writes testing rules.
---

# Demo API (`app_fetcher`)

See `agent/adr/fetcher/demo-api.md` for why demo reads get a separate
namespace and a generated dataset instead of persisted demo rows. This
file covers how that namespace and its collaborators are written.

## Purpose

Serve the demo dashboard and demo inventory page from real `Item` /
`PriceLog` data without a Steam identity and without persisting a demo
inventory. What belongs here: demo-token auth, demo response assembly,
deterministic item selection, synthetic portfolio history, and the item
pool/seed task. What does not: demo session/cookie/JWT ownership (that is
`app_core`’s `core/demo-mode.md`), Steam ingestion, or any demo writes to
`UserInventory`/`InventoryValueLog`.

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
- `app_fetcher/app/queries/demo/dataset.rb` — `Demo::Dataset`, the read-only
  generated read model.
- `app_fetcher/app/queries/demo/item_pool.rb` — `Demo::ItemPool`, the YAML pool
  loader.
- `app_fetcher/config/demo_items.yml` — the curated pool (a placeholder
  set is acceptable for the first implementation; curation is a
  follow-up).
- `app_fetcher/lib/tasks/demo.rake` — `demo:seed_items`.
- Routes are explicit under `namespace :api do; namespace :demo do ...`
  in `config/routes.rb`.

`Demo::Dataset`/`Demo::ItemPool` are deliberately **not**
`ApplicationService`s (they do not return
`ApplicationService::Result`) and not flat `<Resource>ListQuery`
endpoint query objects (they do not read a persisted demo resource).
They are demo-specific read collaborators in a namespaced
`app/queries/demo/` subfolder.

## Interface

`Api::Demo::BaseController`:

- `before_action :authenticate_demo_token!`;
- decodes with `APP_DEMO_JWT_SECRET`, `algorithm: "HS256"`;
- requires `payload["aud"] == "demo"` and an integer `seed`;
- sets `@demo_seed`;
- exposes `demo_seed` and a memoized `demo_dataset`;
- `demo_dataset` → `Demo::Dataset.new(seed: demo_seed)`.

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
  `ItemPriceDynamicsSerializer.call(priced_items, 0)` where the names
  come from `demo_dataset.items`.
- `GET /api/demo/item_prices/trend` →
  `ItemTrendCache.fetch_for(demo_dataset.items.map(&:market_hash_name))`.
- `GET /api/demo/item_prices/:market_hash_name/history?period=...` →
  the same 30-day cache/history-query branch as V1, with no identity.

`Demo::Dataset`:

- `items` → `T::Array[Item]`, at most 20, deterministic for a seed;
- `summary` → `InventoryListQuery::InventorySummary`;
- `value(period:)` → `InventoryValueQuery::InventoryValue`;
- `details(params)` → `InventoryDetailQuery::InventoryDetails`;
- `rarity_counts` → `T::Hash[RarityTier, Integer]`.

`Demo::ItemPool`:

- `entries` → YAML entries with `market_hash_name`, `rarity`, `category`;
- `market_hash_names` → `T::Array[String]`.

## Responsibilities

`Api::Demo::` controllers parse params, call `demo_dataset`, and render
through the existing serializers. They do not sample items, generate
history, or query Steam. `Demo::Dataset` owns item selection, snapshot/
history/detail assembly, rarity counting, and fallback behavior.
`Demo::ItemPool` owns YAML loading only. `demo:seed_items` owns turning
pool entries into real `Item` rows and enqueueing the existing price
worker.

## Dependencies

`Demo::Dataset` may depend on:

- `Item` (read-only queries/scopes);
- `ItemPriceCache`, `ItemTrendCache`, `PriceHistoryCache` for real
  market data;
- `InventoryValueQuery` structs (`ValueSnapshot`, `ValueDelta`,
  `ValueHistory`, `InventoryValue`);
- `InventoryListQuery::InventorySummary` and
  `InventoryDetailQuery::InventoryDetails` structs;
- `Options::DateRange`, `Appliers::Pagination`, `Appliers::SortApplier`,
  `Options::ItemSortOption`, and `RarityTier`.

`demo:seed_items` may depend on `Demo::ItemPool`, `ItemParser`, `Item`,
and `PriceUpdateWorker`.

Must not depend on `app_core`, a `User`/`UserInventory` row, or a
Steam identity.

## Rules

### MUST

- Authenticate every demo endpoint with `APP_DEMO_JWT_SECRET` and
  `aud: "demo"`; reject missing, malformed, expired, wrong-secret, and
  wrong-audience tokens with `401` / `{ message: "Invalid demo token" }`.
- Keep the demo namespace read-only: no `UserInventory`,
  `UserInventoryItem`, or `InventoryValueLog` writes.
- Select items deterministically from the seed: use a fresh
  `Random.new(seed)` for each computation so repeated `items`/`value`
  calls produce the same result.
- Cap the demo inventory at 20 items. If the pool is incomplete or
  unpriced, fall back to other priced/marketable `Item` rows rather than
  returning an empty/500 demo.
- Use real `Item` prices, real `ItemTrendCache` trends, and real
  `PriceLog`-based item history. Only the demo inventory composition and
  portfolio history are synthetic.
- Make the generated portfolio history end at the current total and mark
  its points complete; compute the delta from the previous point (or the
  same current total when there is only one point).
- Build `InventoryListQuery::InventorySummary` /
  `InventoryDetailQuery::InventoryDetails` and render through the
  existing serializers; do not invent a parallel demo response shape.
- Reuse `Options::DateRange::Param` for `period`, `Appliers::SortApplier`
  for `sort`, and `Appliers::Pagination` for the top-items sub-list,
  passing `Api::Demo::UnsupportedParamError` so the demo base controller
  renders `400`.
- Keep the YAML pool entries limited to `market_hash_name`, `rarity`, and
  `category` (optional `icon_url`); items are real catalog rows, never
  demo-flagged.
- Make `demo:seed_items` idempotent: find-or-initialize by
  `market_hash_name`, do not overwrite existing metadata, and enqueue
  `PriceUpdateWorker` for the pool.
- Return `404` for an unknown item history via a bang finder and the
  base controller’s `ActiveRecord::RecordNotFound` handler.

### SHOULD

- Extract the reusable single-summary JSON shaping from
  `InventoryListSerializer` rather than duplicating its field list in the
  demo controller.
- Keep `Demo::Dataset#details`’s sort/pagination on an ActiveRecord
  relation (`Item.where(id: ...)`) so the existing appliers behave
  exactly as they do for public inventories.
- Keep the placeholder pool small but valid; the follow-up curates the
  full 40–50 item set.

### MUST NOT

- Don’t put demo reads in `Api::Public::` (no caller identity) or
  `Api::V1::` (Steam identity/current_steam_id).
- Don’t add a `demo` claim to player/admin tokens or share their
  secrets.
- Don’t persist a demo inventory, demo value logs, or a fake `steam_id`.
- Don’t use `Rails.cache` for per-demo data; the existing caches are for
  shared item/price data only.
- Don’t generate fake item prices or fake `PriceLog` rows; the demo uses
  the real market data it already has.
- Don’t return a demo-specific response envelope that forces a fork of
  the dashboard/inventory React components.

## Error Handling

- Auth failures: `401`, `{ message: "Invalid demo token" }`.
- Unsupported `period`/`sort`: raise `Api::Demo::UnsupportedParamError`
  from the dataset/appliers; the base controller renders `400` with
  `{ message: exception.message }`.
- Unknown item in history: `Item.find_by!` raises
  `ActiveRecord::RecordNotFound`; the base controller renders `404` with
  `{ message: "Not found" }`.
- Unexpected failures: rescue `StandardError` at the base controller,
  log via `Rails.logger.error`, and render
  `{ message: "Internal error" }` / `500`.
- An empty/unpriced catalog is a data condition, not an exception: the
  dataset falls back and the existing serializers/UI handle zero/partial
  data.

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
  `UserInventory`/`UserInventoryItem` rows were created.
- `Demo::Dataset` is a unit spec: same seed → same selection/history;
  different seed generally differs; selection caps at 20; fallback works
  when the pool is empty/unpriced; history ends at the current total;
  rarity counts match; detail honors period/sort/page.
- `Demo::ItemPool` is a unit spec for YAML loading/names.
- `demo:seed_items` may be verified manually or with a focused task spec;
  at minimum verify it is idempotent and enqueues price updates with
  `Sidekiq::Testing.fake!`.
- Serializer regression: the existing `InventoryListSerializer` list
  output is unchanged when the single-summary shaping is extracted.

## Canonical Implementations

None yet — this plan creates the first implementation. The expected
files are listed in `agent/plans/demo-account.md`.

## Related ADR

`agent/adr/fetcher/demo-api.md`
