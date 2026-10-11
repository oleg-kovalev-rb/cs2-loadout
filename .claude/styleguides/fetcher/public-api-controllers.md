---
description: Api::Public:: controller conventions in app_fetcher — the unauthenticated sibling namespace to Api::V1::, response-shape carryover, and query-param handling (clamped numerics, open-set array filters, closed-enum validation) for list-style endpoints.
---

# Public API Controllers (`Api::Public::`)

See `.claude/adr/fetcher/public-api-namespace.md` for why this is a
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
  this is duplicated rather than shared).

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
- **Closed-enum params** (e.g. `sort`): a small, fixed set of accepted
  values this codebase does enumerate (mirrors
  `ItemPricesController#history`'s existing `period` param — see its
  `ALLOWED_PERIODS` pattern). An unrecognized value **is** an error:
  `render json: { message: "Unsupported <param_name>: <value>" },
  status: :bad_request`, same shape as `history`'s own "Unsupported
  period" message.
- **Boolean params** (e.g. `stattrak`): compare the raw string against
  exactly `"true"` to mean "apply this filter." Any other value,
  including `"false"`, and absence, all mean "don't apply this filter"
  (both states included) — a boolean query param here is "opt into a
  restriction," not a three-state true/false/absent switch. Don't treat
  `"false"` as "filter to the opposite" unless an endpoint genuinely
  needs that; default to the "opt-in only" shape above unless stated
  otherwise.

## Responsibilities

Same shape as `internal-api-controllers.md`'s Responsibilities section:
a controller action parses/normalizes params, calls its collaborator(s)
(a model scope chain, a cache-class `.read`/`.write` pair), and renders
JSON based on the result. It does not invent new business logic beyond
assembling the response hash — filtering/sorting criteria live on the
model as scopes (`rails-layering.md`), not as ad hoc `where` calls
inlined in the action.

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
  `.claude/plans/public-items-catalog-endpoint.md`'s Out of Scope) —
  revisit whether the cap is still the right shape once rate-limiting
  exists.
- Reject an unrecognized closed-enum param value with `:bad_request` /
  `{ message: "Unsupported <param>: <value>" }`; never reject an open
  string-set array param value the same way (see Interface).

### SHOULD

- Keep exactly one collaborator call per action, same as
  `internal-api-controllers.md`'s SHOULD rule — if an action needs more
  than one model-scope chain, that's a sign of a missing scope
  composition, not a reason to add a second collaborator layer (see
  `architecture-layers.md`'s carve-out for plain read-only listing
  controllers — no `app/services/` class is warranted here, that layer
  is reserved for logic needed identically by more than one Scenario).

### MUST NOT

- Don't add any notion of caller identity to this namespace (no
  `current_steam_id`-equivalent, no per-caller scoping of any kind) — an
  endpoint that needs one belongs under `Api::V1::`.
- Don't validate an open string-set array param's values against an
  enumerated list — there isn't one, and inventing one just to validate
  against it duplicates data that already lives in `Item#metadata`.

## Error Handling

Same three-shape taxonomy as `internal-api-controllers.md`, minus the
auth-failure shape (there is no auth to fail):

1. **Explicit per-action failure branch** — a closed-enum param
   (`sort`) with an unrecognized value: `:bad_request` with
   `{ message: "Unsupported <param>: <value>" }`.
2. **Unhandled/infra-level failures** — `Api::Public::
   ApplicationController`'s own `rescue_from StandardError`, same
   behavior as `Api::V1::`'s (log via `Rails.logger.error`, render
   `{ message: "Internal error" }` / `:internal_server_error`) — see ADR
   for why this is declared independently rather than inherited.

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
structure) are governed by `.claude/styleguides/rspec-conventions.md`;
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

## Canonical Implementations

None yet — `Api::Public::ItemsController#catalog`
(`.claude/plans/public-items-catalog-endpoint.md`) is this namespace's
first controller. Update this section once that plan is implemented.

## Related ADR

`.claude/adr/fetcher/public-api-namespace.md`
