---
description: app_core demo-mode conventions — a 12-hour Redis-backed demo session, persistent encrypted cookie, separate demo JWT, global current_demo/layout state, and the demo badge/card/detail behavior that keeps public pages real.
---

# Demo Mode (`app_core`)

See `agent/adr/core/demo-mode.md` for why demo mode is a session-scoped
identity rather than a `User`, and why demo data is generated in
`app_fetcher` instead of persisted. This file covers how the
`app_core` side is written once that decision is taken as given.

## Purpose

Give a signed-out visitor a disposable, read-only demo identity without
creating a Steam account. What belongs here: the demo session record in
Redis, the browser cookie that references it, the demo JWT, the
`current_demo` helpers, and the page/UI affordances that tell a demo
visitor they are in demo mode. What does not: demo inventory contents,
demo prices, or any demo data generation — those live in `app_fetcher`
(see `agent/styleguides/fetcher/demo-api.md`).

## When to Use

Use this pattern when a signed-out visitor needs a temporary, isolated
view of existing `app_fetcher` data without a real identity. Not for
“logged-out but real” public pages — those stay on the existing public
pattern with no identity at all (`inventories/`). Not for a second
player/admin account type; demo access has no profile, login, or account
lifecycle.

## Structure

- `app_core/config/initializers/redis.rb` — `DEMO_REDIS_POOL`, a
  `ConnectionPool` of `Redis` clients using `REDIS_URL_DEMO` (fallback
  to a local DB 3 URL). Keep the pool size aligned with
  `RAILS_MAX_THREADS`, matching `app_fetcher/config/initializers/redis.rb`.
- `app_core/lib/demo/session_store.rb` — `Demo::SessionStore` plus its
  nested `Session` struct (`id`, `seed`, `created_at`). Owns Redis key
  construction, JSON serialization, TTL, and lookup/deletion.
- `app_core/lib/demo/bridge_token.rb` — `Demo::BridgeToken`, HS256 JWT
  encoding only, with `ALGORITHM`, `AUDIENCE = "demo"`, and `encode`.
- `app_core/app/actions/demo/start.rb` and `stop.rb` — thin request-
  scoped actions around `SessionStore.create`/`delete`, following the
  `app/actions/` shape used by `Steam::LoginUser`.
- `app_core/app/controllers/demo_sessions_controller.rb` — create/destroy
  actions, cookie handling, redirects, and Redis-failure handling.
- `app_core/app/controllers/demo/inventories_controller.rb` — serves the
  `/demo/inventory` page; redirects when no demo session exists.
- `app_core/app/controllers/application_controller.rb` — `current_demo`
  and `demo_bridge_token`, exposed with `helper_method`.
- `app_core/app/views/layouts/application.html.erb` — the global
  `<body data-demo data-demo-token>` state.
- `app_core/app/views/dashboards/show.html.erb` — the signed-out demo
  CTA and the `current_user || current_demo` island render condition.
- `app_core/app/views/shared/_topbar.html.erb` — the “My account” chip,
  the Demo badge, and “Exit demo”.
- `app_core/app/views/demo/inventories/show.html.erb` — the
  `/demo/inventory` mount page.
- React entrypoints/hooks — `data-demo`/`data-demo-token` plumbing,
  `apiBase` selection, the demo inventory summary hook, and the demo
  detail reuse; see `react-dashboard.md` for the island-level rules.

## Interface

- `Demo::SessionStore::Session` — immutable `T::Struct` with `id:
  String`, `seed: Integer`, `created_at: Time`.
- `Demo::SessionStore.create` → `Session`; generates a UUID id and a
  random integer seed, writes the JSON value with `EX 43200`.
- `Demo::SessionStore.find(id)` → `Session` or `nil`.
- `Demo::SessionStore.remaining_seconds(id)` → positive `Integer` or
  `nil` when the key is missing/expired.
- `Demo::SessionStore.delete(id)` → void.
- `Demo::BridgeToken.encode(session)` → JWT string carrying `demo_id`,
  `seed`, `aud: "demo"`, `iat`, and `exp = session.created_at + 12 hours`.
