---
description: app_fetcher's app/services/ layer — what a service owns, when it is warranted (responsibility/SRP, not caller count), its flat top-level naming and single .call entry point, and the uniform ServiceResult[Payload] return contract (Ok/Skipped/Failed) every service uses.
---

# Services (`app/services/`)

See `agent/adr/fetcher/service-result-contract.md` for why the return
contract is shaped this way, and
`agent/adr/fetcher/cross-scenario-service-layer.md` for why this layer
exists. This file states the rules.

## Purpose

Give a cohesive unit of business logic its own class when keeping it in
its caller would leave that caller with more than one responsibility.

A service is defined by what it owns, not by how many callers it has: one
business operation with a single `.call` entry point, one reason to
change, and boundaries that can be tested in isolation. It owns the
orchestration sequence (fetch → resolve → act → persist), including its
external calls and persistence.

It is not a home for logic that already belongs to an existing layer:
Steam-response parsing (parser), DTO → AR attributes (builder), read-only
aggregate reads (query object), cache mechanics (caching), or a model's
own invariants (model). See `architecture-layers.md`'s `app/services/`
Structure entry for where the layer sits.

## When to Use

Create a service when the logic is a single, nameable business operation
and no existing layer owns it. Both must hold:

- **It is one operation, not a bag of helpers.** You can state it as a
  verb phrase ("sync a user's inventory", "record an inventory
  valuation", "apply a price update") and say what must be true when it
  finishes.
- **It has no better existing home.** It is not parsing, building, a
  read-only query, cache mechanics, or a model invariant. Keeping it
  inline would leave a worker's `perform` or a controller action mixing
  orchestration with domain logic.

The number of callers is not a criterion. A single call site is not a
reason to keep mixed responsibilities in a worker or a controller, and
cross-Scenario reuse is not a requirement for creating a service — it is
a common consequence of drawing the right boundary, not the test for
where that boundary is. `PriceUpdateService` is a single-Scenario
service of this shape; `UserInventorySyncService` is a cross-Scenario
one.

This layer is not a place for every method that made a class long: if the
extraction would be a couple of delegating lines with no independent
behaviour, keep it inline. And if the logic is really parsing, building,
reading, or caching, it belongs in that layer, not here.

Choosing the right home:

| The logic is...                                            | Home         |
|------------------------------------------------------------|--------------|
| parsing a raw Steam response into a typed DTO              | parser       |
| turning a DTO/API response into AR attributes              | builder      |
| a read-only aggregate or list query                        | query object |
| cache keying / read-through / invalidation                 | caching      |
| a model's own invariant or association behaviour           | model        |
| a cohesive sequence that acts (writes or has side effects) | service      |

## Structure

- Flat under `app/services/`, top-level, named `<Noun>Service`
  (`UserInventorySyncService`, not `Steam::UserInventorySyncService` and
  not `Services::UserInventorySyncService`) — the same non-namespacing
  every other `app_fetcher` application-layer class follows (parsers,
  builders, workers, schedulers, caching), even when the class calls
  `Steam::Client`.
- One class per sequence; no shared base class.
- `ServiceResult` (`app/services/service_result.rb`) is the single,
  deliberate exception to the `<Noun>Service` file/class naming: it is
  the layer's shared value object, not a service.
- Callers are workers, and controllers for:
  - the named synchronous-persistence call sites in
    `cross-scenario-service-layer.md` (plus `admin-api-controllers.md`'s
    `sync` call site); and
  - a cohesive side-effect operation the controller would otherwise have
    to implement itself — e.g. `PriceWarmupService` owning the warmup
    cap, dedup key/TTL, and `PriceUpdateWorker` enqueue loop for
    `ItemPricesController#dynamics`. This is not the persistence
    carve-out: the service writes no records, it only performs the
    controller's existing side effects behind one nameable operation.
  A service may have a single caller.

## Interface

- **One public class method**: `self.call(...)`. No other public methods.
- `sig` returns `ServiceResult[Payload]` (see Rules) — never `void`, never
  a bare model instance, never a nested per-service `Result`.
- `ServiceResult[Payload]` is a top-level `T::Struct` (modeled on
  `Steam::Response`): a `Status` `T::Enum` (`Ok`/`Skipped`/`Failed`),
  `data: T.nilable(Payload)`, `error: T.nilable(String)`, and the
  predicates `success?`/`skipped?`/`failed?`.
- Construct it at the call site as
  `ServiceResult[Payload].new(status:, data:, error:)`, the same idiom as
  `Steam::Response[Payload].new(...)`.
- `ServiceResult` must not be subclassed (sorbet-runtime forbids
  subclassing a `T::Struct`); the generic `Payload` is how one shared
  result type carries different payloads.

## Responsibilities

Owns: the whole fetch → resolve → act → persist sequence it exists for,
including its external calls and its persistence. Does not own: response
rendering (controller), Steam-response parsing (parser/DTO), or Steam HTTP
mechanics (client). When its read step is a shared aggregate, it
delegates to the query layer (`InventoryValueQuery`) instead of
re-implementing the SQL; the service remains the only writer.

A service is responsible for **deciding whether its own preconditions are
met** — a condition its callers would otherwise have to re-check belongs
inside the service, reported as `Skipped` (see Rules), not duplicated at
each call site.

## Dependencies

May depend on `Steam::Client`, the `app/caching/` classes, parsers,
models, and read-only query objects under `app/queries/` for its read
step (e.g. `InventoryValueRecordingService` calling
`InventoryValueQuery`) — the same dependency set a worker already has,
plus the query layer. A query-object dependency does not transfer write
ownership: the service still owns the sequence and persistence, and the
query only reads/computes. Must not be called *from* a model, a query
object, or a serializer, and must not reach up into controllers.

## Rules

### MUST

- Expose a single `self.call` entry point.
- Return `ServiceResult[Payload]` from `.call`. There is no other allowed
  return shape.
- Use exactly the three statuses:
  - `Ok` when the service did its job — `data` carries the produced
    result (the written record, the resolved list, the updated model);
    `error` is `nil`.
  - `Skipped` when a **precondition the service itself owns** is not met,
    so it deliberately performed no write/action — `data` and `error` are
    both `nil`. `Skipped` is not a failure and not a success-with-no-data;
    it is the honest "nothing to do yet".
  - `Failed` when the service could not do its job for an **expected**
    reason (e.g. a failed external call it chose to return rather than
    raise) — `error` is a non-nil explanation.
- Branch on the outcome via `success?`/`skipped?`/`failed?` at the call
  site — never infer it from `data.nil?`.
- Put a precondition that its callers share inside the service, so the
  check is not duplicated — returning `Skipped` rather than letting each
  caller guard first.

### SHOULD

- Carry the produced value in `data` even when the caller currently
  ignores it, rather than relying on in-place mutation of an argument.
- Keep `.call` orchestration-only; extract any further non-trivial
  parsing/building to the parser/builder layers.

### MUST NOT

- Don't add a nested per-service `Result` struct — reuse `ServiceResult`.
- Don't return `void` or a bare model instance from `.call`.
- Don't use `Skipped` for a failure (that is `Failed`) or for routine
  business branching where a domain value would be clearer — reserve it
  for a precondition the service deliberately declines to act on.
- Don't subclass `ServiceResult`.
- Don't let a caller assume a service ran successfully without checking
  `status`.

## Error Handling

- Expected, enumerable failure (e.g. a `Steam::Client` response that is
  not `success?`) → return `Failed(error: <response.error>)`; log a
  `[ClassName] ...` warning where the caller already does, per
  `background-jobs.md`.
- Unexpected failure → let it raise (bang writes keep raising). `Failed`
  is for outcomes the service chooses to return, not a replacement for
  exceptions, and does not engage Sidekiq `retry:` the way a raised
  exception does.
- Unmet precondition → `Skipped`. A caller that needs to try again later
  treats `Skipped` as "retry on a future request/run", not as an error.

## Interaction With Other Layers

```text
Api::V1::<X>Controller#action   (Scenario 1)
    ↓  .call(...)   — synchronous, inline, before rendering
Service.call
    ↓  Steam::Client / Caching / parsers / Models
    ⇢ returns ServiceResult[Payload]

<X>UpdateWorker#perform         (Scenario 3)
    ↓  .call(...)   — identical call
```

Both Scenarios call the identical `.call` and branch on the same
`ServiceResult`. A single-Scenario service has only one of these edges;
its call shape and return contract are unchanged. A controller may call
a service either for one of the named synchronous-persistence sites in
`cross-scenario-service-layer.md` or for a cohesive side-effect
operation like `PriceWarmupService`'s enqueue/dedup. The persistence
permission itself is still limited to those named sites — a warmup
service writes no records.

## Testing

RSpec mechanics (spec level, `FactoryBot`, `Sidekiq::Testing.fake!`,
stubbing) are governed by `agent/styleguides/rspec-conventions.md` and
`agent/adr/fetcher/rspec-testing-strategy.md`. Beyond those:

- A service is a unit spec under `spec/services/`, no `type:` metadata.
- Assert on the **result outcome**, not only on side effects: check
  `result.success?`/`skipped?`/`failed?` and `result.data`/`result.error`
  alongside the persisted state.
- Every `Skipped` branch (the unmet-precondition case) needs its own
  example — it is the outcome most likely to regress silently.

## Canonical Implementations

- `app_fetcher/app/services/user_inventory_sync_service.rb` —
  `Ok`/`Failed` (a real external-failure branch).
- `app_fetcher/app/services/inventory_value_recording_service.rb` —
  `Ok`/`Skipped` (a precondition-gated write).
- `app_fetcher/app/services/price_update_service.rb` — `Ok` only; no
  failure/mutation-only shape any more. Also the canonical
  **single-Scenario SRP extraction**: one caller (`PriceUpdateWorker`),
  extracted to keep `perform` as orchestration glue.
- `app_fetcher/app/services/price_warmup_service.rb` —
  `PriceWarmupService` — the canonical controller-called side-effect
  service: nil-price filter, 20-item cap, 90-second `Rails.cache`
  dedup, and `PriceUpdateWorker.perform_async`, returning
  `ServiceResult[T::Array[Integer]]` with the enqueued item ids.
- `app_fetcher/app/services/service_result.rb` — the shared result type.

## Related ADR

- `agent/adr/fetcher/service-result-contract.md`
- `agent/adr/fetcher/cross-scenario-service-layer.md`
