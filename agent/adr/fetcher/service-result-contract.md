# Uniform Service Result Contract for `app_fetcher`'s `app/services/` Layer

## Status

Accepted

(Supersedes the per-service result-shape position of
`agent/adr/fetcher/cross-scenario-service-layer.md`; see
`agent/styleguides/fetcher/services.md` for the corresponding "how".)

## Context

`app_fetcher`'s `app/services/` layer (introduced by
`agent/adr/fetcher/cross-scenario-service-layer.md`) exists for cohesive
application-layer operations — originally, sequences needed identically
from more than one Scenario (a controller action and a worker); membership
is now responsibility-based, with cross-Scenario reuse being a common
consequence rather than a criterion (see that ADR's 2026-10-19
amendment). It has three members, and each signals its outcome
differently:

- `UserInventorySyncService.call` returns a nested
  `UserInventorySyncService::Result` struct
  (`success`/`error`/`items`) — it has a real failure mode (the Steam
  call can fail).
- `PriceUpdateService.call` returns `void`; it communicates through the
  `Item` instance the caller hands it (mutated in place), and has no
  failure branch (its writes are bang methods that raise).
- `InventoryValueRecordingService.call` returns the written
  `InventoryValueLog`.

The code itself flags this as unresolved:
`user_inventory_sync_service.rb` carries a "Temporary: this Result shape
is defined inline per-service… Revisit extracting a shared base-service/
Result abstraction once `app/services/` has enough members to show what
that shape should actually be" comment.

A new requirement forces the question. `InventoryValueRecordingService`
must gain a **readiness gate**: it should deliberately write nothing when
the inventory is not yet fully priced (see
`agent/plans/portfolio-first-snapshot-race.md`). That introduces a third
outcome — *"ran normally, intentionally did not act"* — which none of the
three current shapes expresses: it is not a failure, and it is not a
success that produced a record.

Two constraints shape the solution:

- `T::Struct` forbids a second level of subclassing (`Steam::Response`'s
  own ADR documents this: a `T::Struct` subclass cannot itself be
  subclassed). So a shared base that per-service result classes inherit
  from is not available.
- `Steam::Response[T]` (`lib/steam/response.rb`) already establishes the
  sanctioned alternative: a `T::Struct` using `extend T::Generic` with a
  `type_member` payload, constructed as `Response[Payload].new(...)`, with
  a `success?` predicate.

## Decision

Every `app/services/` class exposes exactly one public method, `.call`,
returning a single shared value object: `ApplicationService::Result[Payload]`.

`ApplicationService::Result` is a `T::Struct` nested inside
`app_fetcher/app/services/application_service.rb` (the layer's own
shared value object, living with the base that builds it), modeled
directly on `Steam::Response`:

- `extend T::Generic`, `Payload = type_member(:out)` (covariant as of
  the 2026-10-20 amendment below);
- `const :status, Status` — a `T::Enum` with exactly three members:
  - `Success` — the service did its job; `data` carries the result;
  - `Skipped` — a precondition was not met, so the service deliberately
    did nothing; `data` is `nil`, `error` is `nil`;
  - `Failure` — the service could not do its job; `error` explains why;
- `const :data, T.nilable(Payload)`, `const :error, T.nilable(String)`;
- predicates `success?` (`Success`), `skipped?` (`Skipped`), `failed?`
  (`Failure`).

Constructed through the private `ApplicationService` helpers
(`success`/`failure`/`skipped`); see the 2026-10-20 amendment below for
why the original call-site `ApplicationService::Result[Payload].new(...)`
idiom moved behind a base class.

All three current services migrate:

- `UserInventorySyncService` → `Failure(error:)` on a Steam failure,
  `Success(data: <items>)` otherwise (its nested `Result` is removed).
- `PriceUpdateService` → `Success(data: <the updated Item>)`; callers stop
  reading the mutated argument and read `result.data` instead. It has no
  `Failure` path (bang writes still raise).
- `InventoryValueRecordingService` → `Skipped` when the gate is closed
  (no `UserInventory`, or an unpriced `marketable` item), `Success(data: <the
  log>)` otherwise.

