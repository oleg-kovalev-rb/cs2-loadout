---
description: Api::V1:: controller conventions in app_fetcher — routing, bridge-token auth, JSON response/error shape, single-collaborator actions.
---

# Internal API Controllers (`Api::V1::`)

## Purpose

Expose `app_fetcher`'s ingested Steam data (inventory, price history) to
`app_core` over a small internal JSON API, authenticated by a
short-lived bridge token. This is not a public API — it has exactly one
consumer, `app_core`.

## When to Use

Use this pattern when `app_core` needs to read Steam-derived data that
lives in `app_fetcher`. Not for anything a public/external client would
call directly, and not for an endpoint that doesn't need bridge-token
auth — see MUST NOT below. A genuinely public, unauthenticated endpoint
now lives in a sibling namespace instead: see
`agent/styleguides/fetcher/public-api-controllers.md` and
`agent/adr/fetcher/public-api-namespace.md` for that namespace's own
conventions and why it's separate rather than an opt-out here.

## Structure

- `app/controllers/api/v1/<resource>_controller.rb`, nested
  `Api::V1::<X>Controller`, mirroring the `namespace :api do; namespace
  :v1 do; ...; end; end` block in `config/routes.rb`.
- Routes are declared explicitly (`get "inventories/me", to:
  "inventories#show"`, `get "item_prices/dynamics", to:
  "item_prices#dynamics"`) — never a bare `resources :x`, since these
  aren't CRUD resources.
- `ApplicationController < ActionController::API` is the app-wide,
  namespace-neutral base class (no views, sessions, cookies, auth, or
  namespace-specific error handling). Every namespace base controller
  inherits it.
- `Api::V1::BaseController < ::ApplicationController` (no views,
  sessions, or cookies — a pure JSON API base) applies `before_action
  :authenticate_bridge_token!` globally, not opt-in per controller. The
  explicit `::ApplicationController` keeps the lookup pinned to the
  top-level class rather than a future same-named V1 constant.

## Interface

- Every action's `sig` is `{ void }` — actions communicate only through
  `render`, never a Ruby return value.
- Every response is `render json: { ... }, status: :some_symbol` — never
  `render json: some_object` directly; always an explicit hash and an
  explicit status symbol, even for a single error message.
