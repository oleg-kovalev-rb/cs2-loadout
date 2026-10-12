---
status: implemented
app: fetcher+core
goal: Backend foundation for admin panel — AdminUser auth in core + Api::Admin namespace in fetcher
created: 2026-10-11
---

# Development Plan

## Goal

Build the backend foundation for an admin panel, with no UI/views in this
task: a separate `AdminUser` authentication system in `app_core`, an
admin-scoped bridge-token channel from `app_core` to `app_fetcher`
(distinct from the existing per-player bridge token), and a new
`Api::Admin` namespace in `app_fetcher` exposing CRUD/actions over `Item`,
`PriceLog`, `UserInventory`, and `InventoryValueLog`, with a cache-warm
action. Admin-triggered Steam calls reuse the existing
`PriceUpdateWorker`/`UserInventorySyncService` unmodified and share their
existing Prop rate-limit buckets with the scheduled pipeline — isolating
them was considered and explicitly deferred (see Risks).

## Expected Behavior

**Normal behavior:**

- An `AdminUser` can authenticate with email+password; on success,
  `session[:admin_user_id]` is set and a subsequent request carrying that
  session is recognized as authenticated by any controller gated with
  `require_admin!`.
- An authenticated admin session can be destroyed (logout), clearing
  `session[:admin_user_id]`.
- `Admin::BridgeToken.encode(admin_id)` (per
  `.claude/styleguides/core/admin-authentication.md`, `lib/admin/`, not
  `lib/steam/`) produces a JWT carrying an `admin_id` claim (not
  `steam_id`), signed with `APP_ADMIN_BRIDGE_JWT_SECRET`, decodable only
  with that secret.
- Requests to any `Api::Admin::*` controller in `app_fetcher` carrying a
  valid admin bridge token (`admin_id` claim, correct secret, not
  expired) are authenticated; `@current_admin_id` is available to the
  action.
- `Api::Admin::ItemsController` supports full CRUD: `create` accepts only
  `market_hash_name` and enqueues an async price fetch; `update` accepts
  `market_hash_name` plus every `store_accessor` metadata field and the
  cached price columns; `destroy` cascades `price_logs` (existing
  `dependent: :destroy`).
- `refresh_price` (member action) enqueues `PriceUpdateWorker` for that
  item, completely unmodified — it shares the scheduler's own
  `steam_price` Prop bucket (see Risks: isolating this was considered and
  explicitly deferred).
- `Api::Admin::PriceLogsController` (nested under an item) supports
  `index`/`destroy` only — no manual create/update.
- `Api::Admin::UserInventoriesController` supports `index`/`show`/
  `destroy`; `sync` (member action) synchronously re-runs
  `UserInventorySyncService.call(steam_id)`, completely unmodified — it
  shares the per-player API's own `steam_inventory` Prop bucket (same
  deferred-isolation note as above).
- `Api::Admin::InventoryValueLogsController` (nested under a steam_id)
  supports `index`/`destroy` only.
- `warm_cache` member action exists on both `ItemsController` (covers
  `ItemPriceCache`/`PriceHistoryCache`/`ItemTrendCache` via their
  existing `.fetch_for` read-through) and `UserInventoriesController`
  (covers `UserInventoryCache` via `.fetch`) — standalone, with no write
  attached, since read-through methods carry no "writer-only"
  restriction in `caching.md`.
- No standalone cache-invalidation action exists. Cache invalidation
  only happens as part of an action that already writes:
  `refresh_price` invalidates via `PriceUpdateWorker`'s existing
  `update_related_cache` (unchanged, already-authorized writer); `sync`
  invalidates via `UserInventorySyncService`'s existing internal
  `UserInventoryCache.invalidate` call (also unchanged, also
  already-authorized). No new `.invalidate` caller is introduced
  anywhere.

**Edge cases:**

- `create` with a `market_hash_name` that doesn't exist on Steam:
  record is created, `refresh_price` enqueues normally, the worker's
  existing "not found" handling (`Steam::Response` `404`) leaves
  `current_price_cents` nil — this is already-existing, unchanged
  worker behavior, not new logic.
- An admin-created `Item` has `metadata == {}` by default, so it is
  invisible to `Item.due_for_price_update` (`marketable.stale_or_unpriced`)
  until `marketable: true` is set via `update` or until a future
  inventory sync encounters it — existing scope behavior, unchanged.
- `sync` for a `steam_id` with no prior `UserInventory` row: identical
  cold-start behavior to the existing `InventoriesController#show`/
  `#refresh` carve-out (creates the row via `UserInventory.sync!`).

**Failure behavior:**

- Missing/malformed/expired admin bridge token → `401` with
  `{ message: "..." }`, mirroring `authenticate_bridge_token!`'s exact
  shape.
- A regular per-player bridge token (carrying `steam_id`, signed with
  `APP_BRIDGE_JWT_SECRET`) presented to an `Api::Admin::*` endpoint is
  rejected — different secret means it fails to decode at all; even if
  secrets ever collided, `admin_id` claim is explicitly required and
  `steam_id`-only payloads are rejected.
