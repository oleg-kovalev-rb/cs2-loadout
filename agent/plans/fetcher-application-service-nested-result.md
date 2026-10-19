---
status: implemented
app: fetcher
goal: Nest the shared result value object as ApplicationService::Result inside application_service.rb, remove the top-level ServiceResult, and update references
created: 2026-10-20
---

# Development Plan

## Goal

Collapse the two top-level objects of the services layer's shared
machinery into one file: define the result struct as
`ApplicationService::Result` inside
`app_fetcher/app/services/application_service.rb`, and remove the
top-level `ServiceResult` / `app/services/service_result.rb`.

## Expected Behavior

- `application_service.rb` defines both:
  - `ApplicationService` with the private `success`/`failure`/`skipped`
    helpers; and
  - nested `ApplicationService::Result < T::Struct` with the existing
    `Payload` type member (covariant), `Status` enum
    (`Ok`/`Skipped`/`Failed`), `data`, `error`, and predicates.
- Every service `.call` sig returns
  `ApplicationService::Result[<Payload>]`; no `ServiceResult` constant
  remains anywhere in application code.
- The base helpers build `Result[...]` and keep exactly the current
  behavior and typing (`success` generic, `failure`/`skipped` return
  `Result[T.noreturn]`).
- `service_result.rb` and `spec/services/service_result_spec.rb` are
  removed; the value-object spec moves to
  `spec/services/application_service/result_spec.rb` and describes
  `ApplicationService::Result`.
- No behavior change at any call site: same statuses, payloads, error
  strings, predicates, and worker/controller branching.
- Zeitwerk resolves `ApplicationService::Result` from the parent file;
  no `app/services/application_service/` directory is created.

## Scope

### In Scope

- Move the result struct into `application_service.rb` as a nested
  constant.
- Update the four services' return sigs to
  `ApplicationService::Result[...]`.
- Delete `app/services/service_result.rb`.
- Move/rename the result spec and update its references.
- Update current styleguides/ADRs that name `ServiceResult`
  (`fetcher/services.md`, `fetcher/architecture-layers.md`,
  `ruby-sorbet.md`, `fetcher/service-result-contract.md`,
  `fetcher/cross-scenario-service-layer.md`).

### Out of Scope

- Changing `Result`'s shape, statuses, predicates, or covariance.
- Changing helper names or helper behavior.
- Rewriting historical plan files that mention `ServiceResult`; they are
  records of past work.
- Renaming `ApplicationService` or adding any other shared behavior.
- Creating an `app/services/application_service/` folder.

## Implementation Approach

- In `application_service.rb`, define `class Result < T::Struct` first
  (nested under `ApplicationService`), then the `class << self` helper
  block. Inside the base, `Result[...]` resolves lexically.
- In concrete services, use the fully qualified
  `ApplicationService::Result[...]` in `.call` sigs: Sorbet does not
  resolve an unqualified nested constant through the superclass chain
  (verified in the container). Runtime resolution works either way.
- Delete `service_result.rb`; do not leave an alias, since there are no
  external consumers and the point is a single shared object.
- Move the spec to `spec/services/application_service/result_spec.rb`
  (mirrors the nested constant), keeping the existing three predicate
  examples; update `ServiceResult::Status` to
  `ApplicationService::Result::Status`.
- Update docs to use `ApplicationService::Result`; the ADR gets a short
  note in its existing 2026-10-20 amendment rather than rewriting
  history.

## Files To Modify

- `app_fetcher/app/services/application_service.rb` — add nested
  `Result`, switch helpers to it.
- `app_fetcher/app/services/price_update_service.rb` — return sig to
  `ApplicationService::Result[Item]`.
- `app_fetcher/app/services/price_warmup_service.rb` — return sig to
  `ApplicationService::Result[T::Array[Integer]]`.
- `app_fetcher/app/services/inventory_value_recording_service.rb` —
  return sigs to `ApplicationService::Result[InventoryValueLog]`.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — return sig
  to `ApplicationService::Result[T::Array[Item]]`.
- `app_fetcher/spec/services/price_update_service_spec.rb` — example
  description only.
- `agent/styleguides/fetcher/services.md` — replace `ServiceResult` with
  `ApplicationService::Result`; state it lives inside
  `application_service.rb`.
- `agent/styleguides/fetcher/architecture-layers.md` — same rename in the
  layer description and canonical implementations.
- `agent/styleguides/ruby-sorbet.md` — same rename in the `T.untyped`
  exception.
- `agent/adr/fetcher/service-result-contract.md` — same rename plus a
  nesting note in the 2026-10-20 amendment.
- `agent/adr/fetcher/cross-scenario-service-layer.md` — same rename in
  its references to the current contract.

## Files To Create

- `app_fetcher/spec/services/application_service/result_spec.rb` —
  moved/renamed value-object spec.

## Files To Delete

- `app_fetcher/app/services/service_result.rb`
- `app_fetcher/spec/services/service_result_spec.rb`

## Test Plan

- Move the existing `ServiceResult` predicate examples unchanged to
  `spec/services/application_service/result_spec.rb`, describing
  `ApplicationService::Result`.
- Existing `spec/services/application_service_spec.rb` stays as-is; its
  helper tests exercise the nested `Result` through the base.
