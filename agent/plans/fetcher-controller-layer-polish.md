---
status: implemented
app: fetcher
goal: Polish app_fetcher's controller layer with per-namespace BaseControllers, centrally rescued unsupported-param errors, and serializers for InventoryValues and ItemPrices#dynamics response shaping
created: 2026-10-19
---

# Development Plan

## Applicable Styleguides

- **`agent/styleguides/fetcher/internal-api-controllers.md`** —
  constrains the new `Api::V1::BaseController`, where auth/rescue
  behavior lives, and the raise-in-action / rescue-in-base-controller
  shape for `Api::V1::UnsupportedParamError`.
- **`agent/styleguides/fetcher/public-api-controllers.md`** —
  constrains the `Api::Public::BaseController` rename and inheritance,
  and confirms Public period/range errors keep using
  `Api::Public::UnsupportedParamError`.
- **`agent/styleguides/fetcher/admin-api-controllers.md`** — constrains
  the `Api::Admin::BaseController` rename/inheritance and its retained
  auth, `rescue_from` pair, and `pagination_meta`.
- **`agent/styleguides/fetcher/list-query-objects.md`** — constrains both
  new serializers: pure response shaping, zero I/O, already-resolved
  inputs, `<Concern>Serializer`/`<Resource><Action>Serializer` naming,
  and unit specs with in-memory/unsaved data.
- **`agent/styleguides/fetcher/services.md`** — confirms why
  `ItemPricesController#dynamics`' remaining logic is *not* extracted
  into a service (single-Scenario use; services are reserved for logic
  shared across Scenarios).
- **`agent/styleguides/rails-layering.md`** — thin-controller invariant.
- **`agent/styleguides/ruby-sorbet.md`** — `# typed: strict`, explicit
  sigs, and DSL-RBI regeneration for the new/changed controllers and
  serializers.
- **`agent/styleguides/rspec-conventions.md`** — request specs for
  controller contracts, unit specs for serializers, and the
  serializer-spec rule against `create`/DB access.
- **`agent/styleguides/fix_me.md`** — checked; none of the files this
  plan touches are currently listed as known deviations.

## Goal

Refine `app_fetcher`'s controller layer without changing any HTTP
contract:

1. Give each API namespace (`Api::V1`, `Api::Public`, `Api::Admin`) a
   dedicated `BaseController` that inherits the common, behaviorless
   `ApplicationController`, instead of overloading the common
   `ApplicationController` or naming namespace bases
   `ApplicationController`.
2. Stop rendering unsupported-period errors inline in actions. Raise a
   namespace-local `Api::V1::UnsupportedParamError` and let the V1 base
   controller turn it into the same `:bad_request` response.
3. Move `InventoryValuesController`'s `payload`/`current_json`/
   `point_json` response shaping into one serializer.
4. Move `ItemPricesController#dynamics`'s price-list shaping into a
   serializer, leaving cache reads, warmup enqueueing, and the
   `pending_count` DB query in the controller.

## Expected Behavior

Every endpoint keeps its current externally observable behavior.

### Base controllers and auth

- `ApplicationController < ActionController::API` remains the common
  app-wide base class, but contains no namespace-specific
  authentication or rescue behavior.
- Each namespace gets its own base class, inheriting
  `::ApplicationController`:
  - `Api::V1::BaseController` — player bridge-token auth
    (`current_steam_id`), `rescue_from StandardError`, and
    `rescue_from Api::V1::UnsupportedParamError`.
  - `Api::Public::BaseController` — no auth, `rescue_from
    StandardError`, and `rescue_from Api::Public::UnsupportedParamError`
    (unchanged behavior, renamed class).
  - `Api::Admin::BaseController` — admin bridge-token auth
    (`current_admin_id`), `rescue_from StandardError`,
    `rescue_from ActiveRecord::RecordNotFound`, and the
    `pagination_meta` helper (unchanged behavior, renamed class).
- Every namespace controller inherits its namespace's `BaseController`.
- Missing/invalid/expired tokens keep returning `:unauthorized` with the
  same messages; every existing 404/400/429/500 shape is unchanged.