- `create`/`update` with blank or duplicate `market_hash_name` →
  `422`/`:unprocessable_entity` (or `:bad_request`, see Implementation
  Steps) with validation message, via existing `Item` validations
  (`presence`, `uniqueness`).
- `destroy`/`show`/`sync` for a non-existent `id`/`steam_id` → `404`.

**Behavior that must remain unchanged:**

- `Api::V1::*` and `Api::Public::*` controllers,
  `authenticate_bridge_token!`, `PriceScheduler`/
  `UserInventorySyncScheduler` cron behavior, and
  `Steam::Client`/`PriceUpdateWorker`/`UserInventorySyncService` (no
  signature changes of any kind) are unchanged.

## Scope

### In Scope

- `app_core`: `AdminUser` model + migration, `Admin::BaseController` +
  `Admin::SessionsController` (backend only — JSON/head responses, no
  views), `Admin::BridgeToken`.
- `app_fetcher`: `Api::Admin::ApplicationController` (third namespace,
  own `rescue_from`, admin bridge-token auth) and four resource
  controllers (`Items`, `PriceLogs`, `UserInventories`,
  `InventoryValueLogs`) per Expected Behavior above.
- A standalone cache-warm admin action (DB+Redis only, no Steam calls);
  no standalone cache-invalidate action (see Implementation Approach).
- Full RSpec coverage for every new/changed component.

### Out of Scope

- Any admin UI: views, forms, navigation, styling — a separate follow-up
  task once this API contract is stable.
- `Api::BaseController` extraction — explicitly deferred per project
  decision; `Api::Admin::ApplicationController` duplicates `rescue_from`
  a third time instead.
- Historical price backfill (`market/pricehistory`) — requires a
  session-cookie Steam credential this project doesn't have; not part of
  this task.
- Granular admin permissions/roles — `AdminUser` is a single flat role.
- Pagination/search/filtering on `Api::Admin::ItemsController#index` —
  basic unfiltered listing only; add later if the (future) UI needs it.
- `ItemCatalogCache` invalidate/warm — it's keyed by arbitrary filter
  combinations, not a single `Item`/`UserInventory` id, and wasn't part
  of the agreed per-resource cache-button scope.
- Deduplicating rapid repeated clicks on `refresh_price`/`sync` (the
  existing warmup-dedup pattern from `caching.md` is not applied here —
  see Risks).
- Isolating admin-triggered Steam calls from the scheduled pipeline's
  rate-limit budget — `refresh_price`/`sync` share the existing
  `steam_price`/`steam_inventory` Prop buckets with `PriceScheduler`/
  `UserInventorySyncScheduler` as-is. Explicitly accepted for now (see
  Risks); revisit only if it becomes a real operational problem.

## Implementation Approach

**`app_core` auth layer** follows
`.claude/styleguides/core/admin-authentication.md` (backed by
`.claude/adr/core/separate-admin-authentication.md`): a parallel,
unconnected stack to the existing `User`/`SessionsController`/
`Steam::BridgeToken` shape, not an extension of it. `AdminUser` has no
relation to `User`; `Admin::SessionsController` has no relation to
`SessionsController`; `Admin::BridgeToken` (at `lib/admin/bridge_token.rb`
— a new domain folder, sibling to `lib/steam/`, not inside it) has no
relation to `Steam::BridgeToken` beyond shared JWT mechanics (HS256,
`exp`/`iat`). `Admin::BaseController` (not `ApplicationController`
itself) carries `before_action :require_admin!`, matching
`core/architecture-layers.md`'s existing "thin controller" posture —
`current_admin_user` does a single `AdminUser.find_by(id:)` lookup,
nothing more.

**`app_fetcher`'s `Api::Admin` namespace** follows
`.claude/styleguides/fetcher/admin-api-controllers.md` (backed by
`.claude/adr/fetcher/public-api-namespace.md` and
`.claude/adr/fetcher/admin-api-crud-routing.md`): its own
`ApplicationController < ActionController::API`, its own
independently-declared `rescue_from StandardError`, matching
`Api::V1`/`Api::Public`'s existing behavior verbatim (same log call, same
rendered body/status) — this is the ADR's anticipated "third namespace,"
and per explicit project decision (recorded in `public-api-namespace.md`'s
"Update: Third-Namespace Trigger Reached" note) the triggered
`Api::BaseController` extraction is deferred, not performed here. Unlike
`Api::V1`/`Api::Public`, `Items` (genuine CRUD) routes via standard
`resources :items`, with nested `resources :price_logs, only: %i[index
destroy]`; non-CRUD actions (`refresh_price`, `warm_cache`, `sync`) stay
explicit member routes — see `admin-api-crud-routing.md` for why this
namespace is the one deliberate exception to the other two namespaces'
"never bare `resources :x`" rule.