Callers branch on `status` via the predicates — never on `data.nil?` to
infer why a result is empty. This supersedes the "per-service result
shape" position of
`agent/adr/fetcher/cross-scenario-service-layer.md`'s Decision and the
`PriceUpdateService`-returns-void reasoning in
`agent/styleguides/fetcher/architecture-layers.md`'s Canonical
Implementations.

## Amendment (2026-10-20): Construction Through `ApplicationService`

The outcome contract above is unchanged; the construction idiom moved
behind the base class and `Payload` became covariant. This also resolves
the "revisit extracting a shared base-service/Result abstraction"
question left open in the Context section.

Every `app_fetcher/app/services/` service now inherits
`ApplicationService`
(`app_fetcher/app/services/application_service.rb`). The value object is
nested there as `ApplicationService::Result`; there is no top-level
`ServiceResult` constant or separate file. The base defines three
private singleton helpers:

- `success(payload)` → `Success`, carrying `payload`, `error: nil`;
- `failure(error)` → `Failure`, `data: nil`, non-nil `error`;
- `skipped` → `Skipped`, `data` and `error` both nil.

`ApplicationService::Result::Payload` is declared covariant
(`type_member(:out)`). `success` is generic over the payload
(`type_parameters(:Payload)` / `T.type_parameter(:Payload)`), so the
payload is inferred from its argument and a mismatched payload is a
`srb tc` error at the call site. `failure`/`skipped` carry no payload
and return `ApplicationService::Result[T.noreturn]`; covariance makes
that a subtype of every concrete
`ApplicationService::Result[Payload]`, so each service's `.call` keeps
declaring its concrete payload with no per-service type declaration.

Inside the helpers, construction uses
`ApplicationService::Result[T.untyped]` because runtime generics are
erased — naming the type parameter in the method body
(`ApplicationService::Result[T.type_parameter(:Payload)]`) would call
`T.type_parameter` outside a `sig` and raise. The helper `sig` carries
the real type; this is the sanctioned `T.untyped` exception documented
in `agent/styleguides/ruby-sorbet.md`.

`ApplicationService` owns construction only: no orchestration, no
business logic, no per-service carve-outs. The result's statuses and
predicates are unchanged apart from the covariant `Payload`.
Direct `ApplicationService::Result[Payload].new(status:, data:, error:)`
construction is now confined to `ApplicationService` (and the
value-object spec).

Motivation: all four services repeated the same verbose
`ApplicationService::Result[...].new(status:, data:, error:)` call for
every outcome, and the per-service `Skipped` branch had already started
to hide that construction behind a local helper. A typed base helper
removes the repetition without adding a second result shape or changing
any caller's branching.

## Alternatives Considered

### Alternative: keep per-service result shapes (status quo)

Leave each service returning whatever it returns today and document the
new gate's `nil` return inline.

Rejected because:

- it does not answer the question the layer already flagged as open
  (there is still no shared shape to point a new service at);
- a bare `nil` return conveys neither "why" nor "try again later", and
  forces every caller to reach for `data.nil?` checks;
- the layer's unpredictability grows with each new member.

### Alternative: shared `success`/`error` struct with no `status` enum

Reuse the existing `UserInventorySyncService::Result` shape
(`success: Boolean`, `error`, payload) as the shared type, and model the
new gate as `success: true` with a `nil` payload.

Rejected because:

- `Success(nil)` is ambiguous — it cannot be distinguished from "ran and
  produced no payload" without an out-of-band convention, so the
  convention buys nothing over a plain `nil` return;
- `ruby-sorbet.md` already prefers a `T::Enum` over a `Hash`/flag set for
  a closed tag vocabulary (`Options::DateRange` is the precedent);
- two booleans (`success`, plus an implied `skipped`) can contradict.

### Alternative: return `T.nilable(InventoryValueLog)` from the gated service only

Change only `InventoryValueRecordingService` to return `nil` (or the log)
and leave the other two services as-is.

Rejected because:

- it solves one service while leaving the layer heterogeneous — the exact
  "revisit later" the code comment already deferred once;
- the two call sites of that service still can't tell "skipped" apart from
  "nothing to return" by type;
- the gate is the *motivation* for the shared contract, not the only
  future case; settling the contract now is cheaper than a third
  per-service shape.

