---
description: app_core's concrete layer map — Controller → Action (app/actions/steam) → lib/steam/ → Models, plus each React island's direct app_fetcher reads (per-player, admin, and public/unauthenticated).
---

# Architecture Layers (`app_core`)

See `agent/styleguides/rails-layering.md` first for the cross-app
invariant this follows. This file is the concrete layer map specific to
`app_core`.

## Purpose

Give request-scoped business logic, external API/crypto calls, and each
React island's data access an unambiguous home, so new features (another
login-adjacent action, another dashboard data need, a new admin-facing
screen, a new public page) don't re-derive the split. See
`agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md` for
why controllers delegate to actions and why a React island reads
`app_fetcher` directly instead of through an `app_core` proxy endpoint —
that decision's reasoning is island-agnostic, even though it was written
against the dashboard as its first (at the time, only) example.

## When to Use

Applies to any `app_core` controller, `app/actions/`, `lib/` client, or a
React island's data access (`app/frontend/dashboard/`,
`app/frontend/admin-panel/`, `app/frontend/inventories/`, and any sibling
island). Not relevant to `app/jobs/` — currently unused (`ApplicationJob`
only), no convention established yet.

`app_core` runs two structurally parallel, non-overlapping identity/data
stacks side by side, plus a third category with no identity stack at all
— see Structure below. A new feature belongs to whichever applies: a
feature gated by `current_user`/Steam login follows the Steam/`User`
stack; one gated by `current_admin_user`/`require_admin!` follows the
admin stack (`agent/styleguides/core/admin-authentication.md` owns that
stack's own internal rules — session shape, bridge-token claim,
format-aware redirects; this file owns where each stack's pieces sit
relative to each other and the shared no-proxy rule all three follow); a
feature whose backing `app_fetcher` data is genuinely public needs no
stack at all — no `current_user`/`current_admin_user` gate, no bridge
token minted anywhere, no `require_login`/`require_admin!` guard. Don't
blend any of these — see Dependencies.

## Structure

Two identity-scoped stacks (same shape) plus one identity-less pattern for
genuinely public data, never crossing over (see Dependencies):

```text
Steam/User stack:

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

Admin stack (parallel, unconnected — see admin-authentication.md for this
stack's own internal rules):

Controller (app/controllers/admin/)
    ↓  current_admin_user lookup only (Admin::BaseController), else delegates
lib/admin/  (BridgeToken — external I/O/crypto; no action layer exists yet,
             since nothing in this stack today needs more than a single
             lookup plus bridge-token minting — see Responsibilities)
    ↓
Models (app/models/ — AdminUser)

Browser (React island, app/frontend/admin-panel/)
    → HTTPS, Bearer <admin bridge token> → app_fetcher's Api::Admin:: endpoints
      (bridge token minted by Admin::PanelController via Admin::BridgeToken,
       embedded in the rendered page — never proxied through app_core)

Public/unauthenticated pattern (no identity stack at all):

Controller (app/controllers/ — e.g. InventoriesController)
    ↓  no current_user/current_admin_user gate, no auth guard, renders directly
    (no action/lib layer needed — nothing to orchestrate beyond rendering)

Browser (React island, app/frontend/inventories/)
    → HTTPS, no auth header at all → app_fetcher's Api::Public:: endpoints
      (Api::Public::ApplicationController has no auth filter — genuinely
       public; the page-serving controller mints no bridge token and
       embeds none — never proxied through app_core, same rule as both
       identity-scoped stacks)
```

- **Controllers**: routing, auth guard (`require_login` for the Steam/
  `User` stack, `require_admin!` for the admin stack, none at all for a
  public-data page), rendering. `current_user`/`current_admin_user` (a
  plain `find_by`) is the one model access allowed directly in a
  controller; anything else goes through an action, in whichever stack
  has one. A public-data controller (`InventoriesController`) has no
  guard and nothing to delegate to an action either — its pages are
  reachable signed-in or signed-out alike (see Interaction With Other
  Layers).