**Reused services, not new Steam integration:** per project decision,
`refresh_price`/`create` enqueue the existing `PriceUpdateWorker`
unmodified in shape (same `Steam::Client#fetch_item_price` →
`PriceUpdateService` chain); `sync` calls `UserInventorySyncService.call`
directly and synchronously — this is not a new carve-out, since
`.claude/adr/fetcher/cross-scenario-service-layer.md` already
authorizes exactly this service being called synchronously from a
controller (precedent: `InventoriesController#show`/`#refresh`).

**Rate-limit isolation was considered and explicitly dropped**: an
earlier version of this plan threaded an optional caller-supplied
`limit_key` through `Steam::Client`/`PriceUpdateWorker`/
`UserInventorySyncService` so admin-triggered calls would throttle
against their own Prop bucket instead of the scheduler's. Per explicit
project decision, this is not done — `refresh_price`/`sync` call the
existing worker/service completely unmodified and share
`steam_price`/`steam_inventory` with `PriceScheduler`/
`UserInventorySyncScheduler` as-is. This means `Steam::Client`,
`PriceUpdateWorker`, and `UserInventorySyncService` are untouched by this
task — see Risks for the accepted trade-off.

**Response bodies** are built the same way `Api::Public::ItemsController`
already does it — private `*_json` builder methods per controller,
explicit `render json: { ... }, status: :symbol` — no new serialization
abstraction introduced for four controllers.

**Cache actions, reconsidered to avoid a new `.invalidate` caller**: an
earlier version of this plan had a standalone `invalidate_cache` action
calling `.invalidate` directly from `Api::Admin::*`, independent of any
write — `caching.md`'s MUST rule ties `.invalidate` specifically to "the
writer... immediately after its own successful write," and `Api::Admin`
would not have been that writer for a bare invalidate-only call. Instead:
`warm_cache` stays a standalone action (calls `.fetch_for`/`.fetch`,
which carry no writer restriction), and invalidation only ever happens
inside `refresh_price`/`sync` — both of which already invalidate as part
of their own write, via the exact same already-authorized writers
(`PriceUpdateWorker`, `UserInventorySyncService`) `caching.md` already
names. No new cache-layer code and no new `.invalidate` caller are
introduced anywhere.

## Files To Modify

**`app_core`:**

- `app_core/Gemfile` — uncomment `gem "bcrypt", "~> 3.1.7"`; needed for
  `AdminUser#has_secure_password`.
- `app_core/config/routes.rb` — add
  `namespace :admin do resource :session, only: %i[create destroy] end`.

**`app_fetcher`:**

- `app_fetcher/config/routes.rb` — add an `Api::Admin` namespace block
  with the four resources and their member actions (see Implementation
  Steps for exact shape).

No other existing `app_fetcher` file is modified —
`Steam::Client`/`PriceUpdateWorker`/`UserInventorySyncService`/
`config/initializers/prop.rb` are untouched (see Implementation Approach
and Risks).

## Files To Create

**`app_core`:**

- `app_core/db/migrate/<timestamp>_create_admin_users.rb` — `admin_users`
  table: `email` (string, not null), `password_digest` (string, not
  null), timestamps, unique index on `email`.
- `app_core/app/models/admin_user.rb` — `has_secure_password`, validates
  `email` presence/uniqueness (case-insensitive) and format.
- `app_core/app/controllers/admin/base_controller.rb` —
  `before_action :require_admin!`, `current_admin_user` helper.
- `app_core/app/controllers/admin/sessions_controller.rb` — `create`
  (authenticate by email/password, set session, `head :ok` or render
  minimal JSON) / `destroy` (clear session, `head :ok`) — see Assumptions
  for why this is JSON/head-shaped rather than a redirect.
- `app_core/lib/admin/bridge_token.rb` — `Admin::BridgeToken` (new
  `lib/admin/` domain folder, per `admin-authentication.md` — not
  `lib/steam/`), mirrors `Steam::BridgeToken` exactly except the claim
  name and secret.
- `app_core/spec/factories/admin_users.rb`,
  `app_core/spec/models/admin_user_spec.rb`,
  `app_core/spec/requests/admin/sessions_spec.rb`,
  `app_core/spec/lib/admin/bridge_token_spec.rb`.

**`app_fetcher`:**

- `app_fetcher/app/controllers/api/admin/application_controller.rb` —
  third base controller; `authenticate_admin_bridge_token!` requiring an
  `admin_id` claim, decoded with `APP_ADMIN_BRIDGE_JWT_SECRET`; own
  `rescue_from StandardError` (duplicated, per explicit decision).
- `app_fetcher/app/controllers/api/admin/items_controller.rb` — `index`,
  `show`, `create`, `update`, `destroy`, `refresh_price`, `warm_cache`
  (no `invalidate_cache` — see Implementation Approach).
- `app_fetcher/app/controllers/api/admin/price_logs_controller.rb` —
  `index`, `destroy`, scoped to `params[:item_id]`.
