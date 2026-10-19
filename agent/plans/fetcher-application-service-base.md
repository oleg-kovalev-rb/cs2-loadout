---
status: implemented
app: fetcher
goal: Add a shared ApplicationService base that supplies private success/failure/skipped result helpers, and migrate all four app_fetcher services to it
created: 2026-10-20
---

# Development Plan

## Goal

Remove the repeated
`ServiceResult[Payload].new(status: ServiceResult::Status::X, data: ..., error: ...)`
construction from `app_fetcher/app/services/` by introducing a shared
`ApplicationService` base class. Concrete services inherit it and build
results with terse, fully typed helpers:

```ruby
success(log)
failure(T.must(response.error))
skipped
```

## Expected Behavior

- `app_fetcher/app/services/application_service.rb` defines a top-level
  `ApplicationService` with three private class helpers:
  - `success(data)` → `ServiceResult` with `Ok` status, the payload, and
    `error: nil`;
  - `failure(error)` → `ServiceResult` with `Failed` status, `data: nil`,
    and the given non-nil error;
  - `skipped` → `ServiceResult` with `Skipped` status and both `data` and
    `error` nil.
- All four services
  (`InventoryValueRecordingService`, `PriceUpdateService`,
  `PriceWarmupService`, `UserInventorySyncService`) inherit from
  `ApplicationService` and use these helpers instead of constructing
  `ServiceResult` directly.
- `ServiceResult` keeps the same `T::Struct`, the same
  `Ok`/`Skipped`/`Failed` enum, the same predicates, and the same file
  (`service_result.rb`). Its `Payload` type member becomes covariant
  (`type_member(:out)`).
- Every service still exposes exactly one public class method, `.call`;
  the helpers are private inherited class methods, not public API.
- Behavior at every call site is unchanged: same statuses, same payloads,
  same error strings, same persisted records, same worker/controller
  branching.
- `srb tc` still rejects a mismatched payload passed to `success`:
  `success` is generic over its payload and infers it from its argument.
  `failure`/`skipped` carry no payload and return
  `ServiceResult[T.noreturn]`; covariance makes that a subtype of every
  concrete `ServiceResult[Payload]`, so no per-service payload
  declaration is needed.

## Scope

### In Scope

- New `app_fetcher/app/services/application_service.rb`.
- Migrate the four existing services to inherit it and use
  `success`/`failure`/`skipped`.
- Remove `InventoryValueRecordingService`'s local private `skipped`
  method, now supplied by the base.
- Make `ServiceResult`'s `Payload` covariant (`type_member(:out)`).
- New unit spec for the base helpers.
- Update `agent/styleguides/fetcher/services.md`, which currently states
  "no shared base class" and documents direct `ServiceResult[...].new`
  construction.
- Update `agent/styleguides/fetcher/architecture-layers.md`'s Services
  section/canonical implementations.
- Add the `T.untyped`-at-generic-result-construction exception to
  `agent/styleguides/ruby-sorbet.md`.
- Add an amendment to `agent/adr/fetcher/service-result-contract.md`
  documenting the construction-idiom and variance change without
  rewriting the contract.

### Out of Scope

- Moving `ServiceResult` into `application_service.rb`. Zeitwerk expects
  `application_service.rb` to define `ApplicationService`; a file may not
  cleanly define a second unrelated top-level constant. `ServiceResult`
  also stays a distinct value object per the existing ADR.
- Changing `ServiceResult`'s shape, statuses, or predicates beyond the
  covariant `Payload`.
- Renaming the `base.rb` concept to a top-level `Base` class.
- Splitting `ServiceResult` into a `Success`/`Failure`/`Skipped` union
  (considered and rejected: three classes, duplicated predicates, and a
  larger contract rewrite for the same terse helper API).
- Changing service call sites in workers/controllers, their specs, or any
  API/stream payload.
- Applying the base class to `app_core`'s `app/actions/` layer (a
  different layer, with its own ADR).
- Adding any other shared service behavior beyond result construction.

## Implementation Approach

### Base class shape

`ServiceResult::Payload` becomes covariant (`type_member(:out)`). The
value object is immutable (`const :data`), so covariance is sound and
lets a payload-less result stand in for any concrete
`ServiceResult[Payload]`.

`ApplicationService` is a normal (non-`T::Struct`) class with
`extend T::Sig`; it does not need `extend T::Generic` and has no
`Payload` declaration. The three helpers are private class methods inside
`class << self`:

