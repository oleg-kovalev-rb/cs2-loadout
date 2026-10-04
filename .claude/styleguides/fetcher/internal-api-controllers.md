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
call directly (no such endpoint exists today), and not for an endpoint
that doesn't need bridge-token auth — see MUST NOT below.

## Structure

- `app/controllers/api/v1/<resource>_controller.rb`, nested
  `Api::V1::<X>Controller`, mirroring the `namespace :api do; namespace
  :v1 do; ...; end; end` block in `config/routes.rb`.
- Routes are declared explicitly (`get "inventories/me", to:
  "inventories#show"`, `get "item_prices/dynamics", to:
  "item_prices#dynamics"`) — never a bare `resources :x`, since these
  aren't CRUD resources.
- `ApplicationController < ActionController::API` (no views, sessions,
  or cookies — a pure JSON API base) applies `before_action
  :authenticate_bridge_token!` globally, not opt-in per controller.

## Interface

- Every action's `sig` is `{ void }` — actions communicate only through
  `render`, never a Ruby return value.
- Every response is `render json: { ... }, status: :some_symbol` — never
  `render json: some_object` directly; always an explicit hash and an
  explicit status symbol, even for a single error message.
- Error bodies are always shaped `{ message: "..." }` (see
  `authenticate_bridge_token!`'s "Missing/Invalid bridge token",
  `InventoriesController#show`'s `{ message: response.error }`).
- `current_steam_id` (from `ApplicationController`) is the only source of
  the caller's identity — never read a `steam_id`/user identifier out of
  `params`.

## Responsibilities

A controller action parses params, calls exactly one collaborator (a
`Steam::Client` call, a plain ActiveRecord query, or — per the narrow
exception in `.claude/adr/fetcher/cross-scenario-service-layer.md` — a
cross-Scenario service), and renders JSON based on that single call's
result. It does not parse Steam's raw response itself (that's
`Steam::Client`/its DTOs' job) and carries no business logic beyond a
conditional render — heavier lifting (Steam calls, item resolution,
backfill, persistence) is delegated entirely to the one collaborator.

## Dependencies

May call `Steam::Client` directly (a fresh `Steam::Client.new` per
request — no injection) and enqueue Sidekiq workers directly
(`PriceUpdateWorker.perform_async`). Relies on `ApplicationController`
for auth; never re-implements token verification in a specific
controller. See `.claude/adr/fetcher/cross-scenario-service-layer.md`
for the two named exceptions: `InventoriesController#show`'s cold-start
branch and `#refresh` call `UserInventorySyncService` synchronously
instead of enqueuing, and `InventoryValuesController#index`'s cold-start
seed calls `InventoryValueRecordingService` the same way.

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
  that has no live trigger in today's call sites (e.g. no `rescue_from
  ActiveRecord::RecordNotFound` — see Error Handling for why this is a
  different case from the global `StandardError` catch-all).
- Use `current_steam_id` for anything identity-scoped — never a
  client-supplied identifier.
- Use `POST`, not `GET`, when the request needs a body — e.g. an array of
  `market_hash_names` too unwieldy for query params — even when the
  action itself is a read (`index`), not a create. No current controller
  action needs this (the retired `price_histories` route was this rule's
  original example; `item_prices#dynamics`/`#trend` turned out not to
  need any params at all, since they derive their item set from
  `current_steam_id` via `UserInventoryCache` instead of a client-supplied
  list — see `.claude/plans/dashboard-api-redesign.md`'s "Why endpoints
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
  see `.claude/adr/fetcher/cross-scenario-service-layer.md`); this rule
  still applies the moment a controller needs to batch-enqueue again.

### MUST NOT

- Don't add `skip_before_action :authenticate_bridge_token!`. Every
  `Api::V1::` endpoint is authenticated by default; a genuinely public
  endpoint is a decision to make and document explicitly, not a one-line
  opt-out on a controller.
- Don't parse Steam's raw response body inside a controller — that's
  `Steam::Client`/its DTOs' job (see
  `.claude/styleguides/fetcher/steam-response-objects.md`).

## Error Handling

Three failure shapes:

1. **Auth failures** — both `:unauthorized` with a `{ message: "..." }`
   body: missing token vs. invalid/expired token
   (`JWT::ExpiredSignature`, `JWT::DecodeError`, `JWT::VerificationError`
   all rescued together in `authenticate_bridge_token!`).
2. **Explicit per-action failure branch** — today, only
   `InventoriesController`'s wrapped `Steam::Client` call: branch on
   `response.success?`, `:bad_request` with `{ message: response.error
   }`.
3. **Unhandled/infra-level failures** — a single `rescue_from
   StandardError` on `ApplicationController`, catching anything that
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

Shape 3 is a different category from the `MUST` rule above against a
defensive per-action rescue/branch for something that can't fail: that
rule targets a *speculative* branch for a *specific* exception class
with no live trigger in today's code (e.g. `ActiveRecord::RecordNotFound`
— no `find`/`find_by!` call exists anywhere in `Api::V1::`, only
`find_by`, so there is deliberately no `rescue_from` for it). The
`StandardError` catch-all is the opposite case: one single, global
handler for failures that are *never* "a condition that can't occur" —
unexpected infrastructure failures are unpredictable by definition, not
a branch added speculatively for a condition the code can't actually hit.
It never shadows an existing explicit branch: `InventoriesController`'s
`Steam::Client` failure path still renders its own `:bad_request`
directly, since that's a handled `response.success? == false`, not a
raised exception — `rescue_from` only ever fires for whatever reaches it
un-rescued.

## Interaction With Other Layers

```text
Request (Authorization: Bearer <bridge token>)
    ↓
ApplicationController#authenticate_bridge_token!  (before_action)
    ↓ sets current_steam_id
Api::V1::<X>Controller action
    ↓ Steam::Client call  — or —  ActiveRecord query
    ↓
render json: { ... }, status: :some_symbol
```

## Canonical Implementations

- `app_fetcher/app/controllers/application_controller.rb`
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb`
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb`
- `app_fetcher/config/routes.rb`
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `app_fetcher/spec/requests/api/v1/item_prices_spec.rb`