- `app_fetcher/app/controllers/api/admin/user_inventories_controller.rb`
  — `index`, `show`, `destroy`, `sync`, `warm_cache` (no
  `invalidate_cache`), keyed by `steam_id`.
- `app_fetcher/app/controllers/api/admin/inventory_value_logs_controller.rb`
  — `index`, `destroy`, scoped to `params[:user_inventory_steam_id]`.
- `app_fetcher/spec/support/admin_bridge_token_helper.rb` — mirrors
  `bridge_token_helper.rb`, encoding `admin_id` with
  `APP_ADMIN_BRIDGE_JWT_SECRET`.
- `app_fetcher/spec/requests/api/admin/items_spec.rb`,
  `price_logs_spec.rb`, `user_inventories_spec.rb`,
  `inventory_value_logs_spec.rb`.
- `app_fetcher/spec/factories/admin_... ` — none expected beyond
  existing `items`/`price_logs`/`user_inventories`/`inventory_value_logs`
  factories, which already exist and are reused as-is.

## Test Plan

- **Unit** (no `type:`): `AdminUser` validations/`has_secure_password`
  (`app_core/spec/models/admin_user_spec.rb`); `Admin::BridgeToken`
  encode/decode + wrong-secret rejection, mirroring
  `bridge_token_spec.rb`'s two cases exactly.
- **Request** (`type: :request`):
  - `app_core/spec/requests/admin/sessions_spec.rb` — valid login sets
    session; invalid email/password rejected; logout clears session.
  - `app_fetcher/spec/requests/api/admin/items_spec.rb` — auth cases
    (missing/invalid/wrong-claim token, and a valid *per-player* bridge
    token explicitly rejected); CRUD happy path; `create` with blank/
    duplicate `market_hash_name` rejected; `refresh_price` enqueues
    `PriceUpdateWorker` (assert via `Sidekiq::Testing.fake!` +
    `PriceUpdateWorker.jobs`, same job shape the scheduler already
    enqueues); `warm_cache` asserts real `Rails.cache` state per
    `caching.md`'s testing rule (no mocking `Rails.cache` or the cache
    classes).
  - `app_fetcher/spec/requests/api/admin/price_logs_spec.rb` — index
    scoped to item, destroy; no create/update routes exist (verify via
    routing, not just controller).
  - `app_fetcher/spec/requests/api/admin/user_inventories_spec.rb` —
    CRUD subset; `sync` exercises the real `UserInventorySyncService`
    path with Steam stubbed via `WebMock` (matching existing
    `inventories_spec.rb` convention).
  - `app_fetcher/spec/requests/api/admin/inventory_value_logs_spec.rb` —
    index scoped to steam_id, destroy.

No existing spec file needs updating — `Steam::Client`/
`PriceUpdateWorker`/`UserInventorySyncService` and their specs are
untouched.

## Implementation Steps

1. `app_core`: uncomment `bcrypt` in `Gemfile`, `bundle install`.
2. `app_core`: generate `CreateAdminUsers` migration, run it, write
   `AdminUser` model + validations + spec + factory.
3. `app_core`: write `Admin::BridgeToken` (`lib/admin/bridge_token.rb`) +
   spec, mirroring `bridge_token.rb`/`bridge_token_spec.rb` 1:1 except
   claim name/secret and the `lib/admin/` vs. `lib/steam/` location.
4. `app_core`: write `Admin::BaseController` + `Admin::SessionsController`,
   add routes, write request specs.
5. `app_fetcher`: write `Api::Admin::ApplicationController` +
   `authenticate_admin_bridge_token!` + `admin_bridge_token_helper.rb`
   spec support file.
6. `app_fetcher`: write `Api::Admin::ItemsController` (CRUD +
   `refresh_price` + `warm_cache`), add routes, write request specs.
7. `app_fetcher`: write `Api::Admin::PriceLogsController` (nested
   index/destroy), add routes, write request specs.
8. `app_fetcher`: write `Api::Admin::UserInventoriesController`
   (index/show/destroy + `sync` + `warm_cache`), add routes, write
   request specs.
9. `app_fetcher`: write `Api::Admin::InventoryValueLogsController`
   (nested index/destroy), add routes, write request specs.
10. Run full test suites for both apps; run Sorbet typecheck
    (`bundle exec srb tc`) for `app_fetcher`; run the project's lint
    suite if configured in either app.

## Verification

- `bundle exec rspec` (full suite) in `app_core` and `app_fetcher`.
- `bundle exec srb tc` in `app_fetcher` (Sorbet is required on every new
  hand-written file per `ruby-sorbet.md`).
- Project lint/formatter if configured (e.g. Rubocop) in either app.
- Manual smoke check (no UI available): exercise each new endpoint via
  `curl`/HTTPie with a hand-minted admin bridge token, confirming auth
  rejection and the full CRUD + action set behave as specified.

## Risks

