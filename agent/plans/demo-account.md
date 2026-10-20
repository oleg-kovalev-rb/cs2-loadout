---
status: implemented
app: fetcher+core
goal: Add a 12-hour, read-only demo mode for signed-out visitors — a Redis-backed demo session, generated demo inventory/dashboard data, a demo badge, and a demo inventory card shown first on the public inventories page
created: 2026-10-20
---

# Development Plan

## Goal

Let a signed-out visitor start a throwaway demo account from the sign-in
screen and immediately see a populated dashboard and inventory without a
Steam login. The demo lives for 12 hours in Redis, produces no persistent
demo rows in either app's domain tables, and reuses the existing
dashboard/inventory React islands and `app_fetcher` query/serializer
shapes.

## Expected Behavior

### Starting and ending a demo

- The signed-out dashboard shows a second CTA, “Try a demo account”,
  next to “Sign in through Steam”.
- `POST /demo_session`:
  - creates a demo session with a random `id`, `seed`, and `created_at`;
  - stores it in Redis as `demo:session:<id>` with a 12-hour TTL;
  - stores `<id>` in an encrypted, HttpOnly, SameSite=Lax cookie that
    also expires in 12 hours;
  - redirects to `/`.
- `DELETE /demo_session` deletes the Redis key and the cookie, then
  redirects to `/`.
- If Redis is unavailable, starting a demo redirects back with an alert;
  an existing demo cookie whose Redis key is gone is treated as expired
  and cleared on the next request.
- A demo session never creates a `User`, `UserInventory`,
  `UserInventoryItem`, or `InventoryValueLog` row.

### Demo dashboard

- `GET /` with a valid demo session renders the same dashboard island as a
  logged-in user, but the page carries `data-demo="true"` and a demo
  bearer token.
- The React island chooses `apiBase=/api/demo` when `data-demo` is true
  and `apiBase=/api/v1` otherwise; `DashboardsController` itself contains
  no user-vs-demo branching.
- The dashboard shows:
  - a generated inventory of up to 20 real `Item` rows;
  - real current prices and 24h changes for those items;
  - real 7-day item trends and per-item price history;
  - a generated portfolio-value history for the selected period.
- Demo data is derived deterministically from `seed` + the current
  `Item`/`PriceLog` rows. The selected item set and generated history are
  not stored.
- The topbar shows a “My account” profile chip with a “Demo” badge and
  an “Exit demo” control on every page while the demo session is active.

### Demo inventory on the public inventories page

- `GET /inventories` remains a public, real-data page. In demo mode it
  additionally fetches `GET /api/demo/inventory_summary` with the demo
  token and renders one demo card as the first, sticky card inside the
  public grid.
- The demo card:
  - is the first, sticky card in the grid, outside the public grid’s
    pagination and ranking;
  - shows the “Demo” badge;
  - links to `/demo/inventory`, not `/inventories/:steam_id`;
  - does not change `meta.total_count`, page ranks, or the public list
    response.
- The public inventory list, sort, pagination, and profile enrichment are
  unchanged.
- A real public inventory detail page (`/inventories/:steam_id`) opened
  while in demo mode still uses the real public API; only
  `/demo/inventory` uses the demo API.

### Demo inventory detail

- `GET /demo/inventory` redirects to `/` when there is no demo session.
- With a demo session it renders the existing inventory-detail island
  with `data-demo-inventory="true"` and the nickname “My account”.
- The island calls `GET /api/demo/inventory_detail` with the demo token
  and renders the same portfolio, stats, rarity, and top-item UI as the
  public inventory page.
- It supports the same `period`, `sort`, `page`, and `per_page` query
  parameters as the public detail endpoint.
- The public `/inventories/:steam_id` detail page remains unchanged.

### Demo API

New `Api::Demo::` namespace in `app_fetcher`, authenticated by a separate
`APP_DEMO_JWT_SECRET` and a token whose claims include
`demo_id`, `seed`, `aud: "demo"`, `iat`, and `exp`:

- `GET /api/demo/inventories` — dashboard inventory skeleton, same shape
  as `Api::V1::InventoriesController#show`.
- `GET /api/demo/inventory_values?period=...` — portfolio history, same
  shape as `Api::V1::InventoryValuesController#index`.
- `GET /api/demo/item_prices/dynamics` — current prices for the demo
  inventory, same shape as V1 dynamics.
- `GET /api/demo/item_prices/trend` — 7-day trends for the demo
  inventory, same shape as V1 trend.
- `GET /api/demo/item_prices/:market_hash_name/history?period=...` —
  real market price history for one item.
- `GET /api/demo/inventory_summary` — one summary object with the same
  fields as an entry in `Api::Public::InventoriesController#index`.
- `GET /api/demo/inventory_detail?period=&sort=&page=&per_page=` — the
  same payload shape as `Api::Public::InventoriesController#show`.

Missing, malformed, expired, or wrong-audience tokens return `401` with
`{ "message": "Invalid demo token" }`. Demo tokens must not be accepted
by `Api::V1::`, `Api::Public::`, or `Api::Admin::` endpoints, and player
or admin tokens must not be accepted by `Api::Demo::`.

### Item pool and seeding

- A checked-in YAML file lists the demo item pool. For this task it
  contains a small placeholder set (enough to exercise selection and
  fallback); curating the full 40–50 item pool is a follow-up task.
