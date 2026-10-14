---
description: Api::Admin:: controller conventions in app_fetcher — the CRUD-shaped sibling namespace to Api::V1::/Api::Public::, admin-scoped bridge-token auth, RESTful routing for genuine CRUD resources, and the cache-warm collaborator-count rule.
---

# Admin API Controllers (`Api::Admin::`)

See `agent/adr/fetcher/public-api-namespace.md` for why this namespace
gets its own base controller and independently-declared `rescue_from`
rather than a shared ancestor, and `agent/adr/fetcher/admin-api-crud-routing.md`
for why its routing shape diverges from `Api::V1::`/`Api::Public::`. This
file covers how code inside `Api::Admin::` is written, once both
decisions are taken as given.

## Purpose

Expose `app_fetcher`-owned data (`Item`, `PriceLog`, `UserInventory`,
`InventoryValueLog`) for administrative management: genuine CRUD on
`Item`, read/delete on the others, plus a handful of operator-triggered
actions (`refresh_price`, `sync`, `warm_cache`). What belongs here:
anything gated by "is this an authorized administrator," with no
per-player scoping. What does not: anything scoped to a specific Steam
player (that's `Api::V1::`'s job) or anything with no caller identity at
all (that's `Api::Public::`'s job).

## When to Use

Use this namespace for any endpoint an admin-facing client (currently:
none yet — `app_core`'s admin UI is a separate, later task) needs to
manage `app_fetcher`-owned records directly, independent of any specific
player. Not for anything that should be scoped by `current_steam_id` —
that stays under `Api::V1::`.

## Structure

- `app/controllers/api/admin/<resource>_controller.rb`, nested
  `Api::Admin::<X>Controller`, mirroring `namespace :api do; namespace
  :admin do; ...; end; end` in `config/routes.rb`.
- Unlike `Api::V1::`/`Api::Public::`, genuine CRUD resources use standard
  `resources`, not explicit named routes (see
  `admin-api-crud-routing.md`):
  - `resources :items` (full CRUD) with member routes `post
    :refresh_price` and `post :warm_cache`, plus a nested `resources
    :price_logs, only: %i[index destroy]`.
  - `resources :user_inventories, only: %i[index show destroy], param:
    :steam_id` with member routes `post :sync` and `post :warm_cache`,
    plus a nested `resources :inventory_value_logs, only: %i[index
    destroy]`.
- `Api::Admin::ApplicationController < ActionController::API` — its own
  file, its own `before_action :authenticate_admin_bridge_token!`, its
  own independently-declared `rescue_from StandardError, with:
  :render_internal_server_error` (duplicated from `Api::V1::`'s and
  `Api::Public::`'s, not inherited or shared — per
  `public-api-namespace.md`, not re-decided here).

## Interface

Response-shape conventions are identical to `Api::V1::`'s — not restated
here, see `internal-api-controllers.md`'s own Interface and Error
Handling sections (the same cross-reference `public-api-controllers.md`
already uses for the same reason): every action's `sig` is `{ void }`;
every response is an explicit `render json: { ... }, status:
:some_symbol`; error bodies are always `{ message: "..." }`.

- `authenticate_admin_bridge_token!` requires the JWT's `admin_id` claim
  specifically, decoded with `APP_ADMIN_BRIDGE_JWT_SECRET` — a token that
  decodes but lacks `admin_id` is rejected the same as a missing token.
- `current_admin_id` (set by the above) exists for potential future
  audit-logging use. Unlike `Api::V1::`'s `current_steam_id`, no action
  in this namespace actually scopes a query by it today — there is no
  per-admin data partitioning, every admin sees and manages everything.

## Responsibilities

Same shape as `internal-api-controllers.md`'s Responsibilities: an action
parses params, calls one collaborator, and renders based on that call's
result. For genuine CRUD actions, the one collaborator is the model
itself (`Item.create!`, `item.update!`, `item.destroy!`) — consistent
with these being real CRUD, not an action dressed as one.

**Cache-warm collaborator-count rule**: `ItemsController#warm_cache`
calling `ItemPriceCache.fetch_for`/`PriceHistoryCache.fetch_for`/
`ItemTrendCache.fetch_for` for the one item counts as **one** logical
collaborator, not three, and does not trigger
`internal-api-controllers.md`'s "keep exactly one collaborator call per
action" SHOULD rule. All three calls act on the same id for the same
reason (populate this item's caches) — this is "one resource's own
sibling caches," not two unrelated concerns stitched together in one
action, which is what that SHOULD rule actually guards against. The
grouping itself already has a direct precedent:
`PriceUpdateWorker#update_related_cache` bundles the identical three
calls as one logical step. If a fourth sibling cache is ever added for
`Item`, it joins the same grouping without revisiting this rule.
`UserInventoriesController#warm_cache` only calls `UserInventoryCache`,
so it never raises this question.

## Dependencies

Same dependency set `Api::V1::` already has: may call models (including
scopes) directly for CRUD actions; may enqueue
`PriceUpdateWorker.perform_async` (`refresh_price`) and call
`UserInventorySyncService.call` synchronously (`sync`) — both already
established, unmodified call shapes (see the development plan; not
re-decided here); may call cache classes' `.fetch_for`/`.fetch` directly
for `warm_cache`.

## Rules

### MUST

- Namespace under `Api::Admin::`, with routes declared per Structure
  above.
- Use `resources` (restricted via `only:` where relevant) for every
  genuine CRUD resource in this namespace; keep non-CRUD actions
  (`refresh_price`, `warm_cache`, `sync`) as member routes inside the
  relevant `resources` block — see `admin-api-crud-routing.md`.
- `before_action :authenticate_admin_bridge_token!` on
  `Api::Admin::ApplicationController`, requiring the `admin_id` claim
  explicitly — never accept a token merely because it decodes.
- Look up a record with a raising finder (`find`/`find_by!`) and let
  `Api::Admin::ApplicationController`'s `rescue_from
  ActiveRecord::RecordNotFound` render the `404` — never a manual
  `find_by` + `unless record; render ...; end` guard repeated per action
  (see Error Handling).
- Every request spec in this namespace includes a proof case: a valid
  **per-player** bridge token (`steam_id` claim, signed with
  `APP_BRIDGE_JWT_SECRET`) must be rejected here. This is this
  namespace's analogue of `Api::Public::`'s "succeeds with no
  Authorization header at all" proof case — the one assertion that
  actually proves an endpoint belongs under `Api::Admin::` and not
  `Api::V1::`.
- Build response bodies with a private `*_json` builder method per
  resource shape (see `Api::Public::ItemsController#item_json`), not
  inlined hashes repeated across actions.

### MUST NOT

- Don't reach for `resources` on a non-CRUD action (`refresh_price`,
  `warm_cache`, `sync`) — these stay explicit member routes, the same
  shape every `Api::V1::`/`Api::Public::` action already uses.
- Don't treat `ItemsController#warm_cache`'s three cache calls as a
  reason to extract a builder/action object — see Responsibilities; this
  specific grouping is the one named exception to that SHOULD rule, not
  a general relaxation of it.
- Don't scope any query by `current_admin_id` — there is no per-admin
  partitioning in this namespace today; that field exists for potential
  audit logging only.

## Error Handling

Same three-shape taxonomy as `internal-api-controllers.md`, with
`admin_id` substituted for `steam_id` in the auth-failure shape:

1. **Auth failures** — `:unauthorized` with `{ message: "..." }`: missing
   token, invalid/expired token, or a token that decodes but lacks the
   `admin_id` claim (e.g. a per-player bridge token).
2. **Explicit per-action failure branch** — validation failures on
   `create`/`update` (blank/duplicate `market_hash_name`):
   `:unprocessable_content` with `{ message: "..." }`.
3. **Missing record** — `show`/`update`/`destroy`/`refresh_price`/
   `warm_cache`/the nested `price_logs`/`inventory_value_logs` actions
   look up their record with a raising finder (`Item.find(params[:id])`,
   `UserInventory.find_by!(steam_id: params[:steam_id])`,
   `PriceLog.find_by!(id:, item_id:)`, etc.), never a manual `find_by` +
   `unless record; render :not_found; end` guard. `Api::Admin::
   ApplicationController` declares `rescue_from
   ActiveRecord::RecordNotFound, with: :render_not_found` (`{ message:
   "Not found" }` / `:not_found`), centralizing the 404 shape instead of
   repeating it per action. This is a deliberate divergence from
   `internal-api-controllers.md`'s MUST NOT against a speculative
   `rescue_from` for "a specific exception class that has no live
   trigger" — that rule's own stated reason doesn't apply here, since
   every admin action genuinely operates on a client-supplied id that may
   not exist, unlike `Api::V1::`'s `current_steam_id`-scoped actions.
4. **Unhandled/infra-level failures** — `Api::Admin::
   ApplicationController`'s own `rescue_from StandardError`, logged via
   `Rails.logger.error`, rendering `{ message: "Internal error" }` /
   `:internal_server_error` — same behavior as the other two namespaces',
   declared independently here per `public-api-namespace.md`.

## Interaction With Other Layers

```text
Request (Authorization: Bearer <admin bridge token>)
    ↓
Api::Admin::ApplicationController#authenticate_admin_bridge_token!
    ↓ sets current_admin_id
Api::Admin::<X>Controller action
    ↓ model CRUD  — or —  PriceUpdateWorker.perform_async  — or —
      UserInventorySyncService.call  — or —  cache class .fetch_for/.fetch
    ↓
render json: { ... }, status: :some_symbol
```

## Testing

General RSpec mechanics (spec levels, `FactoryBot`, request-spec
structure) are governed by `agent/styleguides/rspec-conventions.md`;
this section only adds what's specific to this namespace.

### MUST

- Include the per-player-bridge-token-rejected proof case (see Rules)
  in every request spec in this namespace.
- For a resource restricted to `only: %i[index destroy]` (`PriceLogs`,
  `InventoryValueLogs`), assert the absence of create/update routes at
  the routing level (e.g. `expect { post ... }.to raise_error(...)` or an
  equivalent routing assertion) — not just that the controller has no
  corresponding action.
- `warm_cache` specs assert real `Rails.cache` state after the call
  (per `caching.md`'s existing testing rule) — don't mock `Rails.cache`
  or the cache classes.

## Canonical Implementations

- `app_fetcher/app/controllers/api/admin/application_controller.rb` —
  auth, the `rescue_from StandardError`/`rescue_from
  ActiveRecord::RecordNotFound` pair.
- `app_fetcher/app/controllers/api/admin/items_controller.rb` — full
  CRUD, `refresh_price`/`warm_cache`, the `*_json` builder pattern, the
  raising-finder-per-action shape.
- `app_fetcher/app/controllers/api/admin/price_logs_controller.rb`,
  `inventory_value_logs_controller.rb` — the `only: %i[index destroy]`
  nested-resource shape, `find_by!` on a compound (non-primary-key)
  condition.
- `app_fetcher/app/controllers/api/admin/user_inventories_controller.rb`
  — `find_by!` keyed by `steam_id`, the synchronous `sync` action.

## Related ADR

- `agent/adr/fetcher/public-api-namespace.md`
- `agent/adr/fetcher/admin-api-crud-routing.md`
