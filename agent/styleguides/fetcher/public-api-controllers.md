---
description: Api::Public:: controller conventions in app_fetcher — the unauthenticated sibling namespace to Api::V1::, response-shape carryover, query-param handling (clamped numerics, open-set array filters, closed-enum validation) for list-style endpoints, and not-found handling for single-resource lookups.
---

# Public API Controllers (`Api::Public::`)

See `agent/adr/fetcher/public-api-namespace.md` for why this is a
separate namespace with its own, independently-declared base controller
rather than an opt-out on `Api::V1::` or a shared ancestor between the
two. This file covers how code inside `Api::Public::` is written, once
that decision is taken as given.

## Purpose

Expose data that genuinely has no caller-specific identity and no
caller restriction — today, read-only, already-persisted catalog data —
to any client at all, not just `app_core`. What belongs here: endpoints
that would return the exact same data for every caller given the same
parameters. What does not: anything that reads or branches on a caller's
identity (that's `Api::V1::`'s job), and anything that writes/mutates
state (every endpoint in this namespace is a plain read).

## When to Use

Use this namespace when a new endpoint must be callable with no bridge
token and the response doesn't depend on who's asking. Do not use it as
a way to avoid dealing with bridge-token auth for an endpoint that
*does* have a notion of caller identity, even a weak one — that
endpoint belongs under `Api::V1::`. Do not add a `skip_before_action`
exception to `Api::V1::ApplicationController` instead of using this
namespace — see `internal-api-controllers.md`'s MUST NOT rule, which
this namespace exists specifically to honor rather than work around.

## Structure

- `app/controllers/api/public/<resource>_controller.rb`, nested
  `Api::Public::<X>Controller`, mirroring `namespace :api do; namespace
  :public do; ...; end; end` in `config/routes.rb` — same explicit-route
  convention as `Api::V1::` (no bare `resources`, see
  `internal-api-controllers.md`'s Structure section; that reasoning
  applies identically here).
- `Api::Public::ApplicationController < ActionController::API` — no
  `before_action` for authentication. Declares its own
  `rescue_from StandardError, with: :render_internal_server_error`,
  independent of `Api::V1::ApplicationController`'s (see ADR for why
  this is duplicated rather than shared). Also declares
  `rescue_from ActiveRecord::RecordNotFound, with: :render_not_found`,
  for any single-resource-by-identifier action — see Error Handling.