- **Admin Steam calls share the scheduled pipeline's Prop buckets** —
  `refresh_price`/`sync` throttle against the exact same `steam_price`/
  `steam_inventory` buckets as `PriceScheduler`/
  `UserInventorySyncScheduler`. A burst of admin clicks could consume
  quota the scheduler needs (or vice versa). Explicitly accepted for now,
  per project decision — isolating the two was considered and dropped
  rather than silently omitted; revisit only if this causes a real
  operational problem (e.g. admin actions visibly delaying scheduled
  price updates).
- **`Api::BaseController` extraction deferred** despite
  `public-api-namespace.md`'s own stated trigger ("third namespace needs
  the identical error-handling shape") now being met. This is a
  deliberate, acknowledged decision (not an oversight) — revisit later
  per that ADR's explicit guidance.
- **No dedup on `refresh_price`/`sync` repeated clicks** — unlike the
  existing warmup-dedup pattern (`Rails.cache.write(..., unless_exist:
  true, ...)`), admin actions here enqueue/call unconditionally on every
  request. Accepted as a deliberate simplification given low, human-paced
  call volume — not applied here to avoid adding complexity the task
  doesn't need yet.
- **Admin session response shape has no UI precedent to copy** (see
  Assumptions) — may need revisiting once the UI task defines the real
  login flow/redirect target.
- **Admin-created bare `Item` is invisible to `PriceScheduler`** until
  `marketable: true` is set (existing scope behavior, not changed here)
  — confirm this is acceptable operational behavior, not a gap to close
  in this task.

## Assumptions

- No `.env.example`/credentials file exists in either app to document
  `APP_ADMIN_BRIDGE_JWT_SECRET` — assumed to be supplied via deployment
  environment directly, same as the existing `APP_BRIDGE_JWT_SECRET`.
- `Admin::SessionsController#create`/`#destroy` return JSON/`head`
  responses rather than redirects, since no admin UI route exists yet to
  redirect to — a necessary design call for this backend-only phase, not
  dictated by any existing precedent (the existing `SessionsController`
  redirect flow is OAuth-specific and doesn't transfer directly to an
  email+password POST).
- REST shape (nesting `PriceLog` under `Item`, `InventoryValueLog` under
  `UserInventory`'s `steam_id`, and which actions are plain member routes
  vs. separate nested resources) is now settled, not an open assumption —
  see `.claude/adr/fetcher/admin-api-crud-routing.md`, created during
  `styleguides-check` specifically to resolve this.

## Completion Criteria

- Desired behavior explicit (see Expected Behavior).
- Scope explicit (see Scope).
- Affected/new files identified (see Files To Modify/Create).
- Test strategy defined (see Test Plan).
- Implementation steps ordered (see Implementation Steps).
- Verification defined (see Verification).
- Plan written to `.claude/plans/admin-panel-backend-foundation.md`.

## Applicable Styleguides

**Shared:**

- `.claude/styleguides/rails-layering.md` — one-directional dependency
  flow and "thin controller, delegate beyond a single lookup" posture,
  constraining both `Admin::BaseController` (core) and every
  `Api::Admin::` controller (fetcher).
- `.claude/styleguides/ruby-sorbet.md` — `# typed: strict`, `extend
  T::Sig`, a `sig` on every method — constrains every new file this plan
  creates in both apps.
- `.claude/styleguides/rspec-conventions.md` — spec-level mapping
  (unit/request), `FactoryBot` over fixtures, request-spec structure —
  constrains the entire Test Plan.
- `.claude/styleguides/git-commits.md` — commit message format for
  `implement-plan`'s commits.

**`app_fetcher`:**

- `.claude/styleguides/fetcher/admin-api-controllers.md` — directly
  governs all four `Api::Admin::` controllers: routing shape, `admin_id`
  claim, response/error shape (by reference to
  `internal-api-controllers.md`), the `warm_cache` collaborator-count
  rule, and the per-player-bridge-token-rejected testing proof case.
- `.claude/adr/fetcher/admin-api-crud-routing.md` — why `Items` routes
  via `resources`/nested `resources` rather than explicit named routes,
  unlike `Api::V1::`/`Api::Public::`.
- `.claude/adr/fetcher/public-api-namespace.md` — why `Api::Admin::` gets
  its own base controller and independently-declared `rescue_from`
  rather than a shared ancestor; now explicitly records that the
  third-namespace revisit trigger fired with `Api::Admin::` and was
  deliberately deferred again.
- `.claude/styleguides/fetcher/internal-api-controllers.md` — the
  response/error shape (`render json: { ... }, status: :symbol`, `{
  message: "..." }` bodies, three-shape error taxonomy) `Api::Admin::`
  inherits by reference, not restated.
- `.claude/adr/fetcher/cross-scenario-service-layer.md` — authorizes
  `sync`'s synchronous, controller-level `UserInventorySyncService.call`
  (same precedent as `InventoriesController#show`/`#refresh`).