- Each entry has `market_hash_name`, `rarity`, and `category`; an
  optional `icon_url` may be added later.
- `demo:seed_items` creates or finds the corresponding real `Item` rows,
  fills metadata from `ItemParser`, and enqueues the existing
  `PriceUpdateWorker` so prices come from the existing Steam
  `priceoverview` pipeline.
- Seeded items are ordinary `marketable` catalog rows. They may appear in
  the public item catalog / Tracked Items page; they carry no demo flag.
- If the pool is empty or some pool items are missing/unpriced, the demo
  dataset falls back to any available priced, marketable `Item` rows so
  the demo still renders.

### Unchanged

- Steam login flow, `User` model, player/admin bridge tokens, and all
  existing `Api::V1::`, `Api::Public::`, and `Api::Admin::` behavior.
- Public inventory list/detail pagination, sorting, caching, and response
  shapes.
- `InventoryValueScheduler`, `UserInventorySyncScheduler`, and
  `InventoryListQuery` are not changed and never see demo data.
- No database migrations.

## Scope

### In Scope

- Redis-backed demo session store, persistent demo cookie, demo JWT, and
  12-hour expiry.
- Demo session start/stop endpoints and routes.
- `current_demo` / `demo_bridge_token` helpers and layout-level demo flag
  and token.
- Demo mode on the existing dashboard and inventories React islands,
  including the shared `apiBase` refactor for dashboard hooks.
- Demo badge in the shared topbar, on the demo inventory card, and on the
  demo inventory detail header.
- Demo summary card first on `/inventories`, fetched separately from the
  public list.
- `/demo/inventory` page reusing the inventory-detail island.
- New `Api::Demo::` namespace with the seven demo endpoints, demo-token
  auth, and error handling.
- `Demo::Dataset` read model, `Demo::ItemPool` loader, placeholder YAML
  pool, and `demo:seed_items` rake task.
- Environment/config updates: `APP_DEMO_JWT_SECRET`, `REDIS_URL_DEMO`,
  `redis`/`connection_pool` gems in `app_core`, CI values.
- RSpec and Vitest coverage for the behavior above.
- Documentation updates required by `styleguides-check` (likely a new
  demo-mode ADR/styleguide and architecture-layer updates).

### Out of Scope

- Curating the full 40–50 item pool and its real icon metadata.
- Admin-panel data generation for users/inventories/items.
- Persisting demo inventories, demo users, or demo value logs in Postgres.
- `demo` flags/`no_demo` scopes on domain models.
- Fake `steam_id` values or a `DemoUser` model.
- A public demo inventory page, demo accounts seeing each other, or demo
  data entering `/api/public/inventories`.
- Shareable demo links, demo analytics, rate limiting, or a countdown
  timer beyond the 12-hour expiry behavior.
- Showing a signed-in user’s own inventory first on `/inventories`; only
  the demo card is in scope.
- Caching generated demo datasets in Redis beyond the session record.

## Applicable Styleguides

- `agent/adr/core/demo-mode.md` — the demo session/token/layout decision
  the app_core implementation follows.
- `agent/adr/fetcher/demo-api.md` — the separate read-only demo API and
  generated-dataset decision the app_fetcher implementation follows.
- `agent/styleguides/rails-layering.md` — keeps demo controllers thin,
  routes session/token work through `app/actions/demo/` and
  `lib/demo/`, and keeps demo generation out of app_core.
- `agent/styleguides/ruby-sorbet.md` — `# typed: strict`, `sig`s,
  `T.let` constants, typed collections, and the new Redis RBI/shim
  expectations for `Demo::SessionStore`/`Demo::BridgeToken`/
  `Demo::Dataset`.
- `agent/styleguides/rspec-conventions.md` — unit vs request spec levels,
  FactoryBot usage, real-Redis testing for a class that writes Redis
  directly, and the VCR/WebMock rules for any Steam-adjacent spec.
- `agent/styleguides/ci-and-coverage.md` — where the new
  `APP_DEMO_JWT_SECRET`/`REDIS_URL_DEMO` values and the full test
  commands run.
- `agent/styleguides/core/demo-mode.md` — the app_core session store,
  cookie, JWT, `current_demo`/`demo_bridge_token`, layout state, demo
  badge/card/detail, TTL, Redis failure handling, and public-page rules.
- `agent/styleguides/core/architecture-layers.md` — where the demo mode
  sits relative to the Steam/User, Admin, and Public stacks; confirms
  `DashboardsController` stays demo-free and demo reads go directly to
  `app_fetcher`.
- `agent/styleguides/core/react-dashboard.md` — `apiBase`/token plumbing,
  demo card outside public pagination, `/demo/inventory` mount flag,
  reuse of `InventoryCard`/`InventoryDetail`, and demo-mode Vitest
  coverage.
- `agent/styleguides/fetcher/demo-api.md` — `Api::Demo::` auth and error
  shapes, `Demo::Dataset`/`Demo::ItemPool` placement and generation
  rules, serializer/query-struct reuse, and no-demo-writes testing.
- `agent/styleguides/fetcher/internal-api-controllers.md` — the
  explicit render/error-shape conventions the demo controllers reuse.
- `agent/styleguides/fetcher/public-api-controllers.md` — the public
  list/detail response shapes the demo summary/detail must match.