- `success(data)` uses a method-level generic
  (`type_parameters(:Payload)` / `T.type_parameter(:Payload)`) so the
  payload is inferred from the argument and checked against the caller's
  return type.
- `failure(error)` and `skipped` return `ServiceResult[T.noreturn]`;
  covariance makes them assignable wherever a concrete
  `ServiceResult[Payload]` is expected.
- All three construct `ServiceResult[T.untyped]` internally. Naming the
  real type parameter in the method body would call `T.type_parameter`
  outside a `sig` and raise at runtime. The helper `sig` carries the
  real type; this is the sanctioned `T.untyped` exception documented in
  `ruby-sorbet.md`.

This was verified experimentally in the running `app_fetcher` container
with a temporary probe file (then removed): `srb tc` catches a
wrong-typed `success` argument, `failure`/`skipped` satisfy a
`ServiceResult[Integer]` return, and all three work at runtime.

### Migrations

- `PriceUpdateService` → final line becomes `success(item)`.
- `PriceWarmupService` → final construction becomes
  `success(enqueued_ids)`.
- `InventoryValueRecordingService` → final construction becomes
  `success(log)`; delete the local private `skipped` method (`return
  skipped` calls now resolve to the inherited helper).
- `UserInventorySyncService` → failure branch becomes
  `return failure(T.must(response.error))` and the final construction
  becomes `success(all_items)`.

`Steam::Response#error` is typed `T.nilable(String)`, while the helper
takes a non-nil `String` (matching the ADR invariant that a `Failed`
result always carries an error). Every failure path in
`Steam::Client#perform_request` sets a non-nil error, so `T.must` is safe
and keeps the invariant explicit.

### Documentation

- `services.md`: replace "no shared base class" with the
  `ApplicationService` inheritance rule; change the construction rule
  from `ServiceResult[Payload].new(...)` to the inherited helpers;
  document covariance, generic `success`, `T.noreturn` for
  `failure`/`skipped`, and the absence of a per-service payload
  declaration; add MUST/MUST NOT wording that direct
  `ServiceResult[...].new` is confined to the base/value-object specs;
  add `application_service.rb` to Canonical Implementations.
- `architecture-layers.md`: note inheritance from `ApplicationService` in
  the Services structure/canonical-implementation entries.
- `ruby-sorbet.md`: add the exception for `T.untyped` at generic result
  construction inside `ApplicationService`.
- `service-result-contract.md`: add a dated amendment recording the
  helper-based construction and covariant payload, with the rest of the
  contract unchanged.
- `fix_me.md`: check the touched files for existing entries (none found
  during research); no entry needs adding.

## Files To Modify

- `app_fetcher/app/services/service_result.rb` — change `Payload` to
  `type_member(:out)`; no other change.
- `app_fetcher/app/services/inventory_value_recording_service.rb` — add
  `< ApplicationService`, use `success(log)`, remove the local `skipped`
  helper.
- `app_fetcher/app/services/price_update_service.rb` — add
  `< ApplicationService`, use `success(item)`.
- `app_fetcher/app/services/price_warmup_service.rb` — add
  `< ApplicationService`, use `success(enqueued_ids)`.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — add
  `< ApplicationService`, use `failure(T.must(response.error))` and
  `success(all_items)`.
- `agent/styleguides/fetcher/services.md` — update structure, interface,
  MUST/MUST NOT rules, and canonical implementations as described above.
- `agent/styleguides/fetcher/architecture-layers.md` — mention the base
  class in the Services section and canonical implementations.
- `agent/styleguides/ruby-sorbet.md` — add the `T.untyped` generic-result
  construction exception.
- `agent/adr/fetcher/service-result-contract.md` — append the dated
  amendment about construction and variance.

## Files To Create

- `app_fetcher/app/services/application_service.rb` — shared base class
  owning only the private `success`/`failure`/`skipped` constructors.
- `app_fetcher/spec/services/application_service_spec.rb` — unit spec
  covering the three helper-to-status mappings.

## Test Plan

- New `spec/services/application_service_spec.rb`:
  - `success(payload)` yields `Ok`, `data == payload`, `error` nil.
  - `failure("boom")` yields `Failed`, `data` nil, `error == "boom"`.
  - `skipped` yields `Skipped`, `data` nil, `error` nil.
  - Because the helpers are private, exercise them with
    `described_class.send(:success, payload)` etc.
- Existing `spec/services/service_result_spec.rb` stays unchanged; it
  continues to own the value object's predicate behavior.
