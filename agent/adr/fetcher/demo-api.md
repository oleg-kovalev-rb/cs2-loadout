# A Separate Read-Only `Api::Demo::` Namespace and a Generated Demo Dataset

## Status

Accepted

## Context

`app_fetcher` exposes three API families today:

- `Api::V1::` — caller-scoped, Steam-bridge-token authenticated, derives
  the caller’s identity from `current_steam_id`;
- `Api::Public::` — genuinely public, no caller identity at all;
- `Api::Admin::` — admin-bridge-token authenticated.

Demo mode needs a fourth kind of caller: a browser that has a temporary
demo session, but no Steam identity. Its reads are caller-scoped (they
depend on the demo seed and must not be shared across visitors), so they
do not belong in `Api::Public::`. They do not have a `steam_id`, so
`Api::V1::`’s `current_steam_id` model does not fit. They are not admin
reads.

The inventory data itself is stored by `steam_id` in `UserInventory`.
Persisting a demo inventory row would make it visible to
`InventoryListQuery`, the sync scheduler, and the value scheduler, and
would require `no_demo` scopes across unrelated code. The demo should
therefore read real `Item`/`PriceLog` rows and generate its inventory
view on demand.

## Decision

Add a separate **`Api::Demo::`** namespace in `app_fetcher`, read-only,
with its own base controller and its own bearer-token verification:

- Tokens are signed with `APP_DEMO_JWT_SECRET`, carry `aud: "demo"`, and
  carry an integer `seed` (plus the `demo_id` for traceability). They are
  rejected by every other namespace, and every other namespace’s tokens
  are rejected here.
- The namespace exposes the seven read endpoints the demo dashboard and
  demo inventory page need: inventory skeleton, inventory summary,
  inventory detail, portfolio values, item dynamics, item trend, and
  per-item history.
- A new **`Demo::Dataset`** read model in `app_fetcher/app/queries/demo/` owns
  deterministic item selection and generated data. It samples up to 20
  items from `config/demo_items.yml` using `Random.new(seed)`, falls back
  to any priced/marketable catalog items if the pool is incomplete, and
  builds the existing `InventoryListQuery::InventorySummary` /
  `InventoryDetailQuery::InventoryDetails` structs so the existing
  serializers and React components can be reused unchanged.
- A new **`Demo::ItemPool`** in `app_fetcher/app/queries/demo/` loads the YAML
  pool and exposes its entries/names. The pool is a curated list of real
  market item names, not a second inventory store.
- `demo:seed_items` creates/finds the pool’s real `Item` rows through
  the existing `ItemParser`, then enqueues the existing
  `PriceUpdateWorker` so prices come from the existing Steam
  `priceoverview` pipeline. Seeded items are ordinary `marketable`
  catalog rows; they carry no demo flag.
- Real prices, trends, and per-item history come from the existing
  `ItemPriceCache` / `ItemTrendCache` / `PriceHistoryCache` /
  `ItemPriceHistoryQuery`. Only the demo inventory composition and the
  portfolio value history are synthetic.
- No demo writes: no `UserInventory`, `UserInventoryItem`, or
  `InventoryValueLog` rows. The only persistent demo state is the
  `app_core` Redis session.

## Alternatives Considered

### Alternative: reuse `Api::V1::` with a `demo` claim

Rejected because:

- `Api::V1::` is built around `current_steam_id`; every action and cache
  key would need a demo branch.
- A shared token secret and a claim-based branch reintroduce exactly the
  conditional auth posture the project rejected when it introduced
  `Api::Public::`/`Api::Admin::` as separate namespaces.

### Alternative: serve demo data from `Api::Public::`

Rejected because:

- Public endpoints have no caller identity; a demo response depends on
  the caller’s seed.
- Putting demo identity into the public namespace would violate its
  “no notion of caller identity” rule.

### Alternative: persist a demo `UserInventory`

Rejected because:

