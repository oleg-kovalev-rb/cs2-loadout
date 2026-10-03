---
status: implemented
app: fetcher
goal: Unify app_fetcher's app/services/ call convention under class-method `.call` and remove PriceUpdateService's dead Result wrapper
created: 2026-10-03
---

# Development Plan

## Goal

Clean up two concrete inconsistencies in `app_fetcher/app/services/`
surfaced during review: a mixed class-method/instance-method call
convention across the three services, and a `Result` wrapper on
`PriceUpdateService` whose `success`/`error` fields can never actually be
false/present. Both were discussed and scoped down from a broader
"introduce a shared base-service + Result abstraction" idea, which was
explicitly deferred (see `.claude/plans/` session notes / project memory)
until `app/services/` has more members and a real shared shape emerges.

## Expected Behavior

- `InventoryValueRecordingService` is invoked identically everywhere as
  `InventoryValueRecordingService.call(steam_id)` — no more
  `.new(steam_id).call!`. Its behavior (upsert today's
  `InventoryValueLog` row for a `steam_id`, summing current item prices,
  returning that `InventoryValueLog`) is unchanged.
- `PriceUpdateService.call(item, price_data)` still builds and persists a
  `PriceLog`, still updates `item.current_price_cents`/
  `item.change_24h_cents` in the same transaction, but returns nothing
  (`void`). Callers read the result off the same `item` object they
  passed in (already mutated in place by `item.update!`), not off a
  returned `Result`.
- `UserInventorySyncService` and its `Result` are completely unchanged —
  out of scope.
- No behavior change for end users/API consumers: the JSON responses
  from `Api::V1::InventoryValuesController` and the stream payload
  published by `PriceUpdateWorker` are byte-identical to today's.

## Scope

### In Scope

- `app_fetcher/app/services/inventory_value_recording_service.rb` —
  convert to class-method `.call`.
- `app_fetcher/app/workers/inventory_value_update_worker.rb` — update
  call site.
- `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb` —
  update call site.
- `app_fetcher/spec/services/inventory_value_recording_service_spec.rb`
  — update to the new call shape.
- `app_fetcher/app/services/price_update_service.rb` — remove `Result`,
  change sig to `.void`.
- `app_fetcher/app/workers/price_update_worker.rb` — read `item`'s
  mutated attributes instead of a returned `Result`.
- `app_fetcher/spec/services/price_update_service_spec.rb` — update
  assertions to not reference a returned `Result`.
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — verify still
  passes; update only if it referenced `PriceUpdateService`'s return
  value directly (currently it does not — it asserts via `item.reload`
  and the stream, so expected to need no change, but confirm during
  implementation).
- `.claude/adr/fetcher/cross-scenario-service-layer.md` — amend the
  paragraph that currently blesses both call shapes as equally valid, to
  state `.call` (class-method) is the mandated convention for this layer.
- `.claude/styleguides/fetcher/architecture-layers.md` — amend the
  Canonical Implementations bullet describing
  `InventoryValueRecordingService`'s instance-method shape as "both
  valid," and the bullet/diagram describing `PriceUpdateService`'s return
  value if it mentions `Result`.

### Out of Scope

- Any shared base-service class or generic `Result` abstraction — tried
  and explicitly deferred this session (see project memory
  `project_base_service_abstraction_deferred.md`): only 2-3 services
  exist, their `Result` shapes don't overlap beyond `success`/`error`,
  and the cross-scenario-service-layer ADR already argues against adding
  new layers ahead of a proven repeated need.