- Existing four service specs stay behaviorally unchanged and must keep
  passing. They already assert `success?`/`skipped?`/`failed?` plus
  payload/error, so they are the regression net for the migration.
- No request/worker spec changes expected: call sites and result shapes
  are unchanged.

## Implementation Steps

1. Write `spec/services/application_service_spec.rb` first and run it;
   confirm it fails because `ApplicationService` does not exist.
2. Change `ServiceResult::Payload` to `type_member(:out)`.
3. Create `app_fetcher/app/services/application_service.rb` with the
   generic `success` and payload-less `failure`/`skipped`; run the new
   spec until green.
4. Migrate `PriceUpdateService` (smallest, no failure branch) and run its
   spec.
5. Migrate `PriceWarmupService` and run its spec.
6. Migrate `InventoryValueRecordingService`, including deleting its local
   `skipped` helper, and run its spec.
7. Migrate `UserInventorySyncService`, including
   `failure(T.must(response.error))`, and run its spec.
8. Run the full `app_fetcher` RSpec suite.
9. Run `srb tc`; confirm no new errors and that the service payload types
   still constrain `success`.
10. Run RuboCop on all touched Ruby files.
11. Update the styleguide, architecture guide, Sorbet exception, and ADR
    amendment.
12. Update this plan's status to `implemented` and add an implementation
    summary.

## Verification

Inside the `app_fetcher` Docker container (host Ruby cannot load the app,
per `fetcher-services-cleanup.md`):

- `bundle exec rspec spec/services/application_service_spec.rb
  spec/services/service_result_spec.rb spec/services/*_service_spec.rb`
  — targeted services suite.
- `bundle exec rspec` — full `app_fetcher` suite.
- `bundle exec srb tc` — type check, especially the covariant
  `ServiceResult` payload, `success`'s inferred payload, and
  `failure(T.must(...))`.
- `bundle exec rubocop app/services/application_service.rb
  app/services/inventory_value_recording_service.rb
  app/services/price_update_service.rb
  app/services/price_warmup_service.rb
  app/services/user_inventory_sync_service.rb
  spec/services/application_service_spec.rb`
- `bin/rails zeitwerk:check` (or eager-load in the test environment) to
  confirm `application_service.rb` resolves as `ApplicationService` and
  no file defines multiple unexpected top-level constants.

## Risks

- **Covariance change.** `ServiceResult::Payload` moves from invariant
  to covariant. This is sound because `data` is a read-only `const`, and
  it only widens assignability (`ServiceResult[Item]` can stand in for
  `ServiceResult[Object]`); the reverse is still rejected. No call site
  relies on invariance.
- **`T.untyped` construction inside the base.** Required by runtime
  generic erasure; it is confined to `ApplicationService` and documented
  as a `ruby-sorbet.md` exception. A future helper that needs another
  payload-bearing outcome would have to follow the same pattern rather
  than widening `T.untyped` usage.
- **`T.noreturn` readability.** `failure`/`skipped` returning
  `ServiceResult[T.noreturn]` is precise but unfamiliar; the base class
  comment and `services.md` explain why covariance makes it work.
- **Private helper visibility.** They are inherited and callable with an
  implicit receiver from subclass `.call`; they are not public API. The
  base spec uses `send`, which intentionally bypasses visibility.
- **`T.must(response.error)`** relies on `Steam::Client` always setting an
  error on non-success responses (verified for every branch). If that
  ever becomes nil, the failure path raises instead of returning
  `Failed`; acceptable and consistent with the existing non-nil-error
  invariant.
- **Zeitwerk.** Keeping `ServiceResult` in its own file and naming the
  base `application_service.rb`/`ApplicationService` avoids the
  file-defines-multiple-constants problem.

## Assumptions

- The running `app_fetcher` container (Ruby 3.3.6) remains the execution
  environment for specs/Sorbet/RuboCop, per prior plan precedent.
- No additional service, console script, rake task, or spec constructs
  `ServiceResult` directly beyond the files found by the repo-wide grep
  during research (`service_result_spec.rb` and the four services).

## Applicable Styleguides

- `agent/styleguides/fetcher/services.md` — the layer's structure,
  `ApplicationService` inheritance, private helpers, covariant payload,
  `T.noreturn` outcomes, construction confinement, and service testing
  expectations.
- `agent/styleguides/fetcher/architecture-layers.md` — the layer map and
  canonical implementations; `ApplicationService` placement as the
  layer's only shared base.