- `agent/styleguides/fetcher/list-query-objects.md` — reuse of
  `InventoryListQuery::InventorySummary`,
  `InventoryDetailQuery::InventoryDetails`, `Appliers::*`, and
  `Options::*` in `Demo::Dataset`.
- `agent/styleguides/fetcher/caching.md` — the existing
  `ItemPriceCache`/`ItemTrendCache`/`PriceHistoryCache` classes used for
  real demo prices/trends.
- `agent/styleguides/fetcher/background-jobs.md` — the
  `PriceUpdateWorker` enqueue in `demo:seed_items`.
- `agent/styleguides/fetcher/architecture-layers.md` — the `app/queries/demo/`
  read-model placement and `demo:seed_items` writer boundary.

## Implementation Approach

Keep demo state at the edges and keep demo data out of domain tables.

- `app_core` owns demo identity: Redis session, encrypted cookie, demo
  JWT, and the global `current_demo` helper. The layout exposes a boolean
  and the demo token to the React islands, so controllers do not branch
  on “user vs demo”. The frontend chooses `/api/demo` vs `/api/v1` from
  the boolean.
- `app_fetcher` owns demo reads: a new `Api::Demo::` namespace and a
  `Demo::Dataset` that samples real `Item` rows and builds the existing
  query-result structs/serializer payloads. No demo writes.
- Reuse the existing public/dashboard serializers and React components
  rather than creating demo-specific response shapes or UI. The demo
  card and detail reuse `InventoryCard` and `InventoryDetail` with small,
  optional props.
- The item pool is a code/config artifact; only real `Item` rows are
  persisted. The demo selection is deterministic from `seed`, so no demo
  inventory snapshot is stored.

## Files To Modify

### `app_core`

- `app_core/Gemfile` — add `redis` (~> 5.0) and `connection_pool`.
- `app_core/Gemfile.lock` — regenerate.
- `app_core/app/controllers/application_controller.rb` — add
  `current_demo`, `demo_bridge_token`, and their `helper_method`
  declarations; keep the existing `current_user` behavior. Catch
  `Redis::BaseError` and degrade to no demo.
- `app_core/app/controllers/dashboards_controller.rb` — no demo logic
  added; verify it remains only the player-token path.
- `app_core/app/views/layouts/application.html.erb` — add
  `data-demo`/`data-demo-token` to `<body>`, populated from the helpers.
- `app_core/app/views/dashboards/show.html.erb` — render the dashboard
  island when `current_user || current_demo`; add the “Try a demo
  account” button to the signed-out stage; keep the Steam CTA.
- `app_core/app/views/shared/_topbar.html.erb` — add the demo profile
  chip, “Demo” badge, and “Exit demo” control; keep the existing
  signed-in/signed-out branches.
- `app_core/config/routes.rb` — add `resource :demo_session` and
  `get "demo/inventory"`.
- `app_core/app/frontend/entrypoints/dashboard.jsx` — read the body demo
  flag/token, choose `apiBase` and token, pass `demo` to `Dashboard`.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — accept `apiBase` and
  `demo`; pass `apiBase` to all five data hooks.
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js`,
  `useItemPrices.js`, `useItemTrend.js`, `usePortfolioHistory.js`,
  `useItemHistory.js` — build URLs from `fetcherUrl + apiBase` instead of
  hardcoded `/api/v1`.
- `app_core/app/frontend/entrypoints/inventories-index.jsx` — read the
  body demo flag/token and pass `demo`/`demoToken` to `InventoriesIndex`.
- `app_core/app/frontend/inventories/InventoriesIndex.jsx` — add demo
  props; fetch the demo summary; render the demo card as the first,
  sticky card inside the public grid; leave the public list/sort/
  pagination untouched.
- `app_core/app/frontend/inventories/hooks/useInventoryCatalog.js` —
  export the existing `mapInventory` mapper for reuse.
- `app_core/app/frontend/inventories/components/InventoryCard.jsx` —
  support optional `badge`, `href`, and nullable `rank`; keep existing
  behavior when those props are absent.
- `app_core/app/frontend/entrypoints/inventory-detail.jsx` — detect the
  demo-inventory mount flag, choose the demo endpoint/token, and pass
  `demo`/`apiBase`/`demoToken` to `InventoryDetail`. Public inventory
  detail must continue using the public endpoint.
- `app_core/app/frontend/inventories/InventoryDetail.jsx` — accept
  `demo`/`apiBase`/`demoToken`; show “Demo inventory” and the badge in
  demo mode; keep the public header otherwise.
- `app_core/app/frontend/inventories/hooks/useInventoryDetail.js` —
  accept demo props and build either
  `/api/demo/inventory_detail` or `/api/public/inventories/:steam_id`;
  attach the demo bearer token only for demo.
- `app_core/app/frontend/shared/styles/tokens.css` — add the shared
  `.badge-demo` style and demo profile-chip spacing.
- `app_core/app/frontend/inventories/styles/inventories.css` — add
  demo-card/demo-section styling.
- `app_core/spec/requests/dashboards_spec.rb` — add demo-mode rendering
  coverage; keep signed-in/out coverage.
- `app_core/spec/requests/inventories_spec.rb` — add demo-mode body
  flag/token and topbar badge coverage; assert public detail stays
  public.
- `app_core/spec/lib/steam/bridge_token_spec.rb` or a new demo token
  spec — follow the existing token spec pattern.
- `app_core/config/environments/test.rb` — only if needed to provide a
  test-safe Redis URL; prefer the compose/env value.
- `app_core/spec/rails_helper.rb` — only if a shared demo-Redis cleanup
  helper is added.
- `app_core/spec/support/` — add a demo-Redis helper only if more than
  one spec file needs the same flush/setup.

### `app_fetcher`

- `app_fetcher/config/routes.rb` — add the `api/demo` namespace with the
  seven explicit routes.
- `app_fetcher/config/application.rb` — no change expected; verify
  `app/queries/demo` autoload.
- `app_fetcher/app/serializers/inventory_list_serializer.rb` — make the
  single-summary JSON method reusable (public or extracted to a small
  shared serializer) for `inventory_summary`; preserve the existing list
  output exactly.
- `app_fetcher/spec/requests/api/public/inventories_spec.rb` — only if
  the serializer refactor changes its contract (it must not); add a
  regression assertion if useful.
- `app_fetcher/spec/serializers/inventory_list_serializer_spec.rb` —
  cover the reusable single-summary shape.
- `app_fetcher/spec/factories/items.rb` — no new factory needed; use
  existing `:item` with explicit metadata/price traits.

### Root/config

- `.env.example` — document `APP_DEMO_JWT_SECRET` as a distinct secret
  from `APP_BRIDGE_JWT_SECRET`/`APP_ADMIN_BRIDGE_JWT_SECRET`.
- `docker-compose.yml` — pass `APP_DEMO_JWT_SECRET` to `app_core` and
  `app_fetcher`; add `REDIS_URL_DEMO: redis://redis:6379/3` to
  `app_core`.