- All four service specs stay behaviorally unchanged; they are the
  regression net.
- Run the full `app_fetcher` suite, `srb tc`, RuboCop, and
  `zeitwerk:check`.

## Implementation Steps

1. Add the nested `Result` to `application_service.rb`; switch the
   helpers to `Result[...]`.
2. Update the four service return sigs to
   `ApplicationService::Result[...]`.
3. Move/rename the result spec; update its constant references.
4. Delete `service_result.rb` and the old spec file.
5. Run targeted service specs, full suite, `srb tc`, RuboCop, and
   `zeitwerk:check`.
6. Update the styleguides/ADRs.
7. Set this plan to `implemented` and append an implementation summary.

## Verification

Inside the `app_fetcher` container:

- `bundle exec rspec spec/services` and then `bundle exec rspec`.
- `bundle exec srb tc` — confirms nested constant resolution and the
  fully qualified service sigs.
- `bin/rubocop`.
- `bin/rails zeitwerk:check` — confirms the inline nested constant is
  autoloaded from the parent file with no `application_service/`
  directory.

## Risks

- **Sorbet constant resolution.** Unqualified `Result` in a subclass sig
  does not resolve through inheritance; every service sig must use
  `ApplicationService::Result[...]`. This was verified experimentally.
- **Zeitwerk.** Defining `ApplicationService::Result` inline is correct
  as long as no `app/services/application_service/` directory exists;
  the directory would make Zeitwerk expect a file per nested constant.
- **Spec path.** The source is one file but the class is nested; the
  spec mirrors the nested constant path, consistent with
  `Steam::Response::Data::*`.
- **Historical docs.** Old plan files still mention `ServiceResult` by
  design; don't rewrite them. Only current guides/ADRs are updated.
- **`T.noreturn`/covariance behavior** is unchanged; no new typing risk.

## Applicable Styleguides

- `agent/styleguides/fetcher/services.md` — layer structure, base
  helpers, result contract, and construction rules.
- `agent/styleguides/fetcher/architecture-layers.md` — layer map and
  canonical implementations.
- `agent/styleguides/ruby-sorbet.md` — nested constants, `sig`s,
  covariance, and the `T.untyped` exception.
- `agent/styleguides/rspec-conventions.md` — unit-spec path/shape for the
  moved result spec.
- `agent/styleguides/git-commits.md` — eventual `[Fetcher]` commit scope.

## Completion Criteria

- `ServiceResult` no longer exists in application code or current docs.
- `ApplicationService::Result` is defined inside
  `application_service.rb`, and all services return
  `ApplicationService::Result[...]`.
- The moved result spec and all service specs pass; full suite, `srb tc`,
  RuboCop, and `zeitwerk:check` are green.
- Current guides/ADRs refer to `ApplicationService::Result`; historical
  plans are untouched.

# Implementation Summary

## Implemented

- Moved the value object into
  `app_fetcher/app/services/application_service.rb` as
  `ApplicationService::Result < T::Struct`, keeping the covariant
  `Payload`, `Status` enum, `data`/`error`, and predicates unchanged.
- The base helpers now build `Result[...]`; `success` stays generic and
  `failure`/`skipped` still return `Result[T.noreturn]`.
- Deleted `app_fetcher/app/services/service_result.rb`; there is no
  top-level `ServiceResult` constant or alias in application code.
- Updated all four services' `.call` sigs to the fully qualified
  `ApplicationService::Result[...]` (Sorbet does not resolve the nested
  constant unqualified through inheritance).
- Moved the value-object spec from
  `spec/services/service_result_spec.rb` to
  `spec/services/application_service/result_spec.rb`, describing
  `ApplicationService::Result` and using `described_class::Status`.
- Updated `agent/styleguides/fetcher/services.md`,
  `agent/styleguides/fetcher/architecture-layers.md`,
  `agent/styleguides/ruby-sorbet.md`,
  `agent/adr/fetcher/service-result-contract.md`, and
  `agent/adr/fetcher/cross-scenario-service-layer.md` to reference
  `ApplicationService::Result`; the ADR amendment records the nesting.
- Historical plan files that mention `ServiceResult` were left untouched.

## Tests

- Moved spec was written first and failed with
  `uninitialized constant ApplicationService::Result` (RED), then went
  green after the nested class was added.
- Commands executed in the `app_fetcher` container:
  - `bundle exec rspec spec/services` → 38 examples, 0 failures.
  - `bundle exec rspec` (full suite) → 500 examples, 0 failures.
  - `bundle exec srb tc` → no errors.
  - `bin/rubocop` → 178 files inspected, no offenses.
  - `bin/rails zeitwerk:check` → "All is good!"

## Verification

All checks passed. Zeitwerk confirms the nested `ApplicationService::Result`
is autoloaded from the parent file with no
`app/services/application_service/` directory. `srb tc` confirms the
fully qualified service sigs and the covariant helper typing.

## Deviations

None.

## Remaining Issues

None.

## Follow-up

The status enum members were renamed from `Ok`/`Skipped`/`Failed` to
`Success`/`Skipped`/`Failure` (string values `"success"`/`"skipped"`/
`"failure"`), with the result spec and current guides/ADRs updated.
Nothing serializes or persists the string values; call sites only use
the `success?`/`skipped?`/`failed?` predicates.
