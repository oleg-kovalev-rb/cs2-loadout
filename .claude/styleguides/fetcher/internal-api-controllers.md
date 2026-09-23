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
  "inventories#show"`, `post "price_histories", to:
  "price_histories#index"`) — never a bare `resources :x`, since these
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
`Steam::Client` call, or a plain ActiveRecord query), and renders JSON.
It does not parse Steam's raw response itself (that's
`Steam::Client`/its DTOs' job) and carries no business logic beyond
simple set arithmetic (`items_names - items.keys`) — heavier lifting is
delegated (parsing to `Steam::ItemParser`, backfill to a worker).

## Dependencies

May call `Steam::Client` directly (a fresh `Steam::Client.new` per
request — no injection) and enqueue Sidekiq workers directly
(`ItemsListUpdateWorker.perform_async`). Relies on `ApplicationController`
for auth; never re-implements token verification in a specific
controller.

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
  branch is correct (see `PriceHistoriesController#index`) — don't add a
  defensive rescue/branch for something that can't fail.
- Use `current_steam_id` for anything identity-scoped — never a
  client-supplied identifier.
- Use `POST`, not `GET`, when the request needs a body — e.g. an array of
  `market_hash_names` too unwieldy for query params (see the
  `price_histories` route and its request spec) — even when the action
  itself is a read (`index`), not a create.

### SHOULD

- Keep exactly one collaborator call per action. If an action needs more
  than one `Steam::Client` call or query chain, that's a sign the logic
  belongs in a builder/action object instead of the controller.
- Batch worker enqueues from a controller with `each_slice(n)` rather
  than one job per record when backfilling in bulk (see
  `InventoriesController#save_missing_items`).

### MUST NOT

- Don't add `skip_before_action :authenticate_bridge_token!`. Every
  `Api::V1::` endpoint is authenticated by default; a genuinely public
  endpoint is a decision to make and document explicitly, not a one-line
  opt-out on a controller.
- Don't parse Steam's raw response body inside a controller — that's
  `Steam::Client`/its DTOs' job (see
  `.claude/styleguides/fetcher/steam-response-objects.md`).

## Error Handling

Two authentication failure shapes, both `:unauthorized` with a `{
message: "..." }` body: missing token vs. invalid/expired token
(`JWT::ExpiredSignature`, `JWT::DecodeError`, `JWT::VerificationError`
all rescued together in `authenticate_bridge_token!`). Beyond auth, only
`InventoriesController` has a failure path today — the wrapped
`Steam::Client` call — mapped to `:bad_request` with `{ message:
response.error }`.

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
- `app_fetcher/app/controllers/api/v1/price_histories_controller.rb`
- `app_fetcher/config/routes.rb`
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `app_fetcher/spec/requests/api/v1/price_histories_spec.rb`