- `rescue_from StandardError` stays declared before any more specific
  handler in each base controller (Rails resolves the most recently
  declared matching handler first).

### Unsupported period

- `GET /api/v1/inventory_values?period=3weeks` still returns
  `:bad_request` with `{ "message": "Unsupported period: 3weeks" }`.
- `GET /api/v1/item_prices/:market_hash_name/history?period=3weeks`
  still returns the same shape.
- `period=24h` on `inventory_values` still returns
  `{ "message": "Unsupported period: 24h" }`.
- The action raises `Api::V1::UnsupportedParamError` instead of calling
  `render` itself; the base controller renders the response.
- Public namespace period/range errors continue to use
  `Api::Public::UnsupportedParamError`; no public behavior changes.

### Inventory values payload

`GET /api/v1/inventory_values` returns exactly the same JSON keys and
values:

```json
{
  "current": {
    "total_value_cents": 1500,
    "items_count": 1,
    "pricable_items_count": 1,
    "priced_items_count": 1,
    "complete": true,
    "oldest_price_at": "..."
  },
  "history": [
    {
      "at": "...",
      "total_value_cents": 1000,
      "complete": true,
      "priced_items_count": 1,
      "pricable_items_count": 1
    }
  ],
  "change": {
    "cents": 500,
    "percent": 50.0,
    "basis_at": "...",
    "partial": false,
    "available": true
  }
}
```

`current` remains `null` when no `UserInventory` exists; history remains
`[]`; `oldest_price_at` remains an ISO8601 string or `null`.

### Item prices dynamics payload

`GET /api/v1/item_prices/dynamics` returns exactly the same JSON:

```json
{
  "prices": {
    "AK-47 | Redline (Field-Tested)": {
      "current_price_cents": 15050,
      "change_24h_cents": 520,
      "change_24h_percent": 3.58,
      "price_updated_at": "..."
    }
  },
  "pending_count": 0
}
```

- Items with `current_price_cents == nil` are still omitted from
  `prices`.
- `change_24h_percent` still rounds to two decimals and returns `0.0`
  when the base is zero.
- `pending_count` is still computed from `Item.awaiting_price` against
  the owned names (a DB query, not derived from `ItemPriceCache`).
- Warmup enqueueing is unchanged: same cap (20), same dedup key/TTL, same
  eligible items.

## Scope

### In Scope

- Rename `Api::Public::ApplicationController` to
  `Api::Public::BaseController`.
- Rename `Api::Admin::ApplicationController` to
  `Api::Admin::BaseController`.
- Add `Api::V1::BaseController`, moving V1 auth and the
  `StandardError` catch-all out of the common `ApplicationController`.
- Update every namespace controller's superclass.
- Add `Api::V1::UnsupportedParamError` and use it in
  `InventoryValuesController#index` and `ItemPricesController#history`.
- Add `InventoryValuationSerializer` and
  `ItemPriceDynamicsSerializer`, with unit specs.
- Update Sorbet DSL RBIs for the renamed/new controllers.
- Update living styleguides/ADRs that name the renamed classes.

### Out of Scope

- Changing routes, request/response JSON contracts, status codes, or
  error message wording.
- Changing `Api::Public::UnsupportedParamError` or any public query
  object.
- Extracting a shared `Api::BaseController` across all three namespaces.
  This was already considered when `Api::Admin` introduced the third
  namespace and deliberately declined in
  `agent/adr/fetcher/public-api-namespace.md`: the three namespaces'
  filters differ (none/player-token/admin-token), so only the
  `rescue_from`/handler bodies would be shared. Three
  namespace-`BaseController`s inheriting the common empty
  `ApplicationController` are the agreed middle ground.
- Extracting `ItemPricesController#dynamics` into a service or a new
  query object. It is a single-Scenario action; only its pure response
  shaping moves.
- Rewriting historical plan files that mention the old class names.
- Changing `app_core` consumers or frontend code.

## Implementation Approach

### Inheritance shape

