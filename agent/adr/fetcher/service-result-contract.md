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
returning a single shared value object: `ServiceResult[Payload]`.

`ServiceResult` is a top-level `T::Struct` in
`app_fetcher/app/services/service_result.rb` (the layer's own shared
value object, living with the layer), modeled directly on
`Steam::Response`:

- `extend T::Generic`, `Payload = type_member`;
- `const :status, Status` — a `T::Enum` with exactly three members:
  - `Ok` — the service did its job; `data` carries the result;
  - `Skipped` — a precondition was not met, so the service deliberately
    did nothing; `data` is `nil`, `error` is `nil`;
  - `Failed` — the service could not do its job; `error` explains why;
- `const :data, T.nilable(Payload)`, `const :error, T.nilable(String)`;
- predicates `success?` (`Ok`), `skipped?` (`Skipped`), `failed?`
  (`Failed`).

Constructed at the call site as
`ServiceResult[Payload].new(status:, data:, error:)` — the same idiom
`Steam::Response[...].new(...)` already uses.

All three current services migrate:

- `UserInventorySyncService` → `Failed(error:)` on a Steam failure,
  `Ok(data: <items>)` otherwise (its nested `Result` is removed).
- `PriceUpdateService` → `Ok(data: <the updated Item>)`; callers stop
  reading the mutated argument and read `result.data` instead. It has no
  `Failed` path (bang writes still raise).
- `InventoryValueRecordingService` → `Skipped` when the gate is closed
  (no `UserInventory`, or an unpriced `marketable` item), `Ok(data: <the
  log>)` otherwise.

Callers branch on `status` via the predicates — never on `data.nil?` to
infer why a result is empty. This supersedes the "per-service result
shape" position of
`agent/adr/fetcher/cross-scenario-service-layer.md`'s Decision and the
`PriceUpdateService`-returns-void reasoning in
`agent/styleguides/fetcher/architecture-layers.md`'s Canonical
Implementations.

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

- `Ok(nil)` is ambiguous — it cannot be distinguished from "ran and
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

`class UserInventorySyncService::Result < ServiceResult` with its own
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
  `ServiceResult`, branchable via `success?`/`skipped?`/`failed?`.
- The new "deliberately did nothing" outcome has a first-class name
  (`Skipped`) instead of an overloaded `nil`/`Ok(nil)`.
- Removes reliance on in-place mutation for `PriceUpdateService`'s
  result.
- Gives future services a settled answer to "what do I return?" — the
  question the layer already deferred once.

### Negative

- Touches all three existing services and their callers/specs, not just
  the one the current bug requires.
- `ServiceResult`'s generic construction
  (`ServiceResult[Payload].new(...)`) is slightly more verbose than a
  per-service struct.
- A `Result` for a service with no failure/no-op branch
  (`PriceUpdateService`) is, in isolation, ceremony — accepted for
  uniformity.

### Risks

- A future contributor could add a fourth ad-hoc result shape by
  copy-pasting a service instead of reusing `ServiceResult`; the
  styleguide's MUST rules are the guard.
- The `Skipped`/`Ok` distinction could be misused to encode ordinary
  business branching ("nothing to do right now") where a failure or a
  domain value would be more honest; `Skipped` is reserved for a
  precondition the service deliberately declines to act on.

## Implementation Constraints

- `ServiceResult` lives at
  `app_fetcher/app/services/service_result.rb`, top-level (not under a
  `Services::` module — the layer is flat), an exception to the layer's
  `<Noun>Service` file naming (it is the layer's value object, not a
  service).
- It is a `T::Struct` using `extend T::Generic` with `Payload =
  type_member`, mirroring `Steam::Response`; it must not be subclassed.
- `Status` is a `T::Enum` with exactly `Ok`, `Skipped`, `Failed`; no
  other statuses without a new decision.
- `Skipped` never carries `error`; `Failed` always carries a non-nil
  `error`; `Ok` carries the payload. Callers must not infer outcome from
  `data.nil?`.
- Every `app/services/` class's `.call` returns `ServiceResult[...]`;
  there is no `void`/bare-record/nested-`Result` return any more.
- A service that raises (bang writes) does not need a `Failed` branch —
  `Failed` is for *expected* outcomes the service chooses to return, not
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
