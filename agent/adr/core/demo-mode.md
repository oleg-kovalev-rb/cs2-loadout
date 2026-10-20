# A Session-Scoped Demo Identity in Redis, Separate From `User` and `Steam::BridgeToken`

## Status

Accepted

## Context

`app_core` currently has two identity stacks: the Steam-authenticated
`User` stack (`session[:user_id]`, `Steam::BridgeToken`) and the
internally-granted `AdminUser` stack (`session[:admin_user_id]`,
`Admin::BridgeToken`). Public pages have no identity at all.

A signed-out visitor should be able to try the dashboard without a Steam
login. The trial must be read-only, last a bounded amount of time, and
never look like a real Steam account. The obvious-looking alternatives —
creating a `User` with a fake `steam_id`, adding a `demo` flag to
`User`/`UserInventory`, or persisting a demo inventory — all leak into
existing behavior: `UserInventory` is keyed by `steam_id` and feeds the
public inventory list, the sync scheduler, and the value scheduler; a
fake row would need `no_demo` scopes in every one of those paths and a
cleanup job. That is a recurring tax on unrelated code for a feature
that is intentionally disposable.

The demo also has to survive a browser restart and expire on its own.
A normal Rails session cookie is a session cookie (it dies when the
browser closes); Redis alone is unreachable if the browser forgets the
session id. The design therefore needs both a persistent browser-side
reference and a server-side record with a TTL.

## Decision

Model demo mode as a **session-scoped identity**, not as a `User`:

- A demo session is `demo:session:<id>` in Redis, containing only
  `id`, `seed`, and `created_at`, with a **12-hour TTL**.
- The browser holds `<id>` in an encrypted, HttpOnly, SameSite=Lax
  cookie named `demo_id`, also expiring in 12 hours.
- `app_core` mints a demo JWT with `demo_id`, `seed`, `aud: "demo"`,
  `iat`, and `exp` (`created_at + 12 hours`), signed with a **separate**
  `APP_DEMO_JWT_SECRET`.
- `ApplicationController#current_demo` resolves the cookie through Redis
  and returns `nil` when the key is gone; `demo_bridge_token` mints the
  token. The layout exposes `data-demo` and `data-demo-token` on
  `<body>`; the React islands choose `/api/demo` vs `/api/v1` from that
  flag. `DashboardsController` keeps only its existing player-token path.
- The demo inventory is **generated** in `app_fetcher` from the real
  `Item` catalog using the session seed. No `User`, `UserInventory`,
  `UserInventoryItem`, or `InventoryValueLog` rows are created for a
  demo.
- Curated demo items are seeded as ordinary `Item` rows; the demo pool
  is a list of item names, not a second inventory store.
- Public pages remain real. The demo card is fetched separately and
  rendered first on `/inventories`, outside the public list's
  pagination, ranking, and total count. `/demo/inventory` is a separate
  page that reuses the public inventory-detail UI; `/inventories/:steam_id`
  stays on the public API even while a demo session is active.
- Demo tokens must not be accepted by `Api::V1::`, `Api::Public::`, or
  `Api::Admin::`, and player/admin tokens must not be accepted by
  `Api::Demo::`.

## Alternatives Considered

### Alternative: a persisted `User` with a synthetic `steam_id`

Rejected because:

- `users.steam_id` is a unique identity also used by `Steam::LoginUser`
  and `Steam::BridgeToken`; a synthetic value is indistinguishable from
  a real account at the model layer.
- The demo inventory would need to be a real `UserInventory` row, which
  would enter `InventoryListQuery`'s public list and `total_count`, the
  sync/value schedulers, and every future inventory query unless each
  one adds a `no_demo` scope.
- There is no honest cleanup path beyond a TTL job that must find and
  delete the row and its dependent inventory/value logs.

### Alternative: a `demo` boolean flag plus scopes

Rejected because:

- It puts a demo predicate into every query, serializer, scheduler, and
  admin screen that touches the flagged tables — the exact recurring
  cost this feature is meant to avoid.
- A flag does not solve the identity question: the row still needs a
  `steam_id` and still looks like a user to the Steam login path.

### Alternative: a separate `DemoUser` model / parallel identity stack

Rejected because:

- It creates a second identity model, session key, token class, and
  controller gating path, even though demo access is not an identity
  that needs profile, login, or account management.
- Demo data still has to live somewhere; a parallel model does not
  remove the need for generated data or the public-list isolation.

### Alternative: a single persisted showcase inventory

Rejected because:

- It is shared by every visitor, so it is not “your” demo and cannot be
  randomized per session.
- Excluding it from the public list, rankings, and schedulers still
  requires the same scopes/cleanup work as any other persisted demo
  row.

### Alternative: a stateless cookie-only demo (no Redis)

Rejected because:

- A long-lived cookie carrying the whole demo identity has no
  server-side revocation or existence check; clearing a demo early
  would mean rotating/invalidating the cookie only on the client.
- Redis gives the explicit TTL and a single server-side source of truth
  for “does this demo still exist”, while the cookie only carries the
  reference.

### Alternative: reuse `Steam::BridgeToken` with a `demo` claim

Rejected because:

- A shared secret means a leak or verification mistake compromises both
  real and demo identities.
- It would require branching in `Api::V1::BaseController` on the demo
  claim, reintroducing the conditional-flag pattern this project has
  deliberately avoided at the namespace level.

## Consequences

### Positive

- No demo rows in any domain table; no `demo` flags, no `no_demo`
  scopes, and no cleanup job beyond Redis TTL.
- Demo data is isolated by construction: it cannot appear in the public
  inventory list, schedulers, or another visitor's demo.
- Existing dashboard/inventory React components and existing
  `app_fetcher` serializers are reused rather than forked.
- The 12-hour lifetime is enforced independently by Redis, the cookie,
  and the JWT, and a missing Redis key degrades cleanly to “no demo”.
- The demo token has its own secret and audience, so token crossover is
  structurally rejected.

### Negative

- `app_core` gains a direct Redis dependency (gem, initializer, CI env,
  Sorbet RBI) where it previously had none.
- A fourth token/namespace type is added (`Api::Demo::`), with a base
  controller that duplicates the existing auth/error shape.
- Generated demo data can drift as the real item catalog and prices
  change; the selection is stable for a seed, but the values are live.
- Curated demo items need a separate seed task and a pool list; the
  first version may only have a small placeholder pool.

### Risks

- Redis unavailability must not break public pages; all demo reads must
  degrade to “no demo” and only the demo-start action may surface an
  alert.
- A demo token embedded in the page must not be cached by a shared
  cache; demo responses need `Cache-Control: private, no-store`.
- A cookie that outlives the Redis key must be treated as expired and
  cleared, not as an error.
- If a future feature genuinely needs per-user demo state (e.g. saved
  filters), that state must go to Redis/session storage, not to a
  Postgres demo table, unless this decision is revisited.

## Implementation Constraints

- `Demo::SessionStore` lives in `app_core/lib/demo/` and uses a
  dedicated `DEMO_REDIS_POOL`; key prefix `demo:session:`; 12-hour TTL;
  JSON values containing only `id`/`seed`/`created_at`.
- `Demo::BridgeToken` lives in `app_core/lib/demo/`, signs with
  `APP_DEMO_JWT_SECRET`, and carries `demo_id`, `seed`, `aud: "demo"`,
  `iat`, and `exp`.
- `current_demo`/`demo_bridge_token` live on `ApplicationController`;
  `DashboardsController` must not gain demo branching.
- The demo cookie must be encrypted, HttpOnly, SameSite=Lax, secure in
  production, and expire in 12 hours.
- `app_fetcher` exposes a separate `Api::Demo::` namespace whose base
  controller verifies the demo secret/audience and rejects every other
  token type.
- The demo dataset is read-only and generated in `app_fetcher`; it must
  not write `UserInventory`, `UserInventoryItem`, or
  `InventoryValueLog` rows.
- Curated demo items are ordinary `Item` rows seeded by a rake task;
  the pool list lives in `config/demo_items.yml`.
- The demo card on `/inventories` is fetched separately and must not
  affect the public list's `meta`, ranks, or pagination.
- `/demo/inventory` is a distinct page; the public
  `/inventories/:steam_id` page must keep using the public API while a
  demo session is active.

## Related

- `agent/styleguides/core/demo-mode.md` — the concrete app_core
  conventions this decision backs.
- `agent/adr/fetcher/demo-api.md` — the app_fetcher side of the same
  feature (the read-only demo API and generated dataset).
- `agent/styleguides/core/architecture-layers.md` — the identity/layer
  map this decision adds a demo mode alongside.
- `agent/adr/core/separate-admin-authentication.md` — the precedent for
  keeping a separate identity stack and separate token secret rather
  than branching a shared one.
- `agent/adr/fetcher/public-api-namespace.md` — the precedent for
  making a request's auth posture structural rather than a conditional
  flag.