- It would appear in the public inventory list, rankings, and
  `total_count`.
- `UserInventorySyncScheduler` would try to sync a non-Steam id and
  `InventoryValueScheduler` would write demo value logs.
- It requires `demo`/`no_demo` scopes across unrelated queries and a
  cleanup job.

### Alternative: separate demo tables/read path

Rejected because:

- It duplicates the inventory/price read path and requires migrations
  for a disposable feature.
- Reusing the existing `Item` catalog and serializers is cheaper and
  keeps demo data in the same real-price world as the rest of the app.

### Alternative: store the generated dataset in Redis

Rejected because:

- The seed already makes the selection deterministic; storing a full
  dataset adds serialization/versioning for little benefit.
- Live prices are desirable in a demo, and the only state that needs a
  TTL is the demo session itself.

### Alternative: an admin-panel data generator

Rejected for this feature because:

- Demo mode is for visitors, not for development fixture management.
- A generator UI is more code and does not solve the “no demo rows”
  isolation problem.

## Consequences

### Positive

- Demo data is isolated by construction; no public-list, scheduler, or
  domain-model changes.
- The dashboard and inventory UI can reuse the existing serializers and
  React components.
- The demo API can be tested deterministically from a seed without
  writing rows.
- Seeded items still enrich the real catalog and the public Tracked Items
  page.

### Negative

- A fourth API namespace and base controller duplicate the existing
  auth/error shape.
- The demo dataset is generated data, not a frozen snapshot; item
  prices and trends can change during the 12-hour session.
- The curated pool and seed task are additional maintenance.
- Some demo items may be unpriced or missing until `demo:seed_items`
  and the price worker have run.

### Risks

- An empty or unpriced catalog could produce an empty demo; the dataset
  must fall back gracefully.
- Reusing `InventoryDetailSerializer` requires building a complete
  `InventoryDetailQuery::InventoryDetails`; a missing field breaks the
  demo detail page.
- A demo token embedded in a page could be replayed if demo HTML is
  shared-cached; the app_core side must send `no-store`.
- The fourth namespace could drift from V1/Public conventions; keep the
  same explicit render/error shapes and test crossover rejection.

## Implementation Constraints

- `Api::Demo::` lives under `app/controllers/api/demo/`, with its own
  `BaseController < ::ApplicationController`, `before_action` auth, and
  `rescue_from` handlers.
- Token verification uses `APP_DEMO_JWT_SECRET`, requires
  `aud == "demo"`, and requires an integer `seed`. Missing/invalid
  tokens return `401` with `{ message: "Invalid demo token" }`.
- `Demo::Dataset` and `Demo::ItemPool` live under `app/queries/demo/`; they are
  read-only demo collaborators, not `ApplicationService`s and not
  `app/queries/` endpoint query objects.
- The dataset selects up to 20 items from the YAML pool, deterministically
  by seed, with a fallback to priced/marketable catalog items.
- Generated portfolio history must end at the current total and be
  marked complete; real item prices/trends/history must be used as-is.
- `config/demo_items.yml` entries have `market_hash_name`, `rarity`, and
  `category`; `icon_url` is optional.
- `demo:seed_items` is idempotent, does not overwrite existing item
  metadata, and enqueues `PriceUpdateWorker` for the pool.
- No demo writes to `UserInventory`, `UserInventoryItem`, or
  `InventoryValueLog`.

## Related

- `agent/styleguides/fetcher/demo-api.md` — the concrete app_fetcher
  conventions this decision backs.
- `agent/adr/core/demo-mode.md` — the app_core session/token/UI side of
  the same feature.
- `agent/adr/fetcher/public-api-namespace.md` — the precedent for a
  structurally separate namespace instead of a conditional auth flag.
- `agent/styleguides/fetcher/public-api-controllers.md` and
  `agent/styleguides/fetcher/internal-api-controllers.md` — the response
  and error-shape conventions the demo namespace follows.