- `lib/api/public/unsupported_param_error.rb` — `Api::Public::
  UnsupportedParamError < StandardError`. One shared exception type for
  every "caller supplied an unrecognized closed-enum value" case raised
  from inside the query-objects layer across this whole namespace — not
  one subclass per param name, since the response shape is identical
  regardless of which param was invalid. This is a namespace-level
  concern (hence living here, under `lib/api/public/`, rather than under
  `agent/styleguides/fetcher/list-query-objects.md`'s layer) — any
  future `Api::Public::` code that needs to signal the same kind of
  failure raises this same class, not a new one.

## Interface

Response-shape conventions are identical to `Api::V1::`'s — not
restated here, see `internal-api-controllers.md`'s own Interface and
Error Handling sections: every action's `sig` is `{ void }`; every
response is an explicit `render json: { ... }, status: :some_symbol`;
error bodies are always `{ message: "..." }`.

**Query-param handling** is new territory this namespace introduces —
no `Api::V1::` action has ever taken more than one scalar param. Three
distinct param shapes, each with its own validation posture:

- **Bounded numeric params** (e.g. `page`, `per_page`): have a default,
  and a valid range. Coerce with `.to_i` and **clamp** silently into
  range — never reject. A garbage, negative, zero, or non-numeric value
  becomes the nearest valid value (typically the default or the range
  floor), not a `:bad_request`. The upper bound exists to cap worst-case
  response size/cost per request (see Rules, MUST — this is this
  namespace's only defense against an oversized single request, pending
  real rate-limiting).
- **Open string-set array params** (e.g. `category[]`, `rarity[]`):
  filter by exact match against an unbounded, caller-facing set of
  string values this codebase doesn't enumerate anywhere. An
  unrecognized value is not an error — it simply matches no rows (an
  empty-array-equivalent result for that criterion, same as any other
  value that happens to match nothing). Never validate these against a
  known-values list; there isn't one to validate against.
- **Closed-enum params** (e.g. `sort`, `period`, `range`): a small, fixed
  set of accepted values this codebase does enumerate. An unrecognized
  value **is** an error: `render json: { message: "Unsupported
  <param_name>: <value>" }, status: :bad_request`. Sort params are
  resolved and raised by `Appliers::SortApplier` (or an `Options::*`
  value's own `#apply`) in the query-objects layer. Period/range params
  are resolved by `PricePeriod.resolve` against the queried model's
  `SUPPORTED_PERIODS` (`InventoryValueLog` without `24h`, `PriceLog` with
  every period); a query object raises `Api::Public::
  UnsupportedParamError` on nil, while an `Api::V1` action keeps its own
  inline `:bad_request` branch. See
  `agent/styleguides/fetcher/list-query-objects.md`'s Interface section
  and this file's own Error Handling section below for the resulting
  response shape, which is identical either way.
- **Boolean params** (e.g. `stattrak`): compare the raw string against
  exactly `"true"` to mean "apply this filter." Any other value,
  including `"false"`, and absence, all mean "don't apply this filter"
  (both states included) — a boolean query param here is "opt into a
  restriction," not a three-state true/false/absent switch. Don't treat
  `"false"` as "filter to the opposite" unless an endpoint genuinely
  needs that; default to the "opt-in only" shape above unless stated
  otherwise.

A path-segment resource identifier (e.g. `:steam_id` in `/inventories/
:steam_id`) isn't a query param, but gets the same "resolve, don't
branch on absence inline" posture as the closed-enum case above: look
the resource up with a bang finder (`Model.find_by!(...)`), and let a
non-existent identifier raise `ActiveRecord::RecordNotFound` rather than
checking for `nil` and rendering `:not_found` by hand in the action —
see Error Handling for the resulting response shape.

## Responsibilities

Same shape as `internal-api-controllers.md`'s Responsibilities section:
a controller action parses/normalizes params, calls its collaborator(s),
and renders JSON based on the result. It does not invent new business
logic — filtering/sorting criteria live on the model as scopes
(`rails-layering.md`), not as ad hoc `where` calls inlined in the
action, and assembling the response hash is not the controller's job
either for a list endpoint built on the query-objects layer (see
`agent/styleguides/fetcher/list-query-objects.md`): that belongs to
the corresponding `app/serializers/` class. A simpler, single-lookup
action may still assemble its own small response hash directly, same as
today — this only changes once an action's response shape comes from
that layer's `<Resource>CatalogQuery`/`<Resource>CatalogSerializer`
pair.

## Dependencies

May call models (including scopes) and caching classes
(`app/caching/`) directly — same dependency set `Api::V1::` already has
for its own read-only actions. Unlike `Api::V1::`, has no
`current_steam_id` (there is no caller identity to have) and must never
introduce one — a param that looks like it's selecting "whose data" is a
sign the endpoint belongs under `Api::V1::` instead.

## Rules

### MUST

- Give `Api::Public::` its own base controller
  (`Api::Public::ApplicationController`), never inherit from or extend
  `Api::V1::ApplicationController` — see ADR.
- Cap every bounded numeric param's upper range explicitly (e.g.
  `per_page`) — an unauthenticated, not-yet-rate-limited namespace has
  no other defense against a single request requesting an unbounded
  amount of data. This is a stopgap, not a substitute for real
  rate-limiting (explicitly out of scope as of this writing, see
  `agent/plans/public-items-catalog-endpoint.md`'s Out of Scope) —
  revisit whether the cap is still the right shape once rate-limiting
  exists.
- Reject an unrecognized closed-enum param value with `:bad_request` /
  `{ message: "Unsupported <param>: <value>" }`; never reject an open
  string-set array param value the same way (see Interface).
- For a single-resource-by-identifier endpoint, look the resource up with
  a bang finder (`Model.find_by!(...)`) and let a missing record raise
  `ActiveRecord::RecordNotFound`, caught centrally (see Error Handling) —
  never branch on a `nil` return to render `:not_found` by hand inline.
  Keeps this namespace's error-production shape consistent with the
  closed-enum case: raise deep, catch once, at the base controller.

### SHOULD

- For a plain single-lookup action with no sibling needing the same
  mechanics, keep exactly one collaborator call per action, same as
  `internal-api-controllers.md`'s SHOULD rule — if an action needs more
  than one model-scope chain, that's a sign of a missing scope
  composition, not a reason to add a second collaborator layer (see
  `architecture-layers.md`'s carve-out for plain read-only listing
  controllers — no `app/services/` class is warranted here, that layer
  is reserved for logic needed identically by more than one Scenario).
- For a list endpoint built on the query-objects layer
  (`agent/styleguides/fetcher/list-query-objects.md`), the expected
  shape is instead a fixed, explicit sequence, not one collaborator:
  cache read (`<Resource>Cache.read`) → on miss, `<Resource>CatalogQuery.call`
  → `<Resource>CatalogSerializer.call` → cache write
  (`<Resource>Cache.write`) → `stale?`/render. This is not a violation of
  the single-lookup rule above — it's a different, equally fixed shape
  for a different kind of action, chosen because caching and
  conditional-GET must stay in the controller (see that file's
  Responsibilities section) while query/serialization are delegated.
  Don't add steps to this sequence beyond what that file documents.

### MUST NOT

- Don't add any notion of caller identity to this namespace (no
  `current_steam_id`-equivalent, no per-caller scoping of any kind) — an
  endpoint that needs one belongs under `Api::V1::`.
- Don't validate an open string-set array param's values against an
  enumerated list — there isn't one, and inventing one just to validate
  against it duplicates data that already lives in `Item#metadata`.

## Error Handling

Four shapes, minus the auth-failure shape `internal-api-controllers.md`
has (there is no auth to fail):

1. **Explicit per-action failure branch** — a closed-enum param
   (`sort`, `period`, `range`) with an unrecognized value, validated
   inline in the controller action itself: `:bad_request` with
   `{ message: "Unsupported <param>: <value>" }`. Used by any action not
   built on the query-objects layer (e.g. `ItemPricesController#history`'s
   `PricePeriod`/`SUPPORTED_PERIODS` pattern, in `Api::V1::`).
2. **Raised from the query-objects layer, caught centrally** — for a
   list endpoint built on `agent/styleguides/fetcher/list-query-objects.md`,
   sort validation is performed by `Appliers::SortApplier` (or an
   `Options::*` value's own `#apply`), and period/range validation is
   performed by the query object after `PricePeriod.resolve` returns nil.
   Both raise `Api::Public::UnsupportedParamError`
   (`lib/api/public/unsupported_param_error.rb`)
   instead of returning an error for the controller to branch on.
   `Api::Public::ApplicationController` declares
   `rescue_from Api::Public::UnsupportedParamError, with:
   :render_unsupported_param_error`, rendering the identical
   `:bad_request` / `{ message: "Unsupported <param>: <value>" }` shape
   as (1) — only how the error is produced differs, not its response.
   This `rescue_from` is declared *after* `rescue_from StandardError`
   below — Rails resolves the most-recently-declared matching handler
   first, so the more specific handler must come second, not first.
3. **Unhandled/infra-level failures** — `Api::Public::
   ApplicationController`'s own `rescue_from StandardError`, same
   behavior as `Api::V1::`'s (log via `Rails.logger.error`, render
   `{ message: "Internal error" }` / `:internal_server_error`) — see ADR
   for why this is declared independently rather than inherited.
4. **Raised by a plain lookup, caught centrally** — a single-resource
   endpoint identified by a path segment (e.g. `:steam_id`) that doesn't
   exist: looked up via `Model.find_by!(...)` (never a `nil`-checking
   branch inline, per Interface/Rules), which raises
   `ActiveRecord::RecordNotFound`. `Api::Public::ApplicationController`
   declares `rescue_from ActiveRecord::RecordNotFound, with:
   :render_not_found`, rendering `:not_found` /
   `{ message: "<Resource> not found" }` — the static message names the
   resource, not the identifier's value (unlike shape (2) above, which
   echoes the caller's bad value back into the message). Same mechanism
   as (2): raise deep inside the lookup/query layer, catch once at the
   base controller, never branch on a return value in the action. This
   `rescue_from` must also be declared *after* `rescue_from
   StandardError` above, for the same reason as (2); its order relative
   to `rescue_from Api::Public::UnsupportedParamError` doesn't matter —
   neither exception is a subclass of the other, so Rails' most-
   recently-declared-first resolution never has to choose between them
   for the same raised exception.

## Interaction With Other Layers

```text
Request (no Authorization header)
    ↓
Api::Public::<X>Controller action
    ↓ normalize/clamp params
    ↓ model scope chain  — or —  caching-class .read/.write
    ↓
render json: { ... }, status: :some_symbol
```

## Testing

General RSpec mechanics (spec levels, `FactoryBot`, request-spec
structure) are governed by `agent/styleguides/rspec-conventions.md`;
this section only adds what's specific to this namespace.

### MUST

- Every request spec in this namespace must include a case confirming
  the action succeeds with **no** `Authorization` header at all — the
  inverse of every `Api::V1::` spec's "without a bridge token →
  `:unauthorized`" case, and the one assertion that actually proves an
  endpoint belongs in this namespace rather than `Api::V1::`.
- Cover each of the four param shapes from Interface with its own
  scenario: a clamped-numeric edge case (garbage/out-of-range value),
  an unrecognized open-set array value (matches nothing, no error), an
  unrecognized closed-enum value (`:bad_request`), and the boolean
  param's three states (`"true"` / `"false"` / absent).
- A single-resource-by-identifier endpoint's request spec must include a
  case for an identifier that doesn't exist, asserting `:not_found` /
  `{ message: "<Resource> not found" }`.

## Canonical Implementations

None yet — `Api::Public::ItemsController#index`
(`agent/plans/item-catalog-query-refactor.md`, superseding the
`#catalog` shape `agent/plans/public-items-catalog-endpoint.md`
originally shipped) will be this namespace's first controller built on
the query-objects layer, and the first to use the `rescue_from
Api::Public::UnsupportedParamError` shape. Update this section once that
plan is implemented.

The `rescue_from ActiveRecord::RecordNotFound` shape (Error Handling,
(4)) has no implementation yet either — `Api::Public::
InventoriesController#show` (`agent/plans/public-inventory-endpoints.md`)
will be its first. Update this section once that plan is implemented.

## Related ADR

`agent/adr/fetcher/public-api-namespace.md`

## Related

- `agent/adr/fetcher/list-query-objects-layer.md` — why list-endpoint
  filter/sort/pagination/serialization logic lives in its own layer
  rather than inline in the controller.
- `agent/styleguides/fetcher/list-query-objects.md` — the concrete
  `app/queries/`/`app/serializers/` conventions this file's
  Responsibilities/Rules/Error Handling sections now reference.