- Renaming `app/services/` to `app/actions/` — ADR already explicitly
  rejected this ("Alternative: a general-purpose `app/actions/` layer...
  Rejected as too broad").
- Namespacing any service under `Steam::` — ADR already explicitly
  rejected this too, for parity with how workers/schedulers stay flat
  despite calling `Steam::Client`.
- `UserInventorySyncService` and its `Result` — has a real, tested
  failure branch (Steam fetch failure) consumed differently by its two
  callers (`InventoriesController` renders 400; `UserInventorySyncWorker`
  logs and deliberately does not raise/retry). Converting this to
  exceptions was considered and rejected: it would contradict
  `steam-response-objects.md`'s explicit "never an exception" convention
  for Steam failures, and `rescue_from` cannot help the Sidekiq-worker
  call site at all, breaking the ADR's "called identically from both
  Scenarios" guarantee.
- Where `UserInventorySyncService`'s `response.success?` check "belongs"
  — investigated and found to be the established, consistent convention
  used by every `Steam::Client` caller in the app (e.g.
  `PriceUpdateWorker` does the identical check). Not a deviation, no
  change needed.

## Implementation Approach

Both changes are mechanical, behavior-preserving refactors of existing
classes — no new abstractions, no new files.

**`InventoryValueRecordingService`**: move its single instance method
into a `class << self` block, same pattern already used by
`PriceUpdateService`/`UserInventorySyncService` in this same directory.
`@steam_id` ivar becomes a local/parameter; everything else in the method
body (the `UserInventory.find_by` lookup, the sum, the `upsert_all`, the
final `find_by!`) is unchanged.

**`PriceUpdateService`**: delete the `Result < T::Struct` class and
change `.call`'s sig from `returns(PriceUpdateService::Result)` to
`.void`. The method body keeps building `price_log`, computing
`change_24h_cents`, and doing the transactional save/update — it simply
stops constructing/returning a `Result` at the end. `PriceUpdateWorker`
already holds a reference to the same `item` instance it passed in;
because `item.update!(current_price_cents:, change_24h_cents:)` mutates
the receiver's in-memory attributes (not just the DB row), `item
.current_price_cents` and `item.change_24h_cents` are correct and
available on that same object immediately after `PriceUpdateService.call`
returns — no extra query or data needs to flow back through a return
value.

## Files To Modify

- `app_fetcher/app/services/inventory_value_recording_service.rb` —
  convert `initialize`/`call!` instance-method pair to a `class << self`
  block exposing `self.call(steam_id)`, same return type
  (`InventoryValueLog`).
- `app_fetcher/app/workers/inventory_value_update_worker.rb:11` —
  `InventoryValueRecordingService.new(steam_id).call!` →
  `InventoryValueRecordingService.call(steam_id)`.
- `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb:25`
  — same change as above.
- `app_fetcher/app/services/price_update_service.rb` — delete the
  `Result` class; change the `.call` sig to `.void`; remove the final
  `Result.new(...)` construction (method just ends after the
  transaction).
- `app_fetcher/app/workers/price_update_worker.rb:22-24` — drop `result
  = `; call `PriceUpdateService.call(item, T.must(response.data))` as a
  bare statement; change `publish_to_stream` args from
  `result.price_log.lowest_price_cents, result.change_24h_cents` to
  `item.current_price_cents, item.change_24h_cents`.
- `.claude/adr/fetcher/cross-scenario-service-layer.md` — update the
  sentence in the Decision section that currently reads "...an instance
  method is just as valid a shape for a class in this layer; pick
  whichever reads better for the specific service, there's no single
  mandated call convention" to instead state the class-method `.call`
  shape is the mandated convention, and note
  `InventoryValueRecordingService` now follows it too (historical/context
  framing, not rewriting history — keep the Alternatives/Consequences
  sections intact, only correct the now-superseded convention statement).
- `.claude/styleguides/fetcher/architecture-layers.md` — update the
  Canonical Implementations bullet for `InventoryValueRecordingService`
  to no longer describe the instance-method shape as current/valid; note
  it now uses `.call` like the other two services. Check the `Services`
  "Structure" prose and the Scenario interaction diagrams for any other
  reference to `InventoryValueRecordingService`'s old call shape or to
  `PriceUpdateService`'s `Result` and correct those too.

## Files To Create

None.

## Test Plan

- `app_fetcher/spec/services/inventory_value_recording_service_spec.rb`
  — change `subject(:record) { described_class.new(steam_id).call! }` to
  `subject(:record) { described_class.call(steam_id) }`. All four
  existing contexts (priced items, zero-price item, no `UserInventory`
  row, existing log row gets updated in place) keep asserting the same
  behavior unchanged.
- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb` — no
  assertions reference the service's return value or call shape directly
  (worker discards it); expected to need no change, confirm it still
  passes.
- `app_fetcher/spec/services/price_update_service_spec.rb` — both
  examples currently assert on `result.success`, `result.price_log`,
  `result.item`, `result.change_24h_cents`. Rewrite to call
  `described_class.call(item, price_data)` without capturing a return
  value, then assert via `item.reload`/`item.price_logs.last` instead of
  `result.*` (e.g. `item.price_logs.last.lowest_price_cents`,
  `item.current_price_cents`, `item.change_24h_cents`) — the
  `item.current_price_cents`/`item.change_24h_cents` assertions already
  present in both examples stay as-is.
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — asserts
  entirely via `item.reload` and `prices_stream_entries`, never touches
  `PriceUpdateService`'s return value; expected to need no change,
  confirm it still passes after `price_update_worker.rb`'s edit.

## Implementation Steps

1. Convert `InventoryValueRecordingService` to the class-method `.call`
   shape.
2. Update its two call sites
   (`inventory_value_update_worker.rb`,
   `inventory_values_controller.rb`).
3. Update `inventory_value_recording_service_spec.rb` to the new call
   shape; run it (and `inventory_value_update_worker_spec.rb`) to confirm
   green.
4. Remove `PriceUpdateService::Result`; change the sig to `.void`.
5. Update `price_update_worker.rb` to read `item`'s mutated attributes
   instead of a returned `Result`.
6. Update `price_update_service_spec.rb`'s assertions; run it (and
   `price_update_worker_spec.rb`) to confirm green.