- Error bodies are always shaped `{ message: "..." }` (see
  `authenticate_bridge_token!`'s "Missing/Invalid bridge token",
  `InventoriesController#show`'s `{ message: response.error }`).
- `current_steam_id` (from `Api::V1::BaseController`) is the only source
  of the caller's identity — never read a `steam_id`/user identifier out
  of `params`.

## Responsibilities

A controller action parses params, calls exactly one collaborator (a
`Steam::Client` call, a plain ActiveRecord query, or — per the narrow
exception in `agent/adr/fetcher/cross-scenario-service-layer.md` — a
cross-Scenario service), and renders JSON based on that single call's
result. It does not parse Steam's raw response itself (that's
`Steam::Client`/its DTOs' job) and carries no business logic beyond a
conditional render or raising a namespace-local error for the base
controller to render — heavier lifting (Steam calls, item resolution,
backfill, persistence) is delegated entirely to the one collaborator.

## Dependencies

May call `Steam::Client` directly (a fresh `Steam::Client.new` per
request — no injection) and enqueue Sidekiq workers directly
(`PriceUpdateWorker.perform_async`). Relies on `Api::V1::BaseController`
for auth; never re-implements token verification in a specific
controller. See `agent/adr/fetcher/cross-scenario-service-layer.md`
for the one remaining named exception:
`InventoriesController#show`'s cold-start branch calls
`UserInventorySyncService` synchronously instead of enqueuing.
`InventoryValuesController#index` is a pure read — it calls the
`InventoryValueHistoryQuery`; writing the day's log is the nightly
`InventoryValueUpdateWorker`'s job.

## Rules

### MUST

- Namespace under `Api::V1::`, with an explicit route in
  `config/routes.rb` (see Structure).
- `render json: { ... }, status: :ok` on the success path — always an
  explicit status symbol, always a hash.
- If the action calls something that can fail externally (today, only
  `Steam::Client`), branch on `response.success?`: render the data with
  `:ok` on success, `{ message: response.error }` with `:bad_request` on
  failure (see `InventoriesController#show`). If the action only reads
  local data via ActiveRecord, a plain `:ok` render with no failure
  branch is correct (see `InventoryValuesController#index`,
  `ItemPricesController#dynamics`/`#trend`) — don't add a defensive
  rescue/branch, in a specific action, for a specific exception class
  that has no live trigger in today's call sites.
- Look up a path-segment resource with a bang finder
  (`Model.find_by!(...)`) and let the miss raise
  `ActiveRecord::RecordNotFound`; `Api::V1::BaseController` renders it
  as the standard not-found response (see Error Handling). Never check
  for `nil` and render `:not_found` (or an empty success body) inline.
  `ItemPricesController#history` is the canonical case: it resolves the
  `Item` by `market_hash_name` before branching between the 30-day
  cache (explicit `period=30d` or the absent-period default) and the
  history query, so every period has the same 404 contract.
- Validate a closed-enum query param by raising
  `Api::V1::UnsupportedParamError` and let `Api::V1::BaseController`
  render the `:bad_request` response — never render that branch inline
  in the action, and never reuse `Api::Public::UnsupportedParamError`
  from V1.
- Use `current_steam_id` for anything identity-scoped — never a
  client-supplied identifier.
- Use `POST`, not `GET`, when the request needs a body — e.g. an array of
  `market_hash_names` too unwieldy for query params — even when the
  action itself is a read (`index`), not a create. No current controller
  action needs this (the retired `price_histories` route was this rule's
  original example; `item_prices#dynamics`/`#trend` turned out not to
  need any params at all, since they derive their item set from
  `current_steam_id` via `UserInventoryCache` instead of a client-supplied
  list — see `agent/plans/dashboard-api-redesign.md`'s "Why endpoints
  2/3 need no params"); this rule still applies the moment an action
  needs to accept a body-shaped input again.

### SHOULD

- Keep exactly one collaborator call per action. If an action needs more
  than one `Steam::Client` call or query chain, that's a sign the logic
  belongs in a builder/action object instead of the controller.
- Batch worker enqueues from a controller with `each_slice(n)` rather
  than one job per record when backfilling in bulk. No current
  controller action does this (`InventoriesController#show`'s backfill
  moved into `UserInventorySyncService`'s single `Item.upsert_all` call —
  see `agent/adr/fetcher/cross-scenario-service-layer.md`); this rule
  still applies the moment a controller needs to batch-enqueue again.

### MUST NOT

- Don't add `skip_before_action :authenticate_bridge_token!`. Every
  `Api::V1::` endpoint is authenticated by default; a genuinely public
  endpoint is a decision to make and document explicitly, not a one-line
  opt-out on a controller.
- Don't parse Steam's raw response body inside a controller — that's
  `Steam::Client`/its DTOs' job (see
  `agent/styleguides/fetcher/steam-response-objects.md`).

## Error Handling

Five failure shapes:

1. **Auth failures** — both `:unauthorized` with a `{ message: "..." }`
   body: missing token vs. invalid/expired token
   (`JWT::ExpiredSignature`, `JWT::DecodeError`, `JWT::VerificationError`,
   and `KeyError` all rescued together in `authenticate_bridge_token!`).
   A token that decodes but carries no `steam_id` claim, or a non-string
   one, is rejected the same as an invalid token.
2. **Explicit per-action failure branch** — today, only
   `InventoriesController`'s wrapped `Steam::Client` call: branch on
   `response.success?`, `:bad_request` with `{ message: response.error
   }`.
3. **Raised closed-enum validation error, caught centrally** — a query
   object validates a closed-enum query param (`period`) through
   `Options::DateRange::Param#parse`, or a sort param through
   `Appliers::SortApplier.call`, passing
   `Api::V1::UnsupportedParamError`
   (`lib/api/v1/unsupported_param_error.rb`) as `error_class`, instead
   of rendering inline. `Api::V1::BaseController` declares
   `rescue_from Api::V1::UnsupportedParamError, with:
   :render_unsupported_param_error`, rendering `:bad_request` with
   `{ message: exception.message }` (`"Unsupported period: <value>"`).
   Declare this specific handler *after* `rescue_from StandardError`:
   Rails resolves the most-recently-declared matching handler first, so
   the more specific handler must come second, not first. The class is
   namespace-local (mirroring `Api::Public::UnsupportedParamError`) — V1
   must not depend on the Public namespace's error class. The query
   raises; the controller never branches on `nil` to render the 400
   itself.
4. **Missing resource, caught centrally** — an action that looks up a
   path-segment resource with `Model.find_by!(...)` lets the miss raise
   `ActiveRecord::RecordNotFound`. `Api::V1::BaseController` declares
   `rescue_from ActiveRecord::RecordNotFound, with: :render_not_found`,
   rendering `:not_found` with `{ message: "Not found" }` (a generic
   body, not echoing the identifier). Declare it after
   `rescue_from StandardError` for the same ordering reason; its order
   relative to the `UnsupportedParamError` handler does not matter
   (neither exception subclasses the other). `ItemPricesController#history`
   is the canonical case.
5. **Unhandled/infra-level failures** — a single `rescue_from
   StandardError` on `Api::V1::BaseController`, catching anything that
   escapes an action un-rescued (a lost DB connection, any other
   unexpected runtime error — never a specific, named exception class).
   Always `{ message: "Internal error" }` with `:internal_server_error`
   — never the exception's own message or backtrace — and always logged
   first via `Rails.logger.error` (exception class, message,
   backtrace). The logging is required, not optional: `app_fetcher` has
   no error-tracking gem (Sentry/Rollbar/etc.), and Rails' own
   middleware-level exception logging is skipped once a `rescue_from`
   inside the controller has already handled the exception —
   `Rails.logger.error` is the only thing standing between this and a
   silently lost failure.

Shape 5 is a different category from the `MUST` rule above against a
defensive per-action rescue/branch for something that can't fail: that
rule targets a *speculative* branch for a specific exception class with
no live trigger. The `StandardError` catch-all is the opposite case: one
single, global handler for failures that are *never* "a condition that
can't occur" — unexpected infrastructure failures are unpredictable by
definition, not a branch added speculatively for a condition the code
can't actually hit. It never shadows an existing explicit branch:
`InventoriesController`'s `Steam::Client` failure path still renders its
own `:bad_request` directly, since that's a handled
`response.success? == false`, not a raised exception — `rescue_from`
only ever fires for whatever reaches it un-rescued. Shapes 3 and 4 are
different again: both are live, expected failures of caller input,
raised deep in the query/action and rendered once at the base
controller; neither is a speculative guard.

## Interaction With Other Layers

```text
Request (Authorization: Bearer <bridge token>)
    ↓
Api::V1::BaseController#authenticate_bridge_token!  (before_action)
    ↓ sets current_steam_id
Api::V1::<X>Controller action
    ↓ Steam::Client call  — or —  ActiveRecord query  — or —
      raise Api::V1::UnsupportedParamError
    ↓
render json: { ... }, status: :some_symbol
```

## Canonical Implementations

- `app_fetcher/app/controllers/application_controller.rb` — the
  namespace-neutral common ancestor.
- `app_fetcher/app/controllers/api/v1/base_controller.rb` — player
  bridge-token auth, the `StandardError` catch-all, and the
  `UnsupportedParamError` / `RecordNotFound` handlers.
- `app_fetcher/lib/api/v1/unsupported_param_error.rb` — the V1
  closed-enum validation error.
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb` —
  read-only inventory envelope rendered through `InventorySerializer`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` —
  `#history` is the canonical `find_by!` + 30-day cache + history-query
  branch.
- `app_fetcher/config/routes.rb`
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `app_fetcher/spec/requests/api/v1/item_prices_spec.rb`