- `.github/workflows/ci.yml` — add a dummy
  `APP_DEMO_JWT_SECRET: ci-demo-secret-not-real`.
- `agent/styleguides/core/architecture-layers.md` — document the demo
  stack (session store, demo token, layout demos flag, `Api::Demo::`
  reads, demo card/detail).
- `agent/styleguides/fetcher/architecture-layers.md` — document the
  `Api::Demo::` namespace and `Demo::Dataset`/`Demo::ItemPool` read path.
- Additional styleguide/ADR files as required by `styleguides-check`.

## Files To Create

### `app_core`

- `app_core/config/initializers/redis.rb` — `DEMO_REDIS_POOL`, a
  `ConnectionPool` of `Redis` clients using
  `REDIS_URL_DEMO` (fallback `redis://localhost:6379/3`).
- `app_core/lib/demo/session_store.rb` — `Demo::SessionStore` with a
  `Session` struct (`id`, `seed`, `created_at`), `create`, `find`,
  `remaining_seconds`, and `delete`; 12-hour TTL; JSON serialization.
- `app_core/lib/demo/bridge_token.rb` — `Demo::BridgeToken` with
  `ALGORITHM`, `AUDIENCE = "demo"`, and `encode(session)`; uses
  `APP_DEMO_JWT_SECRET`; `exp` is `created_at + 12 hours`.
- `app_core/app/actions/demo/start.rb` — thin `Demo::Start.call`
  wrapper around `SessionStore.create`.
- `app_core/app/actions/demo/stop.rb` — thin `Demo::Stop.call(id)`
  wrapper around `SessionStore.delete`.
- `app_core/app/controllers/demo_sessions_controller.rb` — create/destroy
  actions, cookie handling, Redis failure handling, redirects.
- `app_core/app/controllers/demo/inventories_controller.rb` — render the
  demo inventory detail page; redirect when no demo session.
- `app_core/app/views/demo/inventories/show.html.erb` — the demo
  inventory-detail mount page with `data-demo-inventory="true"` and the
  “My account” nickname.
- `app_core/app/frontend/inventories/hooks/useDemoInventory.js` — fetch
  `/api/demo/inventory_summary` with the demo token; non-fatal, returns
  no card on failure.
- `app_core/spec/lib/demo/session_store_spec.rb` — Redis TTL/JSON/
  find/delete coverage.
- `app_core/spec/lib/demo/bridge_token_spec.rb` — claims/audience/expiry/
  wrong-secret coverage.
- `app_core/spec/requests/demo_sessions_spec.rb` — start/stop, cookie,
  dashboard demo render, missing Redis key, expiry behavior.
- `app_core/spec/requests/demo/inventories_spec.rb` — demo detail page
  renders only with a demo session.
- `app_core/app/frontend/inventories/__tests__/useDemoInventory.test.js`
  — demo summary fetch, auth header, failure degradation.
- Additional Vitest files/updates for `InventoriesIndex`, `InventoryCard`,
  `InventoryDetail`, and the dashboard hooks as needed.

### `app_fetcher`

- `app_fetcher/lib/api/demo/unsupported_param_error.rb` —
  `Api::Demo::UnsupportedParamError < StandardError`.
- `app_fetcher/app/controllers/api/demo/base_controller.rb` — demo-token
  auth (`APP_DEMO_JWT_SECRET`, `aud: "demo"`, integer `seed`), demo
  dataset memoization, `rescue_from` for `StandardError`,
  `ActiveRecord::RecordNotFound`, and the demo param error.