```text
ApplicationController < ActionController::API   (common; no auth/rescue)
├── Api::V1::BaseController
│     before_action :authenticate_bridge_token!
│     rescue_from StandardError
│     rescue_from Api::V1::UnsupportedParamError
├── Api::Public::BaseController
│     rescue_from StandardError
│     rescue_from Api::Public::UnsupportedParamError
└── Api::Admin::BaseController
      before_action :authenticate_admin_bridge_token!
      rescue_from StandardError
      rescue_from ActiveRecord::RecordNotFound
```

All three namespace bases use the explicit top-level constant
`::ApplicationController` to avoid any future same-named-namespace
shadowing.

The common `ApplicationController` becomes a minimal:
`class ApplicationController < ActionController::API; end` (plus its
strict sigil). `require "jwt"` moves to `Api::V1::BaseController` (Admin
already has it).

### Error flow

```text
Api::V1::InventoryValuesController#index
    period = PricePeriod.resolve(...)
    raise Api::V1::UnsupportedParamError, "Unsupported period: #{params[:period]}" unless period
        ↓
Api::V1::BaseController
    rescue_from Api::V1::UnsupportedParamError, with: :render_unsupported_param_error
        ↓
render json: { message: exception.message }, status: :bad_request
```

The action no longer decides how an unsupported period is rendered. The
same class is used by `ItemPricesController#history`, so both endpoints
share one error-producing convention.

### Serializer boundaries

- `InventoryValuationSerializer.call(page)` takes
  `InventoryValuation::Page` (already produced by
  `InventoryValuation.page`) and returns the response hash. It owns
  `current`/`history`/`change` shaping and ISO8601 conversion. It performs
  no DB/cache reads.
- `ItemPriceDynamicsSerializer.call(priced_items, pending_count)` takes
  the `T::Hash[String, Item]` already returned by
  `ItemPriceCache.fetch_for(names)` and the already-computed pending
  count, and returns `{ prices: ..., pending_count: ... }`. It owns the
  per-item omission/change/percent/timestamp shaping only. Cache reads,
  warmup enqueue, and the `Item.awaiting_price` count remain in the
  controller.

This keeps the controller's existing collaborator set intact while
removing the response-building loops from both actions.

## Files To Modify

- **`app_fetcher/app/controllers/application_controller.rb`**
  - Remove `require "jwt"`, `before_action
    :authenticate_bridge_token!`, `current_steam_id`,
    `authenticate_bridge_token!`, and `render_internal_server_error`.
  - Leave the common `ApplicationController < ActionController::API` as
    the shared, behaviorless ancestor.
  - Reason: V1-specific auth/rescue must not leak into Public/Admin now
    that all three inherit this class.

- **`app_fetcher/app/controllers/api/v1/inventories_controller.rb`**
  - Change superclass from `ApplicationController` to `BaseController`.
  - Reason: V1 controllers use the V1 base explicitly.

- **`app_fetcher/app/controllers/api/v1/inventory_values_controller.rb`**
  - Change superclass to `BaseController`.
  - Replace the inline `render json: { message: "Unsupported period..." }`
    branch with `raise Api::V1::UnsupportedParamError, ... unless period`.
  - Remove the private `payload`, `current_json`, and `point_json`
    methods; render `InventoryValuationSerializer.call(page)`.
  - Keep `seed_if_empty` unchanged.
  - Reason: central error handling + response shaping in one serializer.

- **`app_fetcher/app/controllers/api/v1/item_prices_controller.rb`**
  - Change superclass to `BaseController`.
  - Replace the inline period `render` branch in `history` with
    `raise Api::V1::UnsupportedParamError, ... unless period`.
  - Replace the `each_with_object` price-hash construction in `dynamics`
    with a call to `ItemPriceDynamicsSerializer.call(priced_items,
    pending_count)`.
  - Keep `owned_market_hash_names`, `enqueue_price_warmup`, the
    `ItemPriceCache` call, and the `pending_count` query where they are.
  - Reason: remove response shaping and duplicated error rendering from
    the action without changing behavior.

