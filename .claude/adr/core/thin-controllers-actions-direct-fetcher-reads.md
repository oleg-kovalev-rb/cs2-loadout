# Thin Controllers, Actions for Business Logic, Direct React-to-Fetcher Reads

## Status

Accepted

## Context

`app_core` owns almost none of the actual domain data shown on the
dashboard — inventory and price history live in `app_fetcher`.
`app_core`'s own responsibilities are narrower: Steam login
(OpenID handshake + profile fetch + user upsert) and hosting a
Vite-built React dashboard island. Two recurring architectural
questions come up as this app grows:

1. Where does non-trivial request-scoped logic (e.g. everything
   `SessionsController#callback` needs to do on a successful Steam
   login) live relative to the controller that triggers it?
2. How does the React dashboard get `app_fetcher`'s data — proxied
   through an `app_core` backend endpoint, or read directly from
   `app_fetcher`?

Both need an answer before more controllers/features get added, so each
doesn't re-derive its own split.

## Decision

Controllers stay thin and delegate orchestration to `app/actions/`:

```text
Controller
    ↓ current_user / auth only, else delegates immediately
Action (`Steam::LoginUser`, Sorbet `.call` entry point)
    ↓
lib/steam (external API / crypto: Authenticator, ProfileFetcher, BridgeToken)
    ↓
Models (User)
```

A controller touches a model directly only for a simple identity lookup
(`current_user` via `User.find_by`) — anything beyond that single lookup
goes through an action. External API calls and crypto (Steam OpenID
validation, Steam Web API profile fetch, JWT bridge-token minting) live
in `lib/steam/`, never inlined into a controller or action body beyond a
single call to that collaborator.

The React dashboard reads `app_fetcher`'s data by calling `app_fetcher`'s
API **directly from the browser**, authenticated with a short-lived JWT
"bridge token" that `DashboardsController` mints via `Steam::BridgeToken`
and embeds in the rendered page. `app_core`'s own Rails backend does not
proxy, mirror, or re-serve `app_fetcher`'s response shapes.

## Alternatives Considered

### Alternative: fat controllers (inline login orchestration in `SessionsController#callback`)

Rejected because login orchestration (validate OpenID → fetch profile →
find-or-create user) is exactly the multi-step, independently-testable
logic actions exist for. A controller test would otherwise need to stub
the same collaborators (`Steam::Authenticator`, `Steam::ProfileFetcher`)
as an action test, with none of the isolation benefit.

### Alternative: proxy `app_fetcher` data through `app_core`'s own API

Have `app_core`'s Rails backend fetch from `app_fetcher` and re-serve it
to the React island. Rejected because `app_core` would become a
pass-through layer — added latency, and a second place to keep response
shapes in sync with `app_fetcher`'s — for data that gets no
`app_core`-specific transformation. The bridge-token pattern already
gives the browser a scoped, time-limited credential without needing
`app_core` in the data path.

## Consequences

### Positive

- Controller tests stay focused on routing/auth; action tests cover
  orchestration with mocked `lib/steam` collaborators.
- No second API surface in `app_core` to keep in sync with
  `app_fetcher`'s response shapes.
- Adding a new Steam-related orchestration step (e.g. logout cleanup)
  has an obvious home (`app/actions/steam/`) instead of a fresh decision.

### Negative

- The bridge JWT shared secret (`APP_BRIDGE_JWT_SECRET`) is a
  cross-app coupling point that must stay in sync across both apps'
  deployments/config.
- `app_core` cannot apply its own caching, rate-limiting, or
  authorization logic on top of `app_fetcher` reads, since those reads
  never pass through `app_core`'s backend.

### Risks

- A future feature that needs `app_core`-side transformation, caching,
  or per-user authorization on `app_fetcher` data would need a new
  decision — either a proxy endpoint at that point, or extending the
  bridge token's scope. This ADR's "no proxy" decision covers today's
  read-only dashboard case, not every future one.

## Implementation Constraints

- New request-scoped business logic beyond a single model lookup goes
  in `app/actions/`, with a `.call` entry point and Sorbet `sig`s.
- New external API or crypto concerns go in `lib/steam/` (or a new
  `lib/<domain>/` for a non-Steam integration) — never inlined into a
  controller or action.
- If the React island needs new `app_fetcher` data, extend
  `app_fetcher`'s API and the bridge token's claims rather than adding a
  proxy route in `app_core`, unless the data needs `app_core`-only
  enrichment that would justify revisiting this decision.

## Related

- `.claude/styleguides/core/architecture-layers.md`
- `.claude/styleguides/rails-layering.md`
- `.claude/styleguides/fetcher/internal-api-controllers.md` — the
  endpoints the React island calls directly
- `app_core/app/actions/steam/login_user.rb`
- `app_core/app/controllers/sessions_controller.rb`
- `app_core/app/controllers/dashboards_controller.rb`
- `app_core/lib/steam/bridge_token.rb`