- `app_fetcher/app/controllers/api/demo/inventories_controller.rb` —
  `show` (dashboard skeleton), `summary`, and `detail`.
- `app_fetcher/app/controllers/api/demo/inventory_values_controller.rb` —
  `index` with period parsing.
- `app_fetcher/app/controllers/api/demo/item_prices_controller.rb` —
  `dynamics`, `trend`, `history` using the demo item names.
- `app_fetcher/app/queries/demo/dataset.rb` — `Demo::Dataset` read model:
  deterministic item selection, summary/value/history/detail builders,
  rarity counts, fallback to priced catalog items, and no writes.
- `app_fetcher/app/queries/demo/item_pool.rb` — reads
  `config/demo_items.yml`, exposes entries and market hash names.
- `app_fetcher/config/demo_items.yml` — small placeholder pool (names,
  rarity, category) for this task; full curation is the follow-up.
- `app_fetcher/lib/tasks/demo.rake` — `demo:seed_items`, idempotent item
  upsert and price-update enqueue via the existing worker.
- `app_fetcher/spec/requests/api/demo/inventories_spec.rb` — auth and
  the three inventory payloads; no `UserInventory` writes.
- `app_fetcher/spec/requests/api/demo/inventory_values_spec.rb` — period
  validation and payload shape.
- `app_fetcher/spec/requests/api/demo/item_prices_spec.rb` — dynamics,
  trend, history, and unknown-item 404.
- `app_fetcher/spec/queries/demo/dataset_spec.rb` — determinism,
  fallback, history, rarity, detail parameters.
- `app_fetcher/spec/queries/demo/item_pool_spec.rb` — YAML loading and
  names.

## Test Plan

### `app_core` RSpec

- `Demo::SessionStore`:
  - `create` writes one JSON value with a 12-hour TTL (real Redis, per
    `rspec-conventions.md`’s “class that writes to Redis directly” rule);
  - `find` round-trips `id`/`seed`/`created_at`;
  - `find` returns `nil` for an unknown key;
  - `remaining_seconds` reflects the TTL and returns `nil` for a missing
    key;
  - `delete` removes the key.
- `Demo::BridgeToken`:
  - carries `demo_id`, `seed`, `aud: "demo"`, and a 12-hour `exp`;
  - verifies with `APP_DEMO_JWT_SECRET`;
  - does not verify with `APP_BRIDGE_JWT_SECRET`.
- `DemoSessionsController` request specs:
  - `POST /demo_session` creates a Redis session and a persistent cookie,
    then redirects to `/`;
  - a second start replaces the previous demo and removes the old key;
  - `DELETE /demo_session` deletes the key/cookie and redirects;
  - a missing Redis key is treated as expired: the cookie is cleared and
    the signed-out page renders without a demo token;
  - `GET /` in demo mode includes `data-demo="true"`, a demo token, and
    the dashboard mount, while a normal signed-out request does not;
  - `GET /` in demo mode does not call the Steam/player token path.
- Dashboard request specs:
  - signed-in and signed-out behavior remains as today;
  - demo mode renders the demo badge/topbar and does not render a
    `data-bridge-token`.
- Inventories request specs:
  - `/inventories` in demo mode includes the demo flag/token and topbar
    badge, and still has no player bridge token;
  - `/inventories/:steam_id` in demo mode does not carry the demo
    inventory mount flag, so it keeps using the public endpoint.
- Demo inventory page request spec:
  - `/demo/inventory` redirects without a demo session;
  - with a demo session it renders the inventory-detail mount with
    `data-demo-inventory="true"` and “My account”.

### `app_fetcher` RSpec

- `Api::Demo` auth:
  - missing, garbage, expired, malformed, and wrong-audience tokens
    return `401` with the demo error message;
  - a valid demo token succeeds;
  - a player bridge token is rejected by the demo namespace;
  - a demo token is rejected by `Api::V1::`.
- `Api::Demo::InventoriesController`:
  - dashboard inventory has the V1 skeleton shape;
  - summary has one entry-shaped payload;
  - detail has the public detail shape, honors `period` and `sort`, and
    returns paginated top items;
  - no `UserInventory`/`UserInventoryItem` rows are created.
- `Api::Demo::InventoryValuesController`:
  - supported periods work; unknown period is `400`;
  - history ends at the current snapshot and is complete.
- `Api::Demo::ItemPricesController`:
  - dynamics uses the demo item set and real prices;
  - trend returns the demo item names;
  - history returns points for a known item and `404` for an unknown one.
- `Demo::Dataset`:
  - same seed gives the same item selection and history; different seeds
    generally differ;
  - selection is capped at 20 and falls back to priced catalog items
    when the pool is incomplete;
  - all selected items are priced/marketable;
  - history’s last point equals the current total;
  - rarity counts match the selected items;
  - `details` supports period/sort/page and returns a fully populated
    `InventoryDetailQuery::InventoryDetails`.
- `Demo::ItemPool`:
  - loads the YAML entries and names;
  - the placeholder file is valid.
- Serializer regression:
  - `InventoryListSerializer`’s existing list output is unchanged;
  - the reusable single-summary shape matches an entry in the list.

### Vitest / Testing Library

- Dashboard hooks:
  - every hook uses `${fetcherUrl}${apiBase}`;
  - demo base `/api/demo` and token are passed through;
  - existing `/api/v1` tests still pass.