7. Amend `cross-scenario-service-layer.md` and
   `architecture-layers.md` to reflect the now-mandated `.call`
   convention and `PriceUpdateService`'s `void` return.
8. Run the full `app_fetcher` test suite and `srb tc` (Sorbet type
   check) to catch any other reference to the removed `Result` class or
   the old call shape.

## Verification

- `bundle exec rspec spec/services/inventory_value_recording_service_spec.rb spec/workers/inventory_value_update_worker_spec.rb spec/services/price_update_service_spec.rb spec/workers/price_update_worker_spec.rb`
  (app_fetcher) — targeted re-run.
- `bundle exec rspec` (app_fetcher) — full suite, to catch any other
  caller of either service not yet identified.
- `bundle exec srb tc` (app_fetcher) — Sorbet type check, since both
  changes alter public method signatures (`.void` return,
  `self.call` vs instance method) that Sorbet enforces at call sites.

## Risks

- `grep -rn "PriceUpdateService::Result\|InventoryValueRecordingService.new"`
  should be run across `app_fetcher` before editing, in case there's a
  third call site (e.g. a console script, rake task, or another spec)
  not surfaced by this session's research.
- Sorbet's `sig` on `PriceUpdateService.call` is checked at every call
  site — if any other caller besides `PriceUpdateWorker` exists and
  relies on the returned `Result`, Sorbet type-checking (or a runtime
  `NoMethodError` on `nil`) will surface it immediately during step 8.

## Assumptions

- No other caller of `PriceUpdateService.call` or
  `InventoryValueRecordingService` exists beyond the files identified in
  this session (workers, controllers, their specs) — to be confirmed by
  the repo-wide grep in Risks before implementation.

## Applicable Styleguides

- `.claude/styleguides/fetcher/architecture-layers.md` — defines the
  `app/services/` layer's call-convention statement this plan updates
  (Canonical Implementations bullet for `InventoryValueRecordingService`)
  and the layer's dependency/responsibility rules both edited classes
  must keep satisfying.
- `.claude/adr/fetcher/cross-scenario-service-layer.md` — the Decision
  section's "no single mandated call convention" sentence this plan
  supersedes; governs what counts as in/out of scope for this layer
  (confirms the `app/actions/`-rename and `Steam::`-namespacing
  alternatives were already considered and rejected, so neither
  reappears here).
- `.claude/styleguides/ruby-sorbet.md` — constrains the `class << self;
  extend T::Sig; ...; end` shape `InventoryValueRecordingService` moves
  to (already the pattern `PriceUpdateService`/`UserInventorySyncService`
  use) and the `.void` sig on `PriceUpdateService.call` after `Result` is
  removed.
- `.claude/styleguides/fetcher/background-jobs.md` — constrains
  `PriceUpdateWorker`'s edit: `perform` must stay orchestration-only, the
  existing `Item.transaction` boundary (inside `PriceUpdateService`) is
  unchanged, and the worker still guards on a missing `item` before
  calling the service.
- `.claude/styleguides/rspec-conventions.md` — constrains how the four
  touched spec files get updated: unit-level, `subject`-named action,
  `let`/`let!` for test data, `aggregate_failures` for >3 expectations —
  all four specs already follow this and must continue to after the
  edits.
- `.claude/styleguides/git-commits.md` — the eventual commit(s) for this
  work are `[Fetcher]` scope (code + spec changes) and, if the
  ADR/styleguide text edits land in the same commit as the code per this
  file's "Task-Scoped Styleguides" rule (they're amendments needed by
  this specific plan, not a standalone process change), still `[Fetcher]`
  rather than `[AI WorkFlow]`.

## Completion Criteria

- `InventoryValueRecordingService` is called as `.call(steam_id)`
  everywhere, no `.new(...).call!` call sites remain.