- `agent/styleguides/ruby-sorbet.md` — `sig` discipline, `T.must`,
  covariance/type members, `T.untyped` exception for generic result
  construction, and constant wrapping.
- `agent/styleguides/rspec-conventions.md` — unit-spec location/shape,
  named `subject`, `aggregate_failures`, and FactoryBot usage for the new
  base spec.
- `agent/styleguides/git-commits.md` — the eventual commit is `[Fetcher]`
  scope (code + spec + fetcher-scoped docs).

Related ADR (amended, not a styleguide):
`agent/adr/fetcher/service-result-contract.md` — the helper-based
construction and covariant `Payload` amendment.

## Completion Criteria

- `ApplicationService` exists with private `success`/`failure`/`skipped`
  helpers, and all four services inherit it.
- No service constructs `ServiceResult` directly; every result goes
  through the helpers.
- `ServiceResult` keeps its statuses/predicates/file and gains only the
  covariant `Payload` (`type_member(:out)`).
- New base spec and all existing service specs pass; full `app_fetcher`
  suite and `srb tc` are green apart from any already-known unrelated
  failures.
- `services.md`, `architecture-layers.md`, and the
  `service-result-contract.md` amendment reflect the new construction
  idiom and base-class rule.

# Implementation Summary

## Implemented

- Added `app_fetcher/app/services/application_service.rb` with private
  `success(data)`, `failure(error)`, and `skipped` class helpers.
  `success` is generic over its payload; `failure`/`skipped` return
  `ServiceResult[T.noreturn]`. Construction uses
  `ServiceResult[T.untyped]` because runtime generics are erased; the
  helper `sig`s carry the real types.
- Changed `ServiceResult::Payload` from `type_member` to
  `type_member(:out)` so a payload-less result is assignable to any
  concrete `ServiceResult[Payload]`.
- Migrated all four services to `< ApplicationService` and the helpers:
  - `PriceUpdateService` → `success(item)`;
  - `PriceWarmupService` → `success(enqueued_ids)`;
  - `InventoryValueRecordingService` → `success(log)`, with its local
    private `skipped` method removed;
  - `UserInventorySyncService` → `failure(T.must(response.error))` /
    `success(all_items)`.
- No service constructs `ServiceResult[...].new(...)` directly any more;
  that construction lives only in `ApplicationService` and
  `spec/services/service_result_spec.rb`.
- Amended `agent/styleguides/fetcher/services.md`,
  `agent/styleguides/fetcher/architecture-layers.md`,
  `agent/styleguides/ruby-sorbet.md` (new `T.untyped` exception), and
  `agent/adr/fetcher/service-result-contract.md` (2026-10-20 amendment).

## Tests

- Added `app_fetcher/spec/services/application_service_spec.rb`:
  success/skipped/failed mappings plus a check that the helpers are not
  public.
- Existing service/spec files were not changed: their behavior assertions
  already cover the migrated paths.
- Commands executed in the `app_fetcher` container:
  - `bundle exec rspec spec/services/application_service_spec.rb` (RED
    first: `uninitialized constant ApplicationService`), then green.
  - `bundle exec rspec spec/services/application_service_spec.rb
    spec/services/service_result_spec.rb` → 7 examples, 0 failures.
  - Per-service runs for `price_update_service`,
    `price_warmup_service`, `inventory_value_recording_service`, and
    `user_inventory_sync_service` (plus
    `user_inventory_sync_worker_spec` and both inventory request specs) →
    green.
  - `bundle exec rspec` (full suite) → 500 examples, 0 failures.
  - `bundle exec srb tc` → no errors.
  - `bin/rubocop` → 179 files inspected, no offenses.
  - `bin/rails zeitwerk:check` → "All is good!"

## Verification

All targeted and full-suite checks passed. `srb tc` confirms the
covariant payload, `success`'s inferred payload, and
`failure(T.must(...))`; Zeitwerk confirms `application_service.rb`
resolves as `ApplicationService`.

## Deviations

None from the final styleguide-checked plan. Earlier drafts used a
per-service `Payload = type_template { { fixed: ... } }`; after
discussion that was replaced by the covariant `ServiceResult` design
before implementation, and the plan/docs were updated accordingly.

## Remaining Issues

None.

## Follow-up

The result value object was subsequently nested as
`ApplicationService::Result` inside `application_service.rb` (removing
the top-level `ServiceResult`); see
`agent/plans/fetcher-application-service-nested-result.md`.