- `useDemoInventory`:
  - calls `/api/demo/inventory_summary` with `Bearer <demoToken>`;
  - returns `null` on failure instead of breaking the page.
- `InventoriesIndex`:
  - in demo mode, the demo summary is fetched first and rendered as the
    first, sticky card inside the public grid with the Demo badge and
    `/demo/inventory` link;
  - the public list still requests `/api/public/inventories` with no auth
    header;
  - public pagination/ranks/count are unaffected;
  - no demo request is made when `demo=false`.
- `InventoryCard`:
  - badge renders next to the name;
  - custom `href` is used;
  - a missing `rank` does not render `#undefined`;
  - existing delta/partial/avatar/link behavior remains.
- `InventoryDetail` / `useInventoryDetail`:
  - demo mode calls `/api/demo/inventory_detail` with the demo token;
  - public mode still calls `/api/public/inventories/:steam_id` with no
    auth;
  - the demo header shows “Demo inventory” and the badge;
  - period/sort/page changes refetch the demo endpoint.
- Existing dashboard tests are updated only for the new `apiBase`
  argument; no behavior regressions.

## Implementation Steps

1. **Add `app_core` Redis support.** Add `redis`/`connection_pool` to the
   Gemfile, create `config/initializers/redis.rb`, regenerate the lock
   file, add/refresh the Sorbet RBI for Redis, and add
   `APP_DEMO_JWT_SECRET`/`REDIS_URL_DEMO` to the local/CI env.
2. **Implement the demo session layer.** Add `Demo::SessionStore`,
   `Demo::BridgeToken`, `Demo::Start`, `Demo::Stop`, and their unit
   specs. Use a 12-hour TTL and `APP_DEMO_JWT_SECRET`.
3. **Wire demo identity into `app_core`.** Add `current_demo` and
   `demo_bridge_token` to `ApplicationController`, the
   `DemoSessionsController` and routes, the layout body attributes, and
   request specs for start/stop/expiry.
4. **Implement the demo page chrome.** Add the dashboard CTA, the demo
   dashboard render condition, the topbar demo chip/badge/exit control,
   and the demo inventory page/controller/route. Update request specs.
5. **Add demo data to `app_fetcher`.** Add `Demo::ItemPool`, the
   placeholder YAML, `demo:seed_items`, and `Demo::Dataset` with summary,
   value/history, and detail builders. Add unit specs for determinism,
   fallback, history, rarity, and detail parameters.
6. **Add the `Api::Demo` API.** Add the namespace error class, base
   controller with demo-token validation, inventory/value/item-price
   controllers, routes, and request specs for auth, payload shapes, and
   no-write isolation.
7. **Refactor the dashboard frontend for `apiBase`.** Thread `apiBase`
   through `Dashboard` and all five hooks; update entrypoint and tests.
   Verify existing V1 behavior is unchanged.
8. **Add the demo inventory card.** Export/reuse the inventory mapper,
   add `useDemoInventory`, extend `InventoryCard` with optional
   badge/href/rank, render the demo card first (sticky) inside the
   public grid, and add Vitest coverage for demo and non-demo modes.
9. **Add demo inventory detail reuse.** Detect the
   `data-demo-inventory` mount flag, thread demo props through
   `InventoryDetail`/`useInventoryDetail`, and add tests proving the
   public detail path is unchanged.
10. **Style the demo surfaces.** Add the shared badge and demo
    card/section styles; verify the topbar, card, and detail badge are
    consistent.
11. **Update documentation.** Update the core/fetcher architecture
    styleguides (and any new ADR/styleguide required by
    `styleguides-check`) to describe the demo stack, the
    `Api::Demo::` namespace, and the “seed items, not demo rows” rule.
12. **Run the full verification suite**, then update this plan’s
    frontmatter to `implemented` after the code and tests are complete.

## Verification

- `app_core/bin/ci` (or the equivalent docker compose commands):
  RuboCop, Sorbet, Brakeman, bundler-audit, RSpec, ESLint, Prettier,
  Vitest.
- `app_fetcher/bin/ci`: RuboCop, Sorbet, Brakeman, bundler-audit, RSpec.
- Manual end-to-end:
  - start the stack with `APP_DEMO_JWT_SECRET` and `REDIS_URL_DEMO`;
  - run `bin/rails demo:seed_items` in `app_fetcher`;
  - open `/`, click “Try a demo account”;
  - verify the dashboard loads demo data, the topbar shows the Demo badge,
    and “Exit demo” returns to the signed-out state;
  - open `/inventories` in demo mode and verify the demo card is first,
    has the badge, and links to `/demo/inventory`;
  - verify the demo detail page renders portfolio/stats/items and that
    period/sort controls work;
  - open a real public inventory detail page in demo mode and verify it
    still uses real public data;
  - inspect Redis: `TTL demo:session:<id>` is ≤ 43200 and the value
    contains only `id`/`seed`/`created_at`;
  - verify no `UserInventory` rows exist for the demo and that
    `/api/public/inventories` count/pagination is unchanged;
  - wait for/force expiry and verify the demo cookie is cleared and the
    sign-in screen returns.
- Security checks:
  - a player token cannot call `/api/demo/*`;
  - a demo token cannot call `/api/v1/*` or `/api/admin/*`;
  - demo HTML is not publicly cacheable (`Cache-Control: private,
    no-store` when a demo session is present).