- **`app_fetcher/app/controllers/api/admin/items_controller.rb`**,
  **`inventory_value_logs_controller.rb`**,
  **`price_logs_controller.rb`**, **`user_inventories_controller.rb`**
  - Change superclass from `ApplicationController` to `BaseController`.

- **`app_fetcher/app/controllers/api/public/inventories_controller.rb`**,
  **`items_controller.rb`**
  - Change superclass from `ApplicationController` to `BaseController`.

- **`app_fetcher/sorbet/rbi/dsl/api/admin/application_controller.rbi`**,
  **`app_fetcher/sorbet/rbi/dsl/api/public/application_controller.rbi`**
  - Regenerate as `base_controller.rbi` with the new class names.
  - Reason: Tapioca DSL stubs must mirror the controller tree.

- **`app_fetcher/sorbet/rbi/dsl/api/v1/base_controller.rbi`**
  - Add the generated DSL stub for the new V1 base controller.

- **`agent/styleguides/fetcher/internal-api-controllers.md`**
  - Replace `ApplicationController`/`Api::V1::ApplicationController`
    references with `Api::V1::BaseController`; update the error-handling
    section to describe the V1 `UnsupportedParamError` route as well as
    the existing `StandardError` catch-all.
  - Reason: the styleguide is the living contract for this layer.

- **`agent/styleguides/fetcher/public-api-controllers.md`**
  - Rename `Api::Public::ApplicationController` references to
    `Api::Public::BaseController`, including the "never inherit from
    Api::V1" rule.
  - Reason: class rename.

- **`agent/styleguides/fetcher/admin-api-controllers.md`**
  - Rename `Api::Admin::ApplicationController` references to
    `Api::Admin::BaseController`, including canonical
    implementations/interaction diagrams.
  - Reason: class rename.

- **`agent/adr/fetcher/public-api-namespace.md`**
  - Update the current-state implementation constraints and related
    cross-references to the new base-controller names. Preserve the ADR's
    historical decision record.
  - Reason: ADR is a living architecture reference; stale class names
    would misdirect future work.

- **`agent/adr/fetcher/list-query-objects-layer.md`**,
  **`agent/adr/core/separate-admin-authentication.md`**,
  **`agent/styleguides/core/architecture-layers.md`**
  - Update current-state references to the renamed namespace base
    controllers.
  - Reason: cross-app docs that name these classes.

## Files To Create

- **`app_fetcher/app/controllers/api/v1/base_controller.rb`**
  - `Api::V1::BaseController < ::ApplicationController`.
  - Owns `before_action :authenticate_bridge_token!`,
    `current_steam_id`, `rescue_from StandardError`, and
    `rescue_from Api::V1::UnsupportedParamError` (declared after the
    catch-all).
  - Reason: V1 needs its own base with player auth + V1-specific error
    handling.

- **`app_fetcher/lib/api/v1/unsupported_param_error.rb`**
  - `Api::V1::UnsupportedParamError < StandardError`.
  - Mirrors the existing Public error class without coupling V1 to the
    Public namespace.
  - Reason: raise unsupported-param errors from V1 actions and rescue
    them once in `Api::V1::BaseController`.

- **`app_fetcher/app/serializers/inventory_valuation_serializer.rb`**
  - `InventoryValuationSerializer.call(page)` with private
    `current_json`/`point_json` helpers (and the `change` hash inline or
    in a private helper).
  - Reason: move all InventoryValues response shaping out of the
    controller while keeping one serializer, not three.

- **`app_fetcher/app/serializers/item_price_dynamics_serializer.rb`**
  - `ItemPriceDynamicsSerializer.call(priced_items, pending_count)`.
  - Reason: extract the price-list loop and percentage math from
    `ItemPricesController#dynamics`.

- **`app_fetcher/spec/serializers/inventory_valuation_serializer_spec.rb`**
  - Unit spec with in-memory `InventoryValuation` structs; no DB.
  - Covers: nil `current`, populated current/history/change, ISO8601
    `oldest_price_at`, empty history.