- `.claude/styleguides/fetcher/caching.md` — governs `warm_cache`'s
  unrestricted `.fetch_for`/`.fetch` read-through calls, and confirms
  `refresh_price`/`sync`'s existing invalidate-on-write calls (via
  `PriceUpdateWorker`/`UserInventorySyncService`) need no new
  authorization — no standalone invalidate caller is introduced.
- `.claude/adr/fetcher/steam-client-response-objects-and-rate-limiting.md`
  — confirms the plan stays compliant by construction: `refresh_price`/
  `sync` reuse the existing `Steam::Client`/`Prop.throttle!` choke point
  completely unmodified, introducing no bypass and no new rate-limiting
  pattern.

**`app_core`:**

- `.claude/styleguides/core/admin-authentication.md` — directly governs
  `AdminUser`, `Admin::BaseController`/`Admin::SessionsController`, and
  `Admin::BridgeToken` (session-key separation, `require_admin!` gating,
  JSON/`head` response shape, `lib/admin/` file placement).
- `.claude/adr/core/separate-admin-authentication.md` — why this stack is
  wholly separate from `User`/`Steam::BridgeToken` rather than an
  extension of either.
- `.claude/styleguides/core/architecture-layers.md` — the existing
  single-identity layer map this new stack runs parallel to, without
  modifying it.