- **Actions** (`app/actions/steam/`): `.call` entry point, Sorbet-typed,
  orchestrate `lib/steam/` calls and model persistence for one request-
  scoped operation (e.g. `Steam::LoginUser`). The admin stack has no
  `app/actions/admin/` yet — `admin-authentication.md`'s own
  Responsibilities section already names that as where any future logic
  beyond a single lookup would go, once there's actually logic beyond
  that to extract. The public-data pattern has no action layer by
  design — there's no app_core-side business logic to orchestrate.
- **`lib/steam/`**: external HTTP (Steam OpenID, Steam Web API) and
  crypto (JWT bridge-token minting). No AR references. **`lib/admin/`**:
  the admin stack's sibling folder, crypto only (`Admin::BridgeToken`
  minting) — no external HTTP, since nothing in this stack calls an
  external API.
- **Models** (`app/models/`): persistence + validation only (`User`,
  `AdminUser` — two separate models, no association between them, per
  `admin-authentication.md`/`agent/adr/core/separate-admin-authentication.md`).
- **React island**: reads data embedded in the rendered page (a bridge
  token for an island whose data is per-user or admin-only, plus
  `APP_FETCHER_PUBLIC_URL` always) and fetches data directly from
  `app_fetcher` — never from an `app_core` endpoint. Not every island
  needs a bridge token: the dashboard reads `Api::V1::*` with a
  per-player bridge token; the admin panel reads `Api::Admin::*` with an
  admin bridge token; a public-data island (`inventories/`) reads
  `Api::Public::*` with no `Authorization` header and no token minted by
  its controller at all. Which applies is the endpoint's own auth
  requirement, not a convention this app imposes uniformly on every
  island — and no island crosses into another stack's namespace (the
  dashboard never calls `Api::Admin::`, the admin panel never calls
  `Api::V1::`, etc.).

A plain ERB view may be rendered by more than one controller. The
topbar chrome (brand, nav tabs, sign-in/sign-out state) is a single
`app/views/shared/_topbar.html.erb` partial, rendered by every
page-serving controller across all three patterns above
(`DashboardsController#show`, `InventoriesController#index`/`#show`, and
any sibling), parameterized by which nav tab is active — this is still
"rendering" in the thin-controller sense above, since the partial itself
carries no business logic, just the same current_user-conditional chrome
every one of these pages already needed.

## Responsibilities

Anything beyond a single trivial model lookup (validating a login,
fetching a Steam profile, minting a bridge token) belongs in an action
or `lib/steam/`/`lib/admin/`, not inline in a controller — in whichever
stack the feature belongs to. Each React island owns no server-round-trip
logic of its own beyond calling `app_fetcher` — it has no `app_core` API
to call. This holds the same way regardless of whether that island's
endpoint happens to require a bridge token — a public-data controller
(`InventoriesController`) has nothing to delegate to an action either,
for the same reason `DashboardsController` barely does: there's no
`app_core`-side business logic in any of these pages beyond minting (or,
for a public island, simply not minting) a token for the client.

## Dependencies

One-directional, per `rails-layering.md`. Concretely for this app:

- Steam/`User`-stack controllers depend on actions, `User` (for
  `current_user`), and `Steam::BridgeToken`.
- Admin-stack controllers depend on `AdminUser` (for `current_admin_user`)
  and `Admin::BridgeToken`.
- A public-data controller depends on nothing beyond routing/rendering —
  no model, no action, no `lib/` client.
- Actions depend on `lib/steam/` and models.
- `lib/steam/`/`lib/admin/` depend on nothing else in the app (external
  HTTP/crypto only).
- Each React island depends on `app_fetcher`'s API directly (`Api::V1::`
  for the dashboard, `Api::Admin::` for the admin panel, `Api::Public::`
  for a public-data island), not on any `app_core`-hosted endpoint.