- **`app_fetcher/spec/serializers/item_price_dynamics_serializer_spec.rb`**
  - Unit spec with unsaved `Item` instances; no DB.
  - Covers: priced items included with rounded percent, unpriced items
    omitted, zero-denominator percent `0.0`, `price_updated_at` ISO8601,
    `pending_count` passthrough, empty input.

## Test Plan

Existing request specs are the primary contract tests and must all stay
green without behavioral edits:

- `spec/requests/api/v1/inventories_spec.rb`
- `spec/requests/api/v1/inventory_values_spec.rb` — especially the
  unsupported-period (`3weeks`/`24h`) and unhandled-error contexts.
- `spec/requests/api/v1/item_prices_spec.rb` — especially dynamics
  omission/percent/pending/warmup cases and history's unsupported
  period.
- `spec/requests/api/public/inventories_spec.rb`,
  `items_spec.rb` — public class rename and error shapes.
- `spec/requests/api/admin/*.rb` — admin class rename, auth, 404,
  pagination.

New unit specs:

- `InventoryValuationSerializer` — pure shaping, no DB. Assert symbol
  keys and values to lock the JSON contract.
- `ItemPriceDynamicsSerializer` — pure shaping, no DB. Assert the same
  edge cases already covered at request level for dynamics, so future
  changes to the serializer break a focused unit spec.

Targeted additions to request specs:

- Assert the exact `"Unsupported period: 3weeks"` message for
  `item_prices#history` (currently only `be_present`), matching the
  existing exact assertion for inventory values. This proves the raised
  error's message survives the new central rescue unchanged.

No new routing specs are needed; routes are untouched.

## Implementation Steps

1. Add the two serializer unit specs with in-memory structs/items and
   confirm they fail because the serializer classes do not exist yet.
2. Implement `InventoryValuationSerializer` and
   `ItemPriceDynamicsSerializer`; keep them pure (no AR/cache calls).
3. Update `InventoryValuesController#index` to render
   `InventoryValuationSerializer.call(page)` and remove the private
   shaping helpers; update `ItemPricesController#dynamics` to call
   `ItemPriceDynamicsSerializer`.
4. Run the targeted serializer and request specs; confirm the response
   contract is unchanged.
5. Create `Api::V1::UnsupportedParamError`.
6. Create `Api::V1::BaseController`, moving `require "jwt"`,
   `authenticate_bridge_token!`, `current_steam_id`,
   `render_internal_server_error`, and the `StandardError` rescue out of
   the common `ApplicationController`; add the
   `UnsupportedParamError` rescue after it.
7. Replace the inline unsupported-period renders in
   `InventoryValuesController#index` and `ItemPricesController#history`
   with raises; switch the V1 controllers to `< BaseController`.
8. Rename the Public/Admin `ApplicationController` files/classes to
   `BaseController` (via `git mv`), update their superclass to
   `::ApplicationController`, and switch their namespace controllers to
   `< BaseController`.
9. Add the exact-message assertion for `item_prices#history`.
10. Regenerate the Tapioca DSL RBIs for the three base controllers
    (remove the two stale `application_controller.rbi` files, add
    `base_controller.rbi` files). If Tapioca cannot run, update the
    generated stubs to the same content/shape by hand and note the
    tooling limitation.
11. Update the living styleguides/ADRs listed above so no current-state
    doc still names the removed classes.
12. Run the full verification suite below.

## Verification