- `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  the thin-controller/single-lookup posture `Admin::BaseController`'s
  `current_admin_user` follows.

# Implementation Summary

## Implemented

**`app_core`:**
- `AdminUser` model (`app/models/admin_user.rb`) — `has_secure_password`,
  email presence/uniqueness (case-insensitive)/format validation,
  downcased before save. Migration `db/migrate/20261011120000_create_admin_users.rb`.
- `Admin::BridgeToken` (`lib/admin/bridge_token.rb`) — mirrors
  `Steam::BridgeToken` exactly except claim (`admin_id`) and secret
  (`APP_ADMIN_BRIDGE_JWT_SECRET`).
- `Admin::BaseController` (`require_admin!`/`current_admin_user`) and
  `Admin::SessionsController` (`create`/`destroy`, JSON responses) +
  routes (`namespace :admin do resource :session, only: %i[create destroy] end`).
- `bcrypt` uncommented in `Gemfile`.

**`app_fetcher`:**
- `Api::Admin::ApplicationController` — third base controller,
  `authenticate_admin_bridge_token!` (requires `admin_id` claim + correct
  secret; a per-player token or one missing the claim is rejected the
  same as a missing token), own `rescue_from StandardError`.
- `Api::Admin::ItemsController` — full CRUD (`create` accepts only
  `market_hash_name`; `update` accepts all metadata fields + cached price
  columns), `refresh_price` (enqueues `PriceUpdateWorker`, unmodified),
  `warm_cache` (calls `ItemPriceCache`/`PriceHistoryCache`/`ItemTrendCache`
  `.fetch_for` — one logical collaborator per `admin-api-controllers.md`).
- `Api::Admin::PriceLogsController` — `index`/`destroy`, nested under
  `items`, scoped to `item_id`.
- `Api::Admin::UserInventoriesController` — `index`/`show`/`destroy`,
  `sync` (synchronous `UserInventorySyncService.call`), `warm_cache`
  (`UserInventoryCache.fetch`).
- `Api::Admin::InventoryValueLogsController` — `index`/`destroy`, nested
  under `user_inventories`, scoped to `steam_id`.
- Routes: `resources :items`/nested `resources :price_logs, only: %i[index destroy]`;
  `resources :user_inventories, only: %i[index show destroy], param: :steam_id`/
  nested `resources :inventory_value_logs, only: %i[index destroy]`; member
  routes for `refresh_price`/`warm_cache`/`sync` — per
  `admin-api-crud-routing.md`.
- `vcr` gem added + configured in `rails_helper.rb` (first use in either
  app) for the `sync` action's request-spec Steam-call boundary, per
  `rspec-conventions.md`'s MUST rule (request-level Steam calls use a VCR
  cassette, not hand-written `WebMock`).

## Tests

- `app_core/spec/models/admin_user_spec.rb` (7 examples) — validations,
  email normalization, `has_secure_password`.
- `app_core/spec/lib/admin/bridge_token_spec.rb` (3 examples) — claim/TTL
  round-trip, wrong-secret rejection, per-player-secret rejection.
- `app_core/spec/requests/admin/sessions_spec.rb` (6 examples) —
  login/logout, case-insensitive email, bad credentials.
- `app_fetcher/spec/requests/api/admin/items_spec.rb` (14 examples),
  `price_logs_spec.rb` (5), `user_inventories_spec.rb` (8),
  `inventory_value_logs_spec.rb` (5) — auth (missing/garbage/expired
  token, per-player-token-rejected proof case), CRUD, `refresh_price`/
  `sync`/`warm_cache`, 404s, routing-level proof that `PriceLogs`/
  `InventoryValueLogs` expose no create/update route.
- `app_fetcher/spec/cassettes/.../syncs_the_inventory_from_Steam_creating_missing_items.yml` —
  hand-authored VCR cassette (a real request was attempted first; Steam
  returned 401 for the synthetic steam_id, so the recorded interaction
  was replaced with a realistic success body matching
  `Steam::Response::Data::InventoryData`'s expected shape).
- `app_fetcher/spec/support/admin_bridge_token_helper.rb` — mirrors
  `bridge_token_helper.rb` for the new claim/secret.

Commands actually executed (via `docker-compose run` against `db_core`/
`db_fetcher`/`redis` containers brought up in this worktree — no network
access to the main project's stack):
- `bundle exec rspec` (scoped, then full suite) in both apps, repeatedly
  through the RED/GREEN cycle for each component.
- `bundle exec rubocop` (scoped, then full `app_fetcher`/`app_core`) —
  `-A` autocorrect only for array-bracket spacing in `items_spec.rb`.
- `bundle exec srb tc` (full project) in both apps, before and after each
  new file, diffed against the pre-existing error set.
- `bundle exec tapioca dsl AdminUser` (`app_core`) and
  `bundle exec tapioca dsl PriceLog UserInventory InventoryValueLog`
  (`app_fetcher`) — per `ruby-sorbet.md`'s MUST rule.

## Verification

- **`app_fetcher` full suite**: 226 examples, 1 failure. The failure
  (`spec/caching/user_inventory_cache_spec.rb:18`) is a confirmed
  pre-existing bug unrelated to this plan — logged in `fix_me.md`, not
  fixed (see Deviations).
- **`app_core` full suite**: 25 examples, 6 failures — all 6 are the
  pre-existing `dashboards_spec.rb` Vite/`@vitejs/plugin-react`
  asset-build failures (confirmed as the baseline before any change in
  this session); none are new.
- **Rubocop**: zero offenses in any file this plan created or modified,
  in either app. Both apps have pre-existing offenses in untouched files
  (confirmed via full-project runs); none attributable to this work.
- **Sorbet (`bundle exec srb tc`)**: neither app reaches a zero-error
  exit — both have a substantial pre-existing baseline (missing/stale
  gem RBIs for `jwt`/`rspec-rails`/`factory_bot_rails`/`sidekiq`, logged
  in `fix_me.md`, confirmed via identical errors on untouched files like
  `item_prices_controller.rb`/`inventory_value_scheduler.rb`). Every
  error remaining in a file this plan created maps to that same
  pre-existing gap category — none is a genuinely new type error. Two
  real, fixable gaps surfaced and were fixed as part of this work (see
  Deviations: `AdminUser`'s missing safe-nav removal, and the three new
  `tapioca dsl` RBIs for `PriceLog`/`UserInventory`/`InventoryValueLog`,
  which also happened to clear 16 pre-existing errors in untouched V1
  files as a side effect).
- Manual smoke check via `curl`-equivalent `docker-compose run` requests
  was effectively covered by the request specs themselves (same
  Rack-level dispatch); not separately repeated.

## Deviations

- **`Steam::AdminBridgeToken`/`lib/steam/admin_bridge_token.rb` (plan's
  original naming) → `Admin::BridgeToken`/`lib/admin/bridge_token.rb`.**
  Corrected during `styleguides-check` once `admin-authentication.md`
  established this isn't Steam-domain code; the plan was updated in
  place before implementation started, so this isn't a deviation from
  the *final* plan — noted here for anyone comparing against an earlier
  read of this file.
- **Fixed a real, pre-existing runtime bug in `app_fetcher/app/models/item.rb`'s
  `#stattrak`** (`super.nil? ? false : super` → `!!metadata["stattrak"]`).
  The original raised `TypeError: Return value: Expected type T::Boolean,
  got type String with value "stattrak"` whenever `.stattrak` was called
  on an item loaded via a relation query (not a freshly-`.create!`d
  instance) with no `"stattrak"` key in `metadata` — reproducible with
  zero controller code involved. This blocked `Api::Admin::ItemsController#index`/
  `#show` outright (any 2+-item listing would 500), so it had to be
  fixed, not deferred to `fix_me.md`. Root cause traced to
  `ActiveRecord::Store`'s generated reader (`item.method(:stattrak).super_method.call`)
  returning the attribute's own key name instead of the stored value in
  that specific case — not fully root-caused beyond that (looks like a
  Rails/Sorbet-runtime interaction bug); the fix sidesteps it entirely by
  reading `metadata` directly instead of going through the buggy `super`
  path. `Api::Public::ItemsController#item_json` (which also calls
  `.stattrak`) benefits from the same fix; its own spec never happened to
  combine "2+ items in one query" with "missing `stattrak` key," so the
  bug never surfaced there. Logged in `fix_me.md` for traceability even
  though it's fixed (not left outstanding).
- **Generated three previously-missing Sorbet DSL RBIs** (`PriceLog`,
  `UserInventory`, `InventoryValueLog`) in `app_fetcher`, beyond the plan's
  original file list. Required for `Api::Admin::PriceLogsController`/
  `UserInventoriesController`/`InventoryValueLogsController`'s own plain
  column access to type-check per `ruby-sorbet.md`'s MUST rule; as a side
  effect, also cleared 16 pre-existing errors in untouched `Api::V1::`
  files that read the same columns.