- `PriceUpdateService::Result` no longer exists; `PriceUpdateService.call`
  returns `void`; `PriceUpdateWorker` reads price/change data off `item`
  directly.
- `cross-scenario-service-layer.md` and `architecture-layers.md` reflect
  the new mandated call convention.
- Full `app_fetcher` RSpec suite and `srb tc` pass.

# Implementation Summary

## Implemented

- `InventoryValueRecordingService` converted from an instance-method
  shape (`.new(steam_id).call!`) to class-method `.call(steam_id)`,
  matching `PriceUpdateService`/`UserInventorySyncService`. Both call
  sites updated: `InventoryValueUpdateWorker#perform` and
  `InventoryValuesController#index`'s cold-start seed.
- `PriceUpdateService::Result` removed entirely — its `success`/`error`
  fields were unreachable (the method's only writes are `save!`/
  `update!`, which raise rather than returning a false result). `.call`'s
  sig changed to `.void`. `PriceUpdateWorker` now reads
  `item.current_price_cents`/`item.change_24h_cents` directly off the
  same `Item` instance it passed in (mutated in place by `item.update!`
  inside the service) instead of off a returned `Result`.
- `UserInventorySyncService` and its `Result` left untouched, per scope —
  added a one-line comment marking the per-service `Result` duplication
  as a deliberately deferred decision (see project memory
  `project_base_service_abstraction_deferred.md`).
- `.claude/adr/fetcher/cross-scenario-service-layer.md` and
  `.claude/styleguides/fetcher/architecture-layers.md` updated: the
  "no single mandated call convention" language replaced with the
  class-method `.call` mandate; `architecture-layers.md`'s Canonical
  Implementations entries updated for both services' new shapes.

## Tests

- `app_fetcher/spec/services/inventory_value_recording_service_spec.rb`
  — `subject` changed to `described_class.call(steam_id)`; all four
  existing examples unchanged otherwise.
- `app_fetcher/spec/services/price_update_service_spec.rb` — both
  examples rewritten to assert via `item.reload`/`item.price_logs.last`
  instead of a returned `Result`.
- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb`,
  `app_fetcher/spec/workers/price_update_worker_spec.rb`,
  `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb` — no
  changes needed; confirmed still passing.

Commands executed (inside the running `app_fetcher` Docker container —
the host's local Ruby 3.3.0 can't load the app at all, pre-existing
`connection_pool` gem/Ruby mismatch unrelated to this change):

- `docker compose exec -T app_fetcher bundle exec rspec spec/services/inventory_value_recording_service_spec.rb spec/workers/inventory_value_update_worker_spec.rb spec/services/price_update_service_spec.rb spec/workers/price_update_worker_spec.rb spec/requests/api/v1/inventory_values_spec.rb` → 25 examples, 0 failures.
- `docker compose exec -T app_fetcher bundle exec rspec` (full suite) →
  127 examples, 1 failure — pre-existing, unrelated
  (`spec/caching/user_inventory_cache_spec.rb:18`, confirmed failing
  identically on a clean checkout via `git stash`).
- `docker compose exec -T app_fetcher bundle exec srb tc` → 97
  pre-existing errors (98 on a clean checkout), none in the touched
  files beyond the same pre-existing classes of error already present
  elsewhere in the codebase (missing Sidekiq/ActiveRecord-attribute RBIs)
  — confirmed via `git stash` diff of `srb tc` output.
- `docker compose exec -T app_fetcher bundle exec rubocop <touched files>`
  → 6 pre-existing offenses, all in `price_update_worker.rb` lines not
  touched by this change (`Layout/SpaceInsideArrayLiteralBrackets` in
  `update_related_cache`, unrelated to this plan's scope).

## Verification

All targeted and full-suite RSpec runs green except the one confirmed
pre-existing, unrelated failure. `srb tc` and `rubocop` show no new
issues introduced by this change — only pre-existing gaps confirmed via
before/after comparison on a clean checkout.

## Deviations

None from the plan as styleguide-checked.

## Remaining Issues

- Local host Ruby (3.3.0) can't run `app_fetcher`'s test suite at all
  (`connection_pool` gem syntax error) — pre-existing, unrelated to this
  change, environment-level; the project's Docker container (pinned to
  Ruby 3.3.6) runs fine. Not addressed here — out of scope.
- `spec/caching/user_inventory_cache_spec.rb:18` fails on a clean
  checkout already — pre-existing, unrelated, not addressed here.
- `srb tc`'s ~97 pre-existing errors (missing Sidekiq/ActiveRecord
  attribute RBIs) are unrelated to this change and not addressed here.
