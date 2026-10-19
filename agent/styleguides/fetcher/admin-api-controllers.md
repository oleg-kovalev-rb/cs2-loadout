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
`InventoryValueLog`) for administrative management: create/read/destroy on
`Item`, read/delete on the others, plus a handful of operator-triggered
actions (`refresh_price`, `sync`, `warm_cache`). What belongs here:
anything gated by "is this an authorized administrator," with no
per-player scoping. What does not: anything scoped to a specific Steam
player (that's `Api::V1::`'s job) or anything with no caller identity at
all (that's `Api::Public::`'s job).

## When to Use

Use this namespace for any endpoint an admin-facing client (`app_core`'s
admin panel, `app/frontend/admin-panel/` — see
`agent/plans/admin-panel-frontend.md`) needs to manage
`app_fetcher`-owned records directly, independent of any specific player.
Not for anything that should be scoped by `current_steam_id` — that stays
under `Api::V1::`.

## Structure

- `app/controllers/api/admin/<resource>_controller.rb`, nested
  `Api::Admin::<X>Controller`, mirroring `namespace :api do; namespace
  :admin do; ...; end; end` in `config/routes.rb`.
- Unlike `Api::V1::`/`Api::Public::`, genuine CRUD resources use standard
  `resources`, not explicit named routes (see
  `admin-api-crud-routing.md`):
  - `resources :items, only: %i[index show create destroy]` — Item's
    create/read/destroy lifecycle, with no `update` action — plus member
    routes `post :refresh_price` and `post :warm_cache`, collection routes
    `post :bulk_warm_cache` and `post :warm_catalog_cache`, and a nested
    `resources :price_logs, only: %i[destroy]`. Removing a lifecycle
    action narrows the `only:` list; it does not replace `resources` with
    explicit named routes.
  - `resources :user_inventories, only: %i[index show destroy], param:
    :steam_id` with member routes `post :sync` and `post :warm_cache`,
    plus a collection route `post :bulk_warm_cache`, plus a nested
    `resources :inventory_value_logs, only: %i[destroy]`.
  - A **top-level explicit route**, `get "price_logs", to:
    "price_logs#index"` (and the same shape for `inventory_value_logs`)
    — not nested under anything, and not declared via `resources` (unlike
    the genuine-CRUD resources above): a cross-parent listing has no
    single addressable record of its own, the same reason
    `admin-api-crud-routing.md` reserves `resources` for an actual
    create/read/update/destroy lifecycle; this is one read action, the
    same shape `Api::Public::ItemsController#index`'s own `get "items",
    to: "items#index"` already uses. `price_logs`/`inventory_value_logs`
    each only ever have **this one** `index` — the nested
    `resources :price_logs`/`resources :inventory_value_logs` above is
    `only: %i[destroy]`, not `%i[index destroy]`. (Two earlier versions
    of this file described, in turn, a separate nested `#index` action,
    then a single `#index` branching on whether a nested parent param was
    present — both removed once it turned out nothing actually called
    the nested shape: the admin UI's `PriceLog`/`InventoryValueLog` pages
    only ever read the flat list and only ever write through the nested
    `destroy`. Don't resurrect a nested `index` for these two resources
    without a real caller driving it — see Rules' MUST NOT.)