- `bundle exec srb tc` in both apps after adding the Redis gem/RBI and
  the new `Demo::` structs.

## Risks

- **New Redis dependency in `app_core`.** It currently has no Redis gem
  or initializer; adding one affects the lock file, Sorbet RBI, Docker,
  and CI. Keep the pool small and the initializer consistent with
  `app_fetcher`’s.
- **Three independent expiry clocks.** Redis TTL, cookie `expires`, and
  JWT `exp` must all be 12 hours and based on `created_at`. A cookie that
  outlives the Redis key must degrade to “no demo”, not an error.
- **Redis outage.** `current_demo`, `create`, and `destroy` must rescue
  `Redis::BaseError`; public pages must still render.
- **Demo token leakage/caching.** The demo token is embedded in the body
  for demo sessions. Ensure demo HTML is not cached by a shared cache and
  that the token is only minted when a demo session exists.
- **Fourth API namespace.** `Api::Demo::` duplicates the base-controller
  auth/error shape a fourth time. This is deliberate for isolation, but
  `styleguides-check` should decide whether an ADR/styleguide update is
  required rather than silently adding a new pattern.
- **Serializer reuse.** `InventoryListSerializer#inventory_json` is
  currently private. Making it public/extracting it must not change the
  list response; add a regression test.
- **Detail struct construction.** `InventoryDetailSerializer` expects a
  fully populated `InventoryDetailQuery::InventoryDetails`. A missing
  field or a nil snapshot will break the demo detail page; cover with a
  unit spec for `Demo::Dataset#details`.
- **`apiBase` refactor.** Five dashboard hooks currently hardcode
  `/api/v1`; missing one leaves demo mode partially broken. Cover each
  hook’s URL in Vitest.
- **Public-page demo distinction.** `/inventories/:steam_id` in demo mode
  must keep using the public endpoint. The demo flag on `<body>` alone is
  not enough; use a mount-node `data-demo-inventory` flag only on
  `/demo/inventory`.
- **Demo card and pagination.** The demo card must be the first item
  inside `InventoryGrid` (sticky), but outside `Pagination`/`meta`;
  otherwise it will change ranks or counts.
- **Item pool emptiness.** A fresh environment may have no seeded items.
  The dataset must fall back to any priced marketable items, and the demo
  must not 500 on an empty catalog.
- **Price/trend freshness.** Demo items need prices; `demo:seed_items`
  only enqueues `PriceUpdateWorker`. Until the worker runs, the fallback
  and “partial/empty” UI states must be acceptable.
- **Sorbet with Redis.** `Redis` methods are untyped; add the gem RBI and
  use narrow types where possible. Do not weaken the whole file.
- **Tracked Items semantics.** The page is a public catalog, not a
  per-user tracked list; seeding the pool will make items appear there.
  This is expected and should be stated in docs/tests.

## Assumptions

- The demo lifetime is **12 hours**, not 24.
- This task includes the demo feature end-to-end plus a **minimal
  placeholder** `config/demo_items.yml` and `demo:seed_items` task so the
  feature is testable. Curating the full 40–50 item pool and real icons
  is a separate follow-up task.
- The demo inventory is private to the demo session and is never part of
  the public inventory list.
- The demo card is shown first on `/inventories` but is outside the
  public list’s pagination, ranking, and total count.
- The demo detail page is a separate `/demo/inventory` route; the public
  `/inventories/:steam_id` page remains unchanged.
- Public pages stay real while in demo mode; the demo badge in the topbar
  is the only cross-page demo affordance.
- Seeded pool items are ordinary `Item` rows and may appear in the public
  item catalog/Tracked Items.
- `APP_DEMO_JWT_SECRET` is a distinct secret, not a reuse of the player
  or admin bridge secret.
- Redis is available in all target environments; `REDIS_URL_DEMO`
  defaults to a local DB 3 URL and is overridden by compose/CI.
- No database migrations or new domain tables are required.

## Completion Criteria

- A signed-out visitor can start and end a 12-hour read-only demo.
- Demo dashboard and `/demo/inventory` render generated data from real
  item prices without writing demo rows to Postgres.
- The demo card appears first on `/inventories` with a Demo badge and
  does not affect the public list.
- Public pages remain real and unchanged outside the demo chrome.
- Demo and player/admin tokens are mutually rejected.
- All new Ruby/JS behavior is covered by unit/request/Vitest specs.
- CI/lint/type checks and the manual end-to-end checklist pass.
- The plan file is updated to `status: implemented` once complete.

# Implementation Summary

## Implemented

- Added a 12-hour, Redis-backed demo session (`demo:session:<id>`) with an
  encrypted `demo_id` cookie and a separate `APP_DEMO_JWT_SECRET` demo JWT.
- Added `current_demo` / `demo_bridge_token` to `ApplicationController`,
  body-level `data-demo` / `data-demo-token` in the application layout,
  a demo CTA on the signed-out dashboard, a topbar demo chip/badge/exit
  control, and a `POST/DELETE /demo_session` controller.
- Added `/demo/inventory` and its demo inventory-detail mount page.
- Added `Api::Demo::` to `app_fetcher` with demo-token auth, the seven
  read endpoints, and CORS for `/api/demo/*`.