- `current_demo` → `Demo::SessionStore::Session | nil`, memoized for the
  request.
- `demo_bridge_token` → `String | nil`, memoized for the request.
- Cookie name is `demo_id`; value is the session id.
- Routes: `POST/DELETE /demo_session` and `GET /demo/inventory`
  (`demo_session_path`, `demo_inventory_path`).

## Responsibilities

`Demo::SessionStore` owns Redis persistence and TTL. `Demo::BridgeToken`
owns JWT encoding. `DemoSessionsController` owns the browser cookie and
redirects. `ApplicationController` owns resolving the cookie into a
session and minting the token for the layout. `Demo::InventoriesController`
only gates the demo detail page.

`DashboardsController` owns no demo logic — it continues to mint only the
Steam player token for `current_user`. The layout is the single place
that decides whether a page has demo state; the React islands decide
which `app_fetcher` namespace to call from the body flag.

## Dependencies

- May depend on `DEMO_REDIS_POOL`, `Demo::SessionStore`,
  `Demo::BridgeToken`, and the Rails cookie jar.
- Must not depend on `User`, `AdminUser`, `UserInventory`, or any
  `app_fetcher` model/API. Demo identity is not a Steam identity.
- `lib/demo/` must not reference controllers or models; it is the
  external-storage/crypto boundary, analogous to `lib/steam/` and
  `lib/admin/`.
- The React islands depend on `app_fetcher`'s `Api::Demo::` endpoints
  directly; they never ask `app_core` to proxy demo data.

## Rules

### MUST

- Use a **12-hour** TTL consistently: Redis `EX 43200`, cookie
  `expires: 12.hours.from_now`, and JWT `exp` based on
  `session.created_at + 12.hours`.
- Use a dedicated `APP_DEMO_JWT_SECRET` and `aud: "demo"`; never reuse
  `APP_BRIDGE_JWT_SECRET` or `APP_ADMIN_BRIDGE_JWT_SECRET`.
- Store the demo id in an **encrypted** cookie (`cookies.encrypted`),
  `httponly: true`, `same_site: :lax`, and `secure: true` in production.
  Do not use `session[:demo_id]` — the Rails session cookie is not
  persistent across browser restarts.
- Resolve `current_demo` through Redis on every request that has the
  cookie; if the key is missing, delete the cookie and return `nil`.
- Rescue `Redis::BaseError` in `current_demo`, `create`, and `destroy`:
  a Redis outage must degrade to “no demo” and must not break public
  pages.
- Expose demo state to the frontend only through the layout’s
  `data-demo` / `data-demo-token` attributes (or an equivalent single
  page-level contract); do not add per-controller demo branches.
- Keep `DashboardsController` free of demo logic. The dashboard view may
  render the island when `current_user || current_demo`, but the
  controller keeps its existing player-token code only.
- Render the demo card as the first, sticky card inside the public
  grid, but outside pagination, ranking, and `meta.total_count`. Fetch
  its summary separately with the demo token.
- Keep `/inventories/:steam_id` on the public API even while a demo
  session is active. Only `/demo/inventory` may mount
  `data-demo-inventory="true"` and call the demo detail endpoint.
- Show the Demo badge in the topbar on every page while demo mode is
  active, and on the demo inventory card/detail header.
- Send `Cache-Control: private, no-store` for HTML rendered with a demo
  session, so a shared cache cannot replay one visitor’s demo token.
- Delete the previous Redis key when starting a new demo over an
  existing one.

### SHOULD

- Use a single `demo_bridge_token` helper rather than encoding the JWT
  twice in the layout/topbar.
- Keep the demo CTA visually secondary to the Steam CTA; demo is an
  alternative, not the primary login path.
- Keep the demo profile label as “My account” and the badge text as
  “Demo” — one consistent label across the topbar, card, and detail.

### MUST NOT

- Don’t create a `User`, fake `steam_id`, `UserInventory`, or
  `InventoryValueLog` for a demo.