- **Request specs with a JSON body use `as: :json`** (e.g. `PATCH
  .../items/:id` with `marketable: true`) — not specified in the plan.
  Needed because form-encoded params stringify everything, so
  `marketable` would be stored as the string `"true"` instead of a real
  boolean; `as: :json` sends (and `ActionController::Parameters` parses)
  a genuine JSON boolean. Consistent with this being a JSON API, not a
  deviation from any stated convention.
- **Test market_hash_names avoid `"AK-47 | Redline (Field-Tested)"`**
  (used `"AWP | Dragon Lore (Factory New)"`/`"AWP | Asiimov (Field-Tested)"`
  instead) — that exact string is the existing `items(:redline)` global
  fixture (`config.global_fixtures = :all`), always present in every
  example regardless of per-example transactional rollback; using it
  collided with pre-existing data and produced misleading failures during
  development. Not a fixture change, just picked different literals in
  new tests.
- **`:unprocessable_entity` → `:unprocessable_content`** in the new
  `ItemsController` and its spec — the former is a deprecated Rack status
  symbol (confirmed via a live deprecation warning); used the current one
  from the start rather than introducing already-deprecated code.

## Remaining Issues

- `spec/caching/user_inventory_cache_spec.rb:18` fails on a confirmed
  pre-existing version-mismatch bug (spec expects cache key version `2`,
  code has `1`, per `git log` — reverted in `2bd64c5` without updating
  the spec). Unrelated to this plan; logged in `fix_me.md`, not fixed.
- All Risks/Out-of-Scope items from the plan stand as written (no admin
  UI, no `Api::BaseController` extraction, no rate-limit isolation
  between admin and scheduled Steam calls, no price-history backfill,
  single flat `AdminUser` role). None were revisited during
  implementation.
- The broader pre-existing Sorbet gem-RBI gap (`jwt`/`rspec-rails`/
  `factory_bot_rails`/`sidekiq` in `app_fetcher`; `jwt`/`rspec-rails`/
  `factory_bot_rails` in `app_core`; `User`'s own missing DSL RBI in
  `app_core`) remains open — logged in `fix_me.md`, a project-wide
  `tapioca gems`/`tapioca dsl User` run, out of scope for this plan.

## Post-Implementation Follow-Up

Per review feedback, all four `Api::Admin::` controllers were refactored
to use a raising finder (`find`/`find_by!`) plus a centralized
`rescue_from ActiveRecord::RecordNotFound, with: :render_not_found` on
`Api::Admin::ApplicationController`, replacing the original per-action
`find_by` + `unless record; render :not_found; end` guard. Behavior is
unchanged (same `404`/`{ message: "Not found" }` shape); this is purely
an implementation-mechanism simplification. `admin-api-controllers.md`
was amended in place to document the mechanism (new Error Handling
shape-3 entry, a new MUST rule, and a populated Canonical
Implementations section) — no new ADR needed, this doesn't reopen the
`internal-api-controllers.md` "no speculative `rescue_from` without a
live trigger" question, it's the same resolution already reasoned
through in that file's Error Handling section (admin genuinely has a
live trigger). Re-verified: `app_fetcher` full suite 226 examples/1
failure (same pre-existing one), rubocop clean, no new Sorbet errors
(102, same count as before the refactor).

Incidentally caught and fixed during this follow-up: an earlier
broad-stroke `chown -R` (done mid-implementation to fix Docker-root-owned
file permissions) had recursively touched the bind-mounted
`postgres_fetcher_data`/`postgres_core_data` directories too, breaking
the running Postgres containers' own file permissions (they expect uid
999). Restored via a scoped `chown -R 999:999` on just those two
directories and restarted the containers — not a code change, noted here
only so the cause of a mid-session Postgres outage in this worktree's
ad-hoc containers isn't a mystery later.

Per further review feedback, `AdminUser`'s `downcase_email` (a
`before_validation`-triggered private method) was replaced with Rails
7.1+'s declarative `normalizes :email, with: ->(email) { email.downcase }`
— no separate method/`sig` needed, and `normalizes` already skips `nil`
internally (the `email.to_s` guard this plan originally needed is no
longer necessary). `Admin::SessionsController#create`'s lookup was
updated to match, using `AdminUser.normalize_value_for(:email,
params[:email])` instead of a second, hand-duplicated `.to_s.downcase` —
one source of truth for the normalization now, not two. Added a
regression case (`"rejects a request with no email param at all"`) to
`sessions_spec.rb` covering the nil-param path through
`normalize_value_for`. Re-verified: `app_core` full suite 26
examples/6 failures (same 6 pre-existing Vite failures, one more passing
example than before from the new test), rubocop clean, Sorbet error count
unchanged (22) with zero errors in either changed file.