- Added `Demo::Dataset`/`Demo::ItemPool` under
  `app_fetcher/app/queries/demo/`, deterministic seed-based selection,
  generated portfolio history, real price/trend reuse, rarity counts, and
  priced-item fallback.
- Added the placeholder `config/demo_items.yml` pool and idempotent
  `demo:seed_items` rake task (ordinary `Item` rows + existing
  `PriceUpdateWorker`).
- Threaded `apiBase` through the dashboard's five data hooks, added the
  `/api/demo/inventories/me` dashboard alias, added the demo inventory
  summary hook, and made the demo card the first sticky card inside the
  inventory grid (not a separate block above it). Reused
  `InventoryCard` / `InventoryDetail` for demo surfaces.
- Added no-store caching for demo HTML, Redis-failure degradation,
  `REDIS_URL_DEMO`/`APP_DEMO_JWT_SECRET` config, CI values, Sorbet/Redis
  RBIs, and the demo-mode ADRs/styleguides.

## Tests

Added/changed:

- `app_core/spec/lib/demo/session_store_spec.rb`
- `app_core/spec/lib/demo/bridge_token_spec.rb`
- `app_core/spec/requests/demo_sessions_spec.rb`
- `app_core/spec/requests/demo/inventories_spec.rb`
- `app_core/spec/requests/dashboards_spec.rb`
- `app_core/spec/requests/inventories_spec.rb`
- `app_core/spec/support/demo_session_helper.rb`
- `app_fetcher/spec/requests/api/demo/*_spec.rb`
- `app_fetcher/spec/queries/demo/dataset_spec.rb`
- `app_fetcher/spec/queries/demo/item_pool_spec.rb`
- `app_fetcher/spec/lib/tasks/demo_spec.rb`
- `app_fetcher/spec/support/demo_token_helper.rb`
- Dashboard/Inventories Vitest updates plus
  `useDemoInventory.test.js` and the demo `InventoryDetail`/`InventoryCard`
  cases.

Commands executed:

- `docker compose run --rm app_core bundle exec rspec` — 93 examples, 0 failures.
- `docker compose run --rm app_fetcher bundle exec rspec` — 532 examples, 0 failures.
- `docker compose run --rm app_core npm run test` — 320 tests, 0 failures.
- `docker compose run --rm app_core npm run format:check` — passed.
- `docker compose run --rm app_core npm run lint` — 0 errors (one pre-existing warning in `tracked_items/TrackedItems.jsx`).
- `docker compose run --rm app_core bundle exec srb tc` — no errors.
- `docker compose run --rm app_fetcher bundle exec srb tc` — no errors.
- `docker compose run --rm app_core bin/rubocop` — no offenses.
- `docker compose run --rm app_fetcher bin/rubocop` — no offenses.
- `docker compose run --rm app_core bin/brakeman ...` — no warnings.
- `docker compose run --rm app_fetcher bin/brakeman ...` — no warnings.
- `docker compose run --rm app_core bin/bundler-audit` — no vulnerabilities.
- `docker compose run --rm app_fetcher bin/bundler-audit` — no vulnerabilities.
- `docker compose run --rm app_core env RAILS_ENV=test bin/rails db:seed:replant` — passed.
- `docker compose run --rm app_fetcher env RAILS_ENV=test bin/rails db:seed:replant` — passed.
- `docker compose config` — valid.
- Manual `Api::Demo::InventoriesController#show` call against the running
  fetcher with a generated demo JWT returned `200` and 20 real items;
  CORS preflight/response headers for `http://localhost:3000` were
  confirmed after restarting the fetcher.

## Verification

All planned automated checks pass. The app_core HTML/CSRF demo-start flow
is covered by request specs; no browser automation was available in this
environment, so the final visual browser check remains a manual step.

## Deviations

- `Demo::Dataset`/`Demo::ItemPool` were placed under
  `app_fetcher/app/queries/demo/` rather than `app/demo/`: Rails treats
  each top-level `app/<dir>` as an autoload root, so `app/demo/dataset.rb`
  maps to top-level `Dataset`, not `Demo::Dataset`. The new
  `fetcher/demo-api.md` guide and the plan were updated to reflect the
  namespaced `app/queries/demo/` location.
- Added a `config/initializers/cors.rb` entry for `/api/demo/*`; the
  browser calls the demo API cross-origin, and the original CORS config
  only covered `/api/v1`, `/api/admin`, and `/api/public`.
- Added `prevent_demo_caching` in `ApplicationController` to send
  `Cache-Control: private, no-store` for demo HTML, as required by the
  demo-mode styleguide.
- Added a demo-token CORS request spec and a `demo:seed_items` task spec.

## Remaining Issues

- The curated 40–50 item demo pool and its real icon metadata were
  completed by `agent/plans/demo-item-pool.md`; the checked-in pool is no
  longer a placeholder.
- The pre-existing `react-hooks/exhaustive-deps` warning in
  `tracked_items/TrackedItems.jsx` remains (unrelated to this change).
- A final visual browser pass over the demo card/detail layout is still
  worth doing in a real browser.

## Post-Implementation Note

Set `APP_DEMO_JWT_SECRET` and `REDIS_URL_DEMO` in every deployed
environment. The demo token is intentionally distinct from the player and
admin bridge secrets.