Commands (from the repo root, using the project's Docker setup):

- `docker compose exec app_fetcher bundle exec rspec spec/serializers/inventory_valuation_serializer_spec.rb spec/serializers/item_price_dynamics_serializer_spec.rb`
- `docker compose exec app_fetcher bundle exec rspec spec/requests/api/v1/ spec/requests/api/public/ spec/requests/api/admin/`
- `docker compose exec app_fetcher bundle exec rspec`
- `docker compose exec app_fetcher bin/rubocop app/controllers app/serializers lib/api spec/serializers spec/requests`
- `docker compose exec app_fetcher bundle exec srb tc` — compare
  against the pre-change error count; this repo already has known
  pre-existing Sorbet errors (see `agent/styleguides/fix_me.md`), so only
  new errors count as regressions.
- If Tapioca works in this environment:
  `docker compose exec app_fetcher bin/tapioca dsl "Api::V1::BaseController" "Api::Public::BaseController" "Api::Admin::BaseController"`.

Manual spot checks (optional, same payloads as before):

- `GET /api/v1/inventory_values?period=3weeks` with a valid bridge
  token → 400 + exact message.
- `GET /api/v1/item_prices/dynamics` → unchanged JSON.
- `GET /api/public/items` with no token → 200.
- `GET /api/admin/items` with a player token → 401.

## Risks

- **Constant lookup shadowing.** All three bases must use
  `::ApplicationController` explicitly; a bare `ApplicationController`
  inside `Api::Admin`/`Api::Public`/`Api::V1` could resolve to a future
  same-named namespace constant. This mirrors the existing
  `::Admin::...Serializer` rule.
- **Auth leaks into Public/Admin.** Moving V1 auth out of the common
  `ApplicationController` is required; leaving it there would
  authenticate Public/Admin unexpectedly.
- **Rescue ordering.** The specific `UnsupportedParamError` rescue must
  be declared after `rescue_from StandardError`; otherwise the catch-all
  may win and turn a 400 into a 500.
- **Payload drift.** Both serializers must preserve exact keys, nil vs.
  absent distinctions, ISO8601 formatting, omission of unpriced items,
  and the zero-denominator `0.0` behavior.
- **Behavioral side effects in dynamics.** Only the response shaping may
  move. `ItemPriceCache.fetch_for`, `enqueue_price_warmup`, and the
  `Item.awaiting_price` count must stay in the controller so cache,
  job-enqueue, and DB behavior are byte-for-byte unchanged.
- **Stale RBIs/autoloading.** Renaming controller files can leave stale
  Tapioca DSL stubs and old constants in a running dev process; restart
  the app/regenerate RBIs and verify `srb tc`.
- **Docs drift.** Several living styleguides/ADRs name the old classes;
  update them in this change rather than leaving contradictory guidance.

## Assumptions

- No external consumer references controller class names directly; only
  HTTP routes are contracted.
- The common `ApplicationController` has no behavior of its own beyond
  being the app-wide ancestor, so it can be emptied without affecting
  Rails health checks or anything else.
- Keeping `Api::Public::UnsupportedParamError` namespace-local and adding
  a sibling `Api::V1::UnsupportedParamError` is preferable to a shared
  `Api::UnsupportedParamError` for this change, matching the project's
  per-namespace base-controller convention.

## Completion Criteria

- All three namespaces have a `BaseController` inheriting
  `::ApplicationController`; all namespace controllers inherit their own
  base.
- The common `ApplicationController` no longer contains V1 auth or
  rescue behavior.
- Unsupported-period responses are produced by raising
  `Api::V1::UnsupportedParamError` and are still rendered as the exact
  existing `:bad_request` / `{ message: "Unsupported period: ..." }`
  shape.
- `InventoryValuesController` and `ItemPricesController#dynamics` no
  longer contain inline response-shaping loops/helpers covered by the new
  serializers.
- Serializer unit specs and all existing request specs pass; no new
  RuboCop or Sorbet errors.
- Living styleguides/ADRs no longer refer to the removed
  `Api::V1::ApplicationController` / `Api::Public::ApplicationController`
  / `Api::Admin::ApplicationController` names.

---

# Implementation Summary

## Implemented

- Added `Api::V1::BaseController < ::ApplicationController`, carrying the
  player bridge-token `before_action`, `current_steam_id`, the
  `StandardError` catch-all, and a new specific handler for
  `Api::V1::UnsupportedParamError`.
- Reduced the common `ApplicationController` to a namespace-neutral
  `ActionController::API` base with no auth or rescue behavior.
- Renamed `Api::Public::ApplicationController` and
  `Api::Admin::ApplicationController` to `BaseController`, changed their
  ancestry to `::ApplicationController`, and switched every namespace
  controller to its own `BaseController`.
- Added `Api::V1::UnsupportedParamError`
  (`app_fetcher/lib/api/v1/unsupported_param_error.rb`).
- Replaced the inline unsupported-period `render` branches in
  `InventoryValuesController#index` and `ItemPricesController#history`
  with raises handled by the V1 base controller.
- Added `InventoryValuationSerializer` for the inventory-values response
  and `ItemPriceDynamicsSerializer` for the dynamics price payload.
  `InventoryValuesController` no longer has `payload`/`current_json`/
  `point_json`; `ItemPricesController#dynamics` no longer builds the
  price hash inline. Cache reads, warmup enqueueing, and `pending_count`
  stay in the controller.
- Removed the now-stale `Api::Public::ApplicationController` /
  `Api::Admin::ApplicationController` controller DSL RBIs. Tapioca does
  not generate DSL RBIs for these namespace base controllers in this
  environment (confirmed by the full `tapioca dsl` run during the
  pre-commit hook, which removes them as stale); `srb tc` passes without
  them.
- Updated living styleguides/ADRs to the new names and the new
  V1 unsupported-param error shape.

## Tests

Added:

- `app_fetcher/spec/serializers/inventory_valuation_serializer_spec.rb`
  — nil current, populated current/history/change, ISO8601 timestamp,
  empty history.
- `app_fetcher/spec/serializers/item_price_dynamics_serializer_spec.rb`
  — priced/unpriced omission, rounded percent, zero denominator, nil
  change/timestamp, empty input.

Changed:

- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb` — the
  unsupported-period case now asserts the exact
  `"Unsupported period: 3weeks"` message.

Commands executed:

- `docker compose run --rm --no-deps app_fetcher bundle exec rspec spec/serializers/inventory_valuation_serializer_spec.rb spec/serializers/item_price_dynamics_serializer_spec.rb`
  — RED first (`uninitialized constant`), then GREEN (7 examples).
- `docker compose run --rm --no-deps app_fetcher bundle exec rspec spec/requests/api/v1/inventory_values_spec.rb spec/requests/api/v1/item_prices_spec.rb`
  — 36 examples, 0 failures.
- `docker compose run --rm --no-deps app_fetcher bundle exec rspec spec/requests/api spec/serializers`
  — 195 examples, 0 failures.
- `docker compose run --rm --no-deps app_fetcher bundle exec rspec`
  — 476 examples, 0 failures.
- `docker compose run --rm --no-deps app_fetcher bin/rubocop app/controllers app/serializers lib/api spec/serializers spec/requests/api/v1/item_prices_spec.rb`
  — 30 files, no offenses.
- `docker compose run --rm --no-deps app_fetcher bundle exec srb tc`
  — no errors.
- `docker compose run --rm --no-deps app_fetcher bin/tapioca dsl "Api::V1::BaseController" "Api::Public::BaseController" "Api::Admin::BaseController"`
  — Tapioca reports "No classes/modules can be matched for RBI
  generation" for controllers in this environment (also for an existing
  controller). The full `tapioca dsl` run (via the pre-commit hook)
  removed the stale namespace base-controller DSL RBIs, and `srb tc`
  passes without them.

## Verification

- Full `app_fetcher` RSpec suite: **476 examples, 0 failures**.
- RuboCop on all touched controller/serializer/lib/spec paths: **no
  offenses**.
- `srb tc`: **No errors**.
- `git diff --check`: clean.
- No remaining references to
  `Api::V1|Public|Admin::ApplicationController` in `app_fetcher`.

## Deviations

- **Tapioca DSL regeneration unavailable for controllers**: the command
  exits with "No classes/modules can be matched" even for pre-existing
  controllers. The full `tapioca dsl` run removes the old namespace
  application-controller DSL RBIs as stale and generates no replacements;
  `srb tc` passes without them, so no controller DSL RBI files are kept.
- **Pre-existing working-tree edits**: `api/public/inventories_controller.rb`
  and `api/public/items_controller.rb` already had unrelated whitespace
  edits in the working tree before this change. Only their superclass
  lines were changed here; those whitespace edits were left untouched.

## Remaining Issues

None. The V1 `UnsupportedParamError`, base-controller split, and both
serializer extractions are implemented and verified.
