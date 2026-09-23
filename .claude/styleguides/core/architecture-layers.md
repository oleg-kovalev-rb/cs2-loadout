---
description: app_core's concrete layer map — Controller → Action (app/actions/steam) → lib/steam/ → Models, plus the dashboard's direct app_fetcher reads.
---

# Architecture Layers (`app_core`)

See `.claude/styleguides/rails-layering.md` first for the cross-app
invariant this follows. This file is the concrete layer map specific to
`app_core`.

## Purpose

Give request-scoped business logic, external API/crypto calls, and the
React dashboard's data access each an unambiguous home, so new features
(another login-adjacent action, another dashboard data need) don't
re-derive the split. See
`.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md` for
why controllers delegate to actions and why the dashboard reads
`app_fetcher` directly instead of through an `app_core` proxy endpoint.

## When to Use

Applies to any `app_core` controller, `app/actions/`, `lib/` client, or
the `app/frontend/dashboard/` React island's data access. Not relevant
to `app/jobs/` — currently unused (`ApplicationJob` only), no convention
established yet.

## Structure

```text
Controller (app/controllers/)
    ↓  current_user lookup only, else delegates
Action (app/actions/steam/, Sorbet `.call` entry point)
    ↓
lib/steam/  (Authenticator, ProfileFetcher, BridgeToken — external I/O/crypto)
    ↓
Models (app/models/ — User)

Browser (React island, app/frontend/dashboard/)
    → HTTPS, Bearer <bridge token> → app_fetcher's Api::V1:: endpoints
      (bridge token minted by DashboardsController via Steam::BridgeToken,
       embedded in the rendered page — never proxied through app_core)
```

- **Controllers**: routing, `require_login` auth guard, rendering.
  `current_user` (a plain `User.find_by`) is the one model access
  allowed directly in a controller; anything else goes through an
  action.
- **Actions** (`app/actions/steam/`): `.call` entry point, Sorbet-typed,
  orchestrate `lib/steam/` calls and model persistence for one request-
  scoped operation (e.g. `Steam::LoginUser`).
- **`lib/steam/`**: external HTTP (Steam OpenID, Steam Web API) and
  crypto (JWT bridge-token minting). No AR references.
- **Models** (`app/models/`): persistence + validation only (`User`).
- **React island**: reads data embedded in the rendered page (bridge
  token, `APP_FETCHER_PUBLIC_URL`) and fetches inventory/price data
  directly from `app_fetcher` — never from an `app_core` endpoint.

## Responsibilities

Anything beyond a single trivial model lookup (validating a login,
fetching a Steam profile, minting a bridge token) belongs in an action
or `lib/steam/`, not inline in a controller. The React island owns no
server-round-trip logic of its own beyond calling `app_fetcher` — it has
no `app_core` API to call.

## Dependencies

One-directional, per `rails-layering.md`. Concretely for this app:

- Controllers depend on actions, `User` (for `current_user`), and
  `Steam::BridgeToken` (to mint a token for the rendered page).
- Actions depend on `lib/steam/` and models.
- `lib/steam/` depends on nothing else in the app (external HTTP/crypto
  only).
- The React island depends on `app_fetcher`'s API directly, not on any
  `app_core`-hosted endpoint.

## Rules

### MUST

- Route request-scoped business logic beyond a single model lookup
  through `app/actions/`, not inline in a controller.
- Keep external API calls and crypto operations inside `lib/steam/` (or
  a new `lib/<domain>/`), never inlined into a controller or action.

### MUST NOT

- Don't add an `app_core` endpoint that proxies or re-serves
  `app_fetcher` data for the React island to call instead of calling
  `app_fetcher` directly — see ADR for why, and revisit the ADR first if
  a case seems to need one.
- Don't perform the Steam OpenID handshake or Steam Web API calls
  outside `lib/steam/`.

## Interaction With Other Layers

```text
GET /session/callback
    → SessionsController#callback
    → Steam::LoginUser.call
        → Steam::Authenticator.validate!  (lib/steam/)
        → Steam::ProfileFetcher.call      (lib/steam/)
        → User.find_or_initialize_by / .save!

GET /dashboard
    → DashboardsController#show
    → Steam::BridgeToken.encode(steam_id)  (lib/steam/, 2-minute TTL)
    → renders page with token + APP_FETCHER_PUBLIC_URL embedded
        → browser React island fetches app_fetcher's
          Api::V1::InventoriesController / PriceHistoriesController
          directly, Bearer-authenticated with the embedded token
```

## Canonical Implementations

- `app_core/app/actions/steam/login_user.rb`
- `app_core/app/controllers/sessions_controller.rb`
- `app_core/app/controllers/dashboards_controller.rb`
- `app_core/lib/steam/bridge_token.rb`,
  `app_core/lib/steam/authenticator.rb`,
  `app_core/lib/steam/profile_fetcher.rb`
- `app_core/app/frontend/dashboard/Dashboard.jsx`,
  `app_core/app/frontend/dashboard/hooks/useDashboardData.js`

## Related ADR

`.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md`