- Don’t add `demo`/`no_demo` scopes or flags to `User` or any
  `app_fetcher` model.
- Don’t use `Rails.cache` for the demo session. In `app_core` it is a
  memory/null store in development/test; in `app_fetcher` it is
  SolidCache. Use the explicit Redis pool.
- Don’t put the demo token in a URL, query string, or log line.
- Don’t let a demo session change the public inventory list’s count,
  ranks, or pagination.
- Don’t render a demo card or demo detail on a page served by a shared
  cache.

## Error Handling

- `DemoSessionsController#create` rescues `Redis::BaseError`, logs it,
  and redirects to `/` with an alert that the demo is temporarily
  unavailable. It does not create a cookie when Redis failed.
- `current_demo` rescues `Redis::BaseError`, logs a warning, and returns
  `nil`; the page renders in signed-out/public mode.
- A cookie whose Redis key is missing is an expected expiry: clear the
  cookie and continue as signed-out. Do not raise or show an error.
- The demo API returns `401` for missing/invalid/expired/wrong-audience
  tokens; the frontend treats that as “demo ended” and shows the
  signed-out state rather than a hard error.
- `Demo::InventoriesController#show` redirects to `/` with an alert when
  there is no demo session, so a bookmarked `/demo/inventory` does not
  render an empty page.

## Data / Transactions

- The only persisted demo state is the Redis key and the browser cookie.
  There are no database writes.
- The Redis value is JSON with exactly `id`, `seed`, and `created_at`;
  never serialize the generated inventory or price history into it.
- Redis TTL is the cleanup mechanism; no cron job or Rails callback is
  needed.
- If Redis is flushed/restarted, demo sessions are lost. That is
  acceptable; the next request clears the cookie and returns to the
  signed-out screen.

## Interaction With Other Layers

```text
POST /demo_session
    → DemoSessionsController#create
        → Demo::Start.call → Demo::SessionStore.create
            → DEMO_REDIS_POOL SET demo:session:<id> EX 43200
        → cookies.encrypted[:demo_id] = <id>, expires: 12h
    → redirect_to root_path

GET /
    → ApplicationController#current_demo
        → cookies.encrypted[:demo_id] → Demo::SessionStore.find
    → demo_bridge_token → Demo::BridgeToken.encode(session)
    → layout: <body data-demo="true" data-demo-token="...">
    → dashboard entrypoint → app_fetcher Api::Demo::* directly

GET /inventories
    → public page as usual, plus body demo state
    → public island fetches Api::Public::* as usual
    → demo summary hook (only when demo) fetches
      app_fetcher Api::Demo::inventory_summary with the demo token

GET /demo/inventory
    → Demo::InventoriesController#show (redirect unless current_demo)
    → inventory-detail island with data-demo-inventory="true"
    → app_fetcher Api::Demo::inventory_detail with the demo token
```

## Testing

General RSpec mechanics live in `agent/styleguides/rspec-conventions.md`;
this section only adds demo-specific expectations.

- `Demo::SessionStore` writes to Redis directly, so its unit spec uses
  the real test Redis connection and asserts the actual key/value/TTL
  (the “class that writes to Redis directly” rule), not a stubbed Redis.
- Flush only the demo Redis database (or the `demo:session:*` keys) in
  the demo specs; do not flush a shared DB used by other specs.
- `Demo::BridgeToken` is a pure `lib/` class: assert claims, audience,
  expiry, and wrong-secret verification, following
  `app_core/spec/lib/steam/bridge_token_spec.rb`.
- Request specs cover start/stop, cookie persistence, missing Redis key,
  dashboard demo render, `/inventories` demo body state, and
  `/demo/inventory` gating. Assert that a normal signed-out request does
  not carry a demo token.
- Vitest covers the body flag/token plumbing and the demo card/detail
  behavior; see `react-dashboard.md`’s demo-mode section.

## Canonical Implementations

None yet — this plan creates the first implementation. The expected
files are listed in `agent/plans/demo-account.md`.

## Related ADR

`agent/adr/core/demo-mode.md`