- The stacks never depend on each other — no Steam-stack file reads
  `session[:admin_user_id]`/`AdminUser`/`Admin::BridgeToken`, and no
  admin-stack file reads `session[:user_id]`/`User`/`Steam::BridgeToken`
  (restated here for the layer map's own Dependencies section; the
  authoritative statement of this rule is
  `admin-authentication.md`'s Dependencies section). A public-data
  controller/island reads neither stack's identity at all.

## Rules

### MUST

- Route request-scoped business logic beyond a single model lookup
  through `app/actions/`, not inline in a controller.
- Keep external API calls and crypto operations inside `lib/steam/`/
  `lib/admin/` (or a new `lib/<domain>/`), never inlined into a
  controller or action.
- Have each React island read `app_fetcher`'s matching namespace directly
  from the browser (dashboard → `Api::V1::`, admin panel → `Api::Admin::`,
  a public-data island → `Api::Public::`), authenticated with that
  stack's own bridge token where one applies, embedded in the page by
  that stack's own page-serving controller — the same pattern, applied
  per-island. A public-data island embeds no token at all, since its
  endpoint needs none.

### MUST NOT

- Don't add an `app_core` endpoint that proxies or re-serves
  `app_fetcher` data for any React island to call instead of calling
  `app_fetcher` directly — see ADR for why, and revisit the ADR first if
  a case seems to need one. This applies to every island equally; a new
  island later doesn't get to re-litigate it either.
- Don't perform the Steam OpenID handshake or Steam Web API calls
  outside `lib/steam/`.
- Don't have the admin panel's React island call `Api::V1::` (per-player
  data) or the dashboard's call `Api::Admin::` (admin data) — each island
  stays within its own stack's `app_fetcher` namespace. A public-data
  island never needs to call either authenticated namespace.

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
    → renders shared/_topbar partial (active tab: portfolio) + page with
      token + APP_FETCHER_PUBLIC_URL embedded
        → browser React island fetches app_fetcher's
          Api::V1::InventoriesController / PriceHistoriesController
          directly, Bearer-authenticated with the embedded token

POST /admin/session
    → Admin::SessionsController#create
    → AdminUser.find_by(email:) + #authenticate(password)
        → session[:admin_user_id] = admin_user.id

GET /admin
    → Admin::PanelController#show  (Admin::BaseController, require_admin!)
    → Admin::BridgeToken.encode(current_admin_user.id)  (lib/admin/, 8-hour TTL)
    → renders page with token + APP_FETCHER_PUBLIC_URL embedded
        → browser admin-panel React island fetches app_fetcher's
          Api::Admin::ItemsController / UserInventoriesController / etc.
          directly, Bearer-authenticated with the embedded admin token

GET /inventories, GET /inventories/:steam_id
    → InventoriesController#index / #show
        (no current_user gate — reachable signed-in or signed-out alike;
         mints no bridge token)
    → renders shared/_topbar partial (active tab: inventories) + page
      with APP_FETCHER_PUBLIC_URL embedded, no token
        → browser React island fetches app_fetcher's
          Api::Public::InventoriesController directly, with no
          Authorization header at all
```

## Canonical Implementations

- `app_core/app/actions/steam/login_user.rb`
- `app_core/app/controllers/sessions_controller.rb`
- `app_core/app/controllers/dashboards_controller.rb` — the
  bridge-token-minting controller shape
- `app_core/app/controllers/inventories_controller.rb` — the
  no-bridge-token, no-identity-stack controller shape, same thinness,
  different auth need
- `app_core/app/views/shared/_topbar.html.erb` — the chrome partial
  shared across every page-serving controller above
- `app_core/lib/steam/bridge_token.rb`,
  `app_core/lib/steam/authenticator.rb`,
  `app_core/lib/steam/profile_fetcher.rb`
- `app_core/app/frontend/dashboard/Dashboard.jsx`,
  `app_core/app/frontend/dashboard/hooks/useDashboardData.js` — the
  Bearer-authenticated (per-player) island
- `app_core/app/frontend/inventories/InventoriesIndex.jsx`,
  `app_core/app/frontend/inventories/InventoryDetail.jsx` — the
  unauthenticated island
- Admin stack: `app_core/app/controllers/admin/base_controller.rb`,
  `app_core/lib/admin/bridge_token.rb`, `app_core/app/controllers/
  admin/panel_controller.rb`, `app_core/app/frontend/admin-panel/` — the
  Bearer-authenticated (admin) island

## Related ADR

`agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md`