- A non-CRUD action with no single natural `:id` to key off — it takes a
  client-supplied list (`bulk_warm_cache`'s `item_ids`/`steam_ids`) or no
  identifying param at all (`warm_catalog_cache`) — is a `collection`
  route, never a `member` route. Member routes stay reserved for actions
  keyed by exactly one `:id`/`:steam_id` (`refresh_price`, `warm_cache`,
  `sync`).
- Every `index` action paginates via `Appliers::Pagination`
  (`app_fetcher/app/queries/appliers/pagination.rb`) called directly,
  **not** the full `list-query-objects.md` stack
  (`<Resource>CatalogQuery`/`<Resource>CatalogSerializer`/`Options::*`
  sort-filter enums) — that layer is for endpoints that also need shared
  sort/filter/response-cache mechanics (see its own "When to Use"), none
  of which any `Api::Admin::` index needs today. Pair it with an explicit
  default `order` on the scope (pagination over an unordered scope isn't
  stable across pages): `Item.order(id: :asc)`,
  `PriceLog.includes(:item).order(created_at: :desc)`,
  `UserInventory.order(updated_at: :desc)`,
  `InventoryValueLog.order(log_date: :desc)`. Apply the computed
  `page`/`per_page` with `pagination.apply(scope)`
  (`Appliers::Pagination#apply`), not a manual
  `.limit(pagination.per_page).offset(pagination.offset)` chain — every
  admin index does the same two-step (compute pagination, then apply it
  to a scope), so the application itself is shared too, not just the
  computation. The one documented exception:
  `InventoryCatalogQuery` (`app/queries/inventory_catalog_query.rb`)
  keeps the manual chain because Sorbet's `pluck` signature checks a
  splat's size statically, and routing through `apply`'s precisely
  `ActiveRecord::Relation`-typed return makes that check apply to its
  `pluck(*AGGREGATE_COLUMNS.map { ... })` call in a way it didn't against
  the untyped chain it replaced — a real, narrow type-checking
  interaction, not a reason to avoid `apply` generally.
- `Api::Admin::BaseController < ::ApplicationController` — its own
  file, its own `before_action :authenticate_admin_bridge_token!`, its
  own independently-declared `rescue_from StandardError, with:
  :render_internal_server_error` (duplicated from `Api::V1::`'s and
  `Api::Public::`'s, not inherited or shared — per
  `public-api-namespace.md`, not re-decided here). The common
  `ApplicationController < ActionController::API` is a namespace-neutral
  ancestor with no auth or rescue behavior of its own.

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
- A paginated `index` action's response adds a `meta` key alongside the
  resource's existing bare-array key:
  `{ meta: { total_count:, total_pages: }, <key>: [...] }`
  (`<key>` is whatever that controller already renders —
  `items`/`price_logs`/`user_inventories`/`inventory_value_logs`). `meta`
  deliberately does **not** echo `page`/`per_page` back — the caller
  already knows what it requested (it sent those exact params), so
  echoing them is a pure, pointless round-trip; only `total_count`/
  `total_pages` are genuinely server-derived (a `COUNT(*)` the caller has
  no other way to learn) and worth sending. Built via a shared private
  helper, `pagination_meta(pagination, total_count)` on
  `Api::Admin::BaseController` — every `index` action calls it
  rather than inlining the hash, so the envelope shape lives in exactly
  one place.
- `bulk_warm_cache` (Items) accepts `{ item_ids: T::Array[Integer] }` and
  always warms all three of `Item`'s sibling caches
  (`ItemPriceCache`/`PriceHistoryCache`/`ItemTrendCache`) for every
  requested id — there is no per-cache selector. An earlier version of
  this action took a `cache_target` selector (a closed `T::Enum`,
  `Options::CacheTarget`) letting the caller warm just one of the three;
  removed as unneeded indirection once it became clear every real caller
  always wants all three warmed together anyway (the same "one logical
  collaborator" grouping `warm_cache`'s own single-item version already
  uses — see Responsibilities). Returns
  `{ warmed_item_ids: [...], message: "..." }`.
- `bulk_warm_cache` (UserInventory) accepts
  `{ steam_ids: T::Array[String] }` — `UserInventoryCache` is the only
  cache in play for this resource, so there's nothing to select between.
  Returns `{ warmed_steam_ids: [...], message: "..." }`.
- `warm_catalog_cache` (Items) accepts no body. Returns
  `{ message: "..." }`.
- `PriceLogsController#index`/`InventoryValueLogsController#index` use
  the same `meta` envelope as any other paginated index. Each row carries
  its parent's id alongside its own fields — `item_id`/`market_hash_name`
  for `PriceLog`, `steam_id` for `InventoryValueLog` — since these are
  cross-parent listings, not scoped to one parent the caller already
  knows. `item_id`/`steam_id` specifically exist so the frontend's
  row-level mutations (e.g. delete) can target the real nested `destroy`
  route; see `react-dashboard.md`'s "Mutations Against Nested Backend
  Routes".
- `show` may return a richer per-record shape than `index`'s own rows for
  the same resource — they're answering different questions ("everything
  about this one record" vs. "a page of many").
  `UserInventoriesController#show` returns an `items` array (each
  inventory's actual contents: `market_hash_name` + `added_at`) that
  `#index`'s own rows don't carry — sending every row's full item list on
  every list page would be wasteful for data the list view never
  displays; a client that needs it already has the one `steam_id` it's
  asking about. Don't treat `show`/`index` shape parity as an implicit
  rule to preserve — nothing in this namespace has required it, and nothing
  should until a concrete case argues for it.
- A field whose absence is meaningfully different from its zero value
  (`UserInventoriesController`'s `total_value_cents`: `nil` means "never
  synced, unknown," `0` means "synced, confirmed empty or worthless") is
  `nil` when absent — never defaulted to `0`, `""`, or any other sentinel
  that would read as a real value. Don't let a `|| 0`/`.presence ||`-style
  fallback quietly collapse the two cases; the frontend is expected to
  render them differently (e.g. an em dash vs. an actual `$0.00`), which
  it can only do if the API preserves the distinction.

## Responsibilities

Same shape as `internal-api-controllers.md`'s Responsibilities: an action
parses params, calls one collaborator, and renders based on that call's
result. For genuine CRUD actions, the one collaborator is the model
itself (`Item.create!`, `Item.destroy!`, or a future resource's
`update!` when it exposes that lifecycle action) — consistent with these
being real CRUD, not an action dressed as one.

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

This rule extends unchanged to the bulk/catalog actions: `bulk_warm_cache`
(Items) calling all three `fetch_for` variants for the requested batch
is still one logical collaborator (populate this batch's caches), not
three; `warm_catalog_cache` calling
`ItemCatalogQuery.call`/`ItemCatalogSerializer.call`/`ItemCatalogCache.write`
is one logical collaborator too (populate the default catalog view), the
same shape `Api::Public::ItemsController#index` already uses for the read
path.

## Dependencies

Same dependency set `Api::V1::` already has: may call models (including
scopes) directly for CRUD actions; may enqueue
`PriceUpdateWorker.perform_async` (`refresh_price`) and call
`UserInventorySyncService.call` synchronously (`sync`) — both already
established, unmodified call shapes (see the development plan; not
re-decided here); may call cache classes' `.fetch_for`/`.fetch` directly
for `warm_cache`, `bulk_warm_cache`, and `warm_catalog_cache` — all three
only ever read-through-warm (`.fetch_for`/`.fetch`/`.write`), never
`.invalidate`, so none of them introduce a new caller `caching.md`'s
"only the writer named in Dependencies calls `.invalidate`" rule would
otherwise restrict; `warm_catalog_cache` may additionally call
`ItemCatalogQuery.call`/`ItemCatalogSerializer.call` (the same read path
`Api::Public::ItemsController#index` uses on a cache miss) to produce the
payload it writes. An index action that renders a field sourced from elsewhere than the
resource's own columns always batches that lookup across the whole page
in one query, never once per row — the specific technique depends on the
shape of what's being looked up, not a single fixed pattern: a flat/
global index that renders a field from a `belongs_to` association
(`PriceLogsController#index`'s flat branch rendering each log's
`market_hash_name` via its `item`) preloads with `.includes(:item)` on
the base query; an index that renders a "latest row from another table,
per parent" field with no direct association to eager-load
(`UserInventoriesController#index` rendering each row's
`total_value_cents` from that `steam_id`'s most recent
`InventoryValueLog`) batches with a single `DISTINCT ON` query across all
the page's `steam_id`s, keyed into a hash the per-row builder then reads
from — never a `.order(...).first` called once per row in a loop, which
is the per-row-batch-lookup equivalent of the N+1 `.includes` already
guards against.

## Rules

### MUST

- Namespace under `Api::Admin::`, with routes declared per Structure
  above.
- Use `resources` (restricted via `only:` where relevant) for every
  genuine CRUD resource in this namespace; keep non-CRUD actions
  (`refresh_price`, `warm_cache`, `sync`) as member routes inside the
  relevant `resources` block — see `admin-api-crud-routing.md`.
- `before_action :authenticate_admin_bridge_token!` on
  `Api::Admin::BaseController`, requiring the `admin_id` claim
  explicitly — never accept a token merely because it decodes.
- Look up a record with a raising finder (`find`/`find_by!`) and let
  `Api::Admin::BaseController`'s `rescue_from
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
- Build response bodies with a dedicated `Admin::<Resource>Serializer`
  class in `app/serializers/admin/` (`.call_for_list`/`.call` class
  methods — matching the public-API serializers' own single `.call`
  entry point; `call_for_list` is this namespace's own addition, needed
  because a resource with both a paginated list and a single-record shape
  can't fit both under one bare `.call`),
  matching the house convention the public-API serializers already use
  (`ItemCatalogSerializer`, `InventoryCatalogSerializer`,
  `InventoryDetailSerializer`) — not private `*_json` methods inlined in
  the controller. **Always reference it fully qualified,
  `::Admin::<Resource>Serializer`** (leading `::`), never a bare
  `Admin::<Resource>Serializer` — every call site lives lexically inside
  `Api::Admin::`, and Ruby's constant lookup resolves a bare `Admin` to
  the surrounding `Api::Admin` module itself before it ever reaches the
  top-level `Admin` module these serializers live in, raising a
  `NameError` (the same class of constant-shadowing trap
  `Options::CacheTarget` hit against `ActionController::ParamsWrapper::Options`
  earlier in this namespace's history — any bare reference to a
  same-named top-level module from inside a matching nested namespace is
  this bug waiting to happen, not just this one case). The controller
  still builds the `meta` hash (via `pagination_meta`) and runs any
  batched lookups the response needs (e.g. `UserInventoriesController`'s
  `latest_value_cents_by_steam_id`) — those are DB-querying concerns, not
  shaping concerns — then hands the already-fetched records (plus `meta`
  and any per-row side-data) to the serializer, which owns only "how do I
  turn these records into the response hash."
- Paginate every `index` action with `Appliers::Pagination`, applied via
  `pagination.apply(scope)` (see Structure's note on the one exception),
  with an explicit default `order` (see Structure); include the `meta`
  envelope described in Interface.
- Declare a non-CRUD action with no single natural `:id` (a
  client-supplied list, or none at all) as a `collection` route, never a
  `member` route (see Structure).
- Treat a bulk action's id-list param resolving to zero existing records
  as a success (`200`, `warmed_<x>_ids: []`) — silently warming nothing —
  not a validation failure.
- Preload (`.includes`) any association a cross-parent index renders a
  field from, to avoid N+1 across its (potentially large) result set —
  `PriceLogsController#index`'s `.includes(:item)` for `market_hash_name`
  is the concrete example.
- Only expose the actions a resource's nested route actually needs —
  don't add a nested `index` "for completeness" alongside a nested
  `destroy` without a real caller for it. `price_logs`/
  `inventory_value_logs` both had a nested `index` until it became clear
  nothing ever called it (the admin UI only ever reads the top-level flat
  index and writes through the nested `destroy`) — removed, leaving
  `only: %i[destroy]` nested under each parent. If a genuine need for
  "list just this parent's rows" shows up later, add the nested `index`
  back then, driven by that real caller — not speculatively ahead of one.

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
- Don't adopt the full `list-query-objects.md` stack for an `index`
  action that only needs pagination — that layer's own "When to Use"
  reserves it for endpoints that also need shared sort/filter/response-
  cache mechanics (see Structure).
- Don't fold a bulk/catalog action's cache calls into
  `.invalidate` — they read-through-warm only (see Dependencies); adding
  invalidation here would introduce a new caller `caching.md`'s
  writer-ownership rule doesn't authorize.
- Don't add a flat/global index for a nested resource "for consistency"
  absent an actual cross-parent listing need — see Structure's
  `price_logs` example; this is decided per-resource, not applied
  reflexively to every nested resource in this namespace.

## Error Handling

Same three-shape taxonomy as `internal-api-controllers.md`, with
`admin_id` substituted for `steam_id` in the auth-failure shape:

1. **Auth failures** — `:unauthorized` with `{ message: "..." }`: missing
   token, invalid/expired token, or a token that decodes but lacks the
   `admin_id` claim (e.g. a per-player bridge token).
2. **Explicit per-action failure branch** — validation failures on
   `create` (blank/duplicate `market_hash_name`):
   `:unprocessable_content` with `{ message: "..." }`. Item exposes no
   `update`, so there is no update-validation branch; a future resource
   that adds one follows the same shape. An id-list param
   (`item_ids`/`steam_ids`) resolving to zero existing records is *not*
   this case — see Rules.
3. **Missing record** — `show`/`destroy`/`refresh_price`/
   `warm_cache`/the nested `price_logs`/`inventory_value_logs` actions
   look up their record with a raising finder (`Item.find(params[:id])`,
   `UserInventory.find_by!(steam_id: params[:steam_id])`,
   `PriceLog.find_by!(id:, item_id:)`, etc.), never a manual `find_by` +
   `unless record; render :not_found; end` guard.
   `Api::Admin::BaseController` declares `rescue_from
   ActiveRecord::RecordNotFound, with: :render_not_found` (`{ message:
   "Not found" }` / `:not_found`), centralizing the 404 shape instead of
   repeating it per action. This is a deliberate divergence from
   `internal-api-controllers.md`'s MUST NOT against a speculative
   `rescue_from` for "a specific exception class that has no live
   trigger" — that rule's own stated reason doesn't apply here, since
   every admin action genuinely operates on a client-supplied id that may
   not exist, unlike `Api::V1::`'s `current_steam_id`-scoped actions.
4. **Unhandled/infra-level failures** — `Api::Admin::BaseController`'s
   own `rescue_from StandardError`, logged via
   `Rails.logger.error`, rendering `{ message: "Internal error" }` /
   `:internal_server_error` — same behavior as the other two namespaces',
   declared independently here per `public-api-namespace.md`.

## Interaction With Other Layers

```text
Request (Authorization: Bearer <admin bridge token>)
    ↓
Api::Admin::BaseController#authenticate_admin_bridge_token!
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
- For a resource with no `create`/`update` (`PriceLog`,
  `InventoryValueLog`), assert the absence of those routes at the routing
  level (e.g. `expect { post ... }.to raise_error(...)` or an equivalent
  routing assertion) — not just that the controller has no corresponding
  action. Since each is nested `only: %i[destroy]`, also assert the
  nested path has no `index` (`GET .../price_logs`, nested under an
  `item_id`, should 404-route the same way `POST` does) — this is the
  concrete proof that the earlier nested `index` was actually removed,
  not just unreferenced.
- `warm_cache`/`bulk_warm_cache`/`warm_catalog_cache` specs assert real
  `Rails.cache` state after the call (per `caching.md`'s existing testing
  rule) — don't mock `Rails.cache` or the cache classes.
- The per-player-bridge-token-rejected proof case (see Rules) applies to
  `collection` routes exactly the same as `member`/CRUD routes — a bulk/
  catalog action spec includes it too, not just the resource's `index`.
- Pagination specs assert `meta.total_count`/`total_pages` correctness
  and that paging through a seeded set with a known default `order`
  yields no duplicate/skipped rows.
- `bulk_warm_cache` (Items) specs cover: every one of the three sibling
  caches actually warmed, and an id in the list that doesn't resolve to a
  record being silently skipped (not a failure).
- A cross-parent index spec asserts the result actually spans multiple
  parents (e.g. multiple items' `PriceLog` rows in one page) and that the
  preloaded association field renders correctly — and separately asserts
  no N+1 (a `sql.active_record` subscriber count, or equivalent, not a
  guess from reading the code), per `caching.md`'s existing precedent for
  "assert the real thing, don't mock what's under test" applied here to
  query count instead of cache state.
- Any index rendering a batched "latest row from another table" field
  (the `DISTINCT ON` shape) asserts no N+1 the same way, across multiple
  parents in one page — plus a case for a parent with no matching row at
  all, asserting that field renders `nil` in the response (not absent
  from the JSON, not `0`), proving the nil-vs-zero distinction actually
  holds through the full request, not just in the builder method in
  isolation.

## Canonical Implementations

- `app_fetcher/app/controllers/api/admin/base_controller.rb` —
  auth, the `rescue_from StandardError`/`rescue_from
  ActiveRecord::RecordNotFound` pair, `pagination_meta` (the shared
  envelope-building helper every `index` action calls).
- `app_fetcher/app/controllers/api/admin/items_controller.rb` —
  `index`/`show`/`create`/`destroy` (no `update`),
  `refresh_price`/`warm_cache`/`bulk_warm_cache`, the
  raising-finder-per-action shape; `app_fetcher/app/serializers/admin/item_serializer.rb`
  (`::Admin::ItemSerializer`) for its response shapes.
- `app_fetcher/app/controllers/api/admin/price_logs_controller.rb#index` —
  the cross-parent flat index (`.includes(:item)` preload for
  `market_hash_name`); `#destroy` nested under `item_id`, `find_by!` on a
  compound (non-primary-key) condition;
  `app_fetcher/app/serializers/admin/price_log_serializer.rb`
  (`::Admin::PriceLogSerializer`) for the row shape (`item_id`/
  `market_hash_name` alongside the log's own fields).
- `app_fetcher/app/controllers/api/admin/inventory_value_logs_controller.rb#index` —
  the same cross-parent flat index shape;
  `app_fetcher/app/serializers/admin/inventory_value_log_serializer.rb`
  (`::Admin::InventoryValueLogSerializer`) for the row shape (`steam_id`
  alongside the log's own fields). (An earlier version of this action
  also computed a per-row trend via a shared `Appliers::WindowedDownsample`
  helper, and both this resource and `PriceLog` also had a nested
  `index` branch — both removed; see the development plan's "Post-review
  refactor" rounds 3 and 5 for why. `ItemTrendCache#downsample` is
  unaffected by the trend removal — it was always its own, independent,
  self-contained implementation, only ever used as a reference when this
  action's trend was first built.)
- `app_fetcher/app/controllers/api/admin/user_inventories_controller.rb`
  — `find_by!` keyed by `steam_id`, the synchronous `sync` action,
  `total_value_cents` (`DISTINCT ON` batch for `index`, single lookup for
  `show`); `app_fetcher/app/serializers/admin/user_inventory_serializer.rb`
  (`::Admin::UserInventorySerializer`) for its response shapes, including
  `show`-only `items`.
- `app_fetcher/app/queries/appliers/pagination.rb`'s `#apply` — every
  admin `index` action's `scope.limit(...).offset(...)` collapsed to
  `pagination.apply(scope)`; also used by the public `*CatalogQuery`/
  `InventoryDetailQuery` classes (`list-query-objects.md`'s own layer),
  since it's the same `Appliers::Pagination` instance either way.

## Related ADR

- `agent/adr/fetcher/public-api-namespace.md`
- `agent/adr/fetcher/admin-api-crud-routing.md`