### Alternative: per-service subclasses of a shared base result

`class UserInventorySyncService::Result < ApplicationService::Result` with its own
typed fields.

Rejected — not on style grounds but because it is impossible:
`sorbet-runtime` forbids subclassing a `T::Struct` (the same constraint
`Steam::Response`'s ADR documents). The generic `type_member` payload is
the sanctioned way to get one shared result type across many payload
types.

### Alternative: keep `PriceUpdateService` returning `void`

Amend the contract for services that produce a result, but leave
`PriceUpdateService`'s mutation-only `void` shape as a documented
carve-out.

Considered, since `PriceUpdateService`'s existing reasoning (no failure
branch, caller reads the passed-in object) is sound. Rejected in favor of
full uniformity: a single shared shape is the whole point, and a
carve-out reintroduces the "which service returns what" question at every
call site. The cost is small (one caller, plus its spec) and removing the
reliance on in-place mutation makes the worker's data flow explicit.

## Consequences

### Positive

- One predictable contract for the whole layer: every `.call` returns a
  `ApplicationService::Result`, branchable via `success?`/`skipped?`/`failed?`.
- The new "deliberately did nothing" outcome has a first-class name
  (`Skipped`) instead of an overloaded `nil`/`Success(nil)`.
- Removes reliance on in-place mutation for `PriceUpdateService`'s
  result.
- Gives future services a settled answer to "what do I return?" — the
  question the layer already deferred once.

### Negative

- Touches all three existing services and their callers/specs, not just
  the one the current bug requires.
- `ApplicationService::Result`'s generic construction
  (`ApplicationService::Result[Payload].new(...)`) is slightly more verbose than a
  per-service struct.
- A `Result` for a service with no failure/no-op branch
  (`PriceUpdateService`) is, in isolation, ceremony — accepted for
  uniformity.

### Risks

- A future contributor could add a fourth ad-hoc result shape by
  copy-pasting a service instead of reusing `ApplicationService::Result`; the
  styleguide's MUST rules are the guard.
- The `Skipped`/`Success` distinction could be misused to encode ordinary
  business branching ("nothing to do right now") where a failure or a
  domain value would be more honest; `Skipped` is reserved for a
  precondition the service deliberately declines to act on.

## Implementation Constraints

- `ApplicationService::Result` is nested inside
  `app_fetcher/app/services/application_service.rb` (not a separate
  `service_result.rb`, and not under a `Services::` module — the layer
  is flat).
- It is a `T::Struct` using `extend T::Generic` with
  `Payload = type_member(:out)`, mirroring `Steam::Response`; it must not
  be subclassed.
- `Status` is a `T::Enum` with exactly `Success`, `Skipped`, `Failure`; no
  other statuses without a new decision.
- `Skipped` never carries `error`; `Failure` always carries a non-nil
  `error`; `Success` carries the payload. Callers must not infer outcome from
  `data.nil?`.
- Every `app/services/` class's `.call` returns `ApplicationService::Result[...]`;
  there is no `void`/bare-record/nested-`Result` return any more.
- A service that raises (bang writes) does not need a `Failure` branch —
  `Failure` is for *expected* outcomes the service chooses to return, not
  a replacement for exceptions.
- Replacing the nested `UserInventorySyncService::Result` and the
  `PriceUpdateService`-returns-`void` note is required, not optional —
  both are superseded by this decision.

## Related

- `agent/styleguides/fetcher/services.md` — the "how".
- `agent/adr/fetcher/cross-scenario-service-layer.md` — the layer this
  contract applies to; its per-service result-shape position is
  superseded by this ADR.
- `agent/styleguides/fetcher/architecture-layers.md` — the layer map and
  canonical implementations, updated to point at `services.md`.
- `agent/adr/fetcher/steam-client-response-objects-and-rate-limiting.md`
  — the `T::Generic` + `type_member` + predicate pattern and the
  `T::Struct`-subclassing constraint this ADR relies on.
- `agent/styleguides/ruby-sorbet.md` — `T::Enum`, `T.nilable`, `T.let`
  conventions.
- `agent/plans/portfolio-first-snapshot-race.md` — the work that
  motivated settling the contract.
