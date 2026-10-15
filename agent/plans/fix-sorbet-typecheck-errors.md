---
status: implemented
app: fetcher
goal: Make app_fetcher's `srb tc` pass by fixing the 21 remaining type errors across the query layer, parser, controller, service, worker, and config/lib.
created: 2026-10-15
---

# Development Plan

## Goal

Make `app_fetcher`'s `bundle exec srb tc` pass (currently 21 errors)
without changing runtime behavior, by correcting `sig`s/`T.let`s and
narrowing already-guaranteed non-nil values. `app_core` is already green
and stays untouched.

## Expected Behavior

- `srb tc` reports `No errors!`.
- No runtime behavior change: the existing RSpec suite stays green.
- The typed call sites regain the concrete enum type, so
  `Options::ItemSortOption#apply`, `Options::InventorySortOption#apply`,
  and `PricePeriod#duration` resolve again.
- `app_fetcher`'s `bin/ci` stays the local equivalent of CI.

## Scope

### In Scope

- 21 `srb tc` errors, grouped into 8 root causes:
  1. `Appliers::SortApplier` erases the concrete enum (5).
  2. `Options::ItemFilterField#apply` scope type (4).
  3. `UserInventorySyncService` `response.data` not narrowed (4).
  4. `config/initializers/redis.rb` — empty `ConnectionPool` RBI + missing `T.let` (3).
  5. `PriceUpdateWorker` nilable args (2).
  6. `ItemParser` nilable `item_name` (1).
  7. `ItemPricesController#dynamics` narrowing lost across two calls (1).
  8. `Faraday::UserAgentRotator` undeclared `@app` (1).
- Test/type regression coverage for the generic `SortApplier`.

### Out of Scope

- Repo-wide Sorbet adoption gaps in `app_core` (already green; separately
  logged in `fix_me.md`).
- Fixing `bin/tapioca gem` (currently fails on `solid_cache` needing a
  booted Rails for `cache` config). Only logged, not fixed.
- Restructuring `Steam::Response` so success implies non-nil `data` — a
  larger design change; the local `T.must` binding is used instead.
- Migrating `ItemPricesController#history`/`InventoryValuesController` to
  `Appliers::SortApplier` (explicitly deferred by the layer ADR).

## Implementation Approach

Type-only edits, no behavior change, in the order below. The one design
decision is #1:

- **Chosen:** make `Appliers::SortApplier.call` generic with
  `T.type_parameter(:Enum)` inferred from `default:`.
- **Rejected — `T.any` union of all option classes:** violates
  `list-query-objects.md` (MUST NOT: `Appliers::*` must never reference a
  concrete `Options::*` class by name), and union members don't share
  `#apply`/`#duration`, so call sites would still need manual `case`
  dispatch.
- **Rejected — interface module:** `#apply` and `#duration` don't unify
  into one abstract method, so it would need two interfaces and still
  can't type the return without a union.

The generic needs no registry and no bound, keeps `Appliers::*` depending
only on `T::Enum`, and closes the "accepted gap" the layer ADR recorded
under Consequences (Negative). Verified compiles on a standalone probe.

For #4, `connect_pool`'s generated RBI is empty because `sidekiq` loads
`connection_pool` transitively before Tapioca tracks it, so regeneration
keeps producing an empty stub — use a shim, matching the existing
`ffi_shim.rbi` precedent.

## Files To Modify

- `app_fetcher/app/queries/appliers/sort_applier.rb` — replace
  `returns(T::Enum)` with a generic `T.type_parameter(:Enum)` inferred
  from `default: T.all(T.type_parameter(:Enum), T::Enum)`; keep
  `enum_class: T.class_of(T::Enum)`; return `T.unsafe(option)` after the
  `raise` guard. Reason: fixes errors 1a/1b/1c/1d/1e and restores
  `.apply`/`.duration` at call sites.
- `app_fetcher/app/queries/options/item_filter_field.rb` — declare the
  `apply` sig with `T::Sig::WithoutRuntime.sig`, typing `scope` and the
  return as `Item::PrivateRelation` (not `ActiveRecord::Relation`, not the
  non-existent `Item::ActiveRecord_Relation`). `Item::PrivateRelation` is a
  Tapioca RBI-only type that doesn't exist at runtime, so a normal `sig`
  would raise `NameError`; `WithoutRuntime.sig` keeps the static scope
  resolution without the runtime check. Reason: fixes errors 2a–2d; the
  scope methods live on `Item::PrivateRelation` in
  `sorbet/rbi/dsl/item.rbi`.
- `app_fetcher/app/parsers/item_parser.rb` — after
  `weapon_type, item_name = clean_name.split(WEAPON_TYPE_SEPARATOR, 2)`,
  add `item_name = T.must(item_name)`. Reason: fixes error 6; array
  destructuring widens each element to `T.nilable(String)`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` — bind
  `current_price_cents = item.current_price_cents` before the
  `next if ... nil?` guard and reuse the local in `base`/the result hash.
  Reason: fixes error 7 — Sorbet only carries `nil?` narrowing across
  locals, not repeated method calls.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — after the
  `unless response.success?` guard, bind `data = T.must(response.data)`
  once and use `data.*` for `more_items`/`market_hash_names`/
  `icon_urls_by_name`/`item_attributes_by_name`. Reason: fixes errors
  3a–3d.
- `app_fetcher/app/workers/price_update_worker.rb` — bind
  `price = item.current_price_cents` and guard `return if price.nil?`
  before `publish_to_stream`, publishing `item.change_24h_cents || 0`.
  Reason: fixes errors 5a/5b, and matches
  `agent/styleguides/fetcher/background-jobs.md`'s MUST ("guard on a nil
  price before publishing to `prices_stream`; a not-yet-priced item is a
  normal state, not a failure"). `T.must` is wrong here — it would turn a
  normal not-yet-priced item into a raised failure.
- `app_fetcher/config/initializers/redis.rb` — wrap `STREAM_REDIS_POOL`
  in `T.let(..., ConnectionPool)`. Reason: fixes error 4a (`typed: strict`
  requires an annotated constant).
- `app_fetcher/lib/faraday/user_agent_rotator.rb` — call the public
  reader `app.call(env)` instead of `@app.call(env)`. Reason: fixes error
  8; `Faraday::Middleware#app` is in the RBI, the ivar isn't declared.
- `app_fetcher/sorbet/tapioca/config.yml` — add `connection_pool` to
  `gem.exclude`. Reason: makes the intentional shim explicit (optional but
  consistent with `ffi`).
- `agent/styleguides/fix_me.md` — remove the now-fixed entries
  (`item_parser.rb`, `item_prices_controller.rb`, `price_update_worker.rb`,
  `user_inventory_sync_service.rb`); add an entry for the `bin/tapioca
  gem` / `solid_cache` load-order breakage (logged, not fixed here).

## Files To Create

- `app_fetcher/sorbet/rbi/shims/connection_pool.rbi` — minimal
  `# typed: false` shim declaring `ConnectionPool.new`/`#with`, so the
  constant resolves and `T.let(..., ConnectionPool)` typechecks. Necessary
  because Tapioca emits an empty RBI for this gem (loaded early by
  `sidekiq`); precedent: `sorbet/rbi/shims/ffi_shim.rbi`.

## Test Plan

These are type-level fixes; runtime behavior is already covered by the
existing specs, which must stay green:

- `spec/parsers/item_parser_spec.rb` — already asserts `item_name` for the
  separator/dispatch cases.
- `spec/services/user_inventory_sync_service_spec.rb` — already covers
  success/failure/truncation paths.
- `spec/workers/price_update_worker_spec.rb` — already asserts the stream
  payload (`price_cents`/`change_24h_cents`).
- `spec/queries/**` — already cover `ItemCatalogQuery`,
  `InventoryCatalogQuery`, `InventoryDetailQuery` (the `.apply`/`.duration`
  call sites).

New/updated:

- None required. These are type-only edits with no runtime behavior change,
  so no new example can drive them red→green. Spec files carry no
  `# typed:` sigil (`rspec-conventions.md` MUST), so `srb tc` does not
  typecheck them — a `T.let(...)` line in a spec proves nothing.
- Optional (not a type guard): a `PricePeriod` `.call` case in
  `spec/queries/appliers/sort_applier_spec.rb` as a small genericity
  regression (the current spec only exercises `Options::ItemSortOption`).

The regression gate is `srb tc` over the production call sites — the
concrete-enum return is exercised by `ItemCatalogQuery`,
`InventoryCatalogQuery`, `InventoryDetailQuery`, and
`ItemPricesController` — plus the existing RSpec suite, which proves no
runtime behavior changed.

## Implementation Steps

1. Make `Appliers::SortApplier.call` generic (as described); confirm the
   5 downstream errors clear.
2. Change `Options::ItemFilterField#apply`'s `scope`/return sig to
   `Item::PrivateRelation`.
3. Add `T.must(item_name)` in `ItemParser.parse`.
4. Hoist `current_price_cents` into a local in
   `ItemPricesController#dynamics`.
5. Bind `data = T.must(response.data)` once in `UserInventorySyncService`.
6. Add the nil-price guard (and `change_24h_cents || 0`) in
   `PriceUpdateWorker` before publishing.
7. Use `app.call(env)` in `Faraday::UserAgentRotator`.
8. Add `sorbet/rbi/shims/connection_pool.rbi` and wrap `STREAM_REDIS_POOL`
   in `T.let`; optionally add `connection_pool` to the tapioca exclude
   list.
9. Update `sort_applier_spec.rb` with the `PricePeriod` + `T.let` case.
10. Update `fix_me.md` (remove fixed entries, add the tapioca-gem entry).
11. Run verification below; fix any fallout.

## Verification

- `docker compose -f docker-compose.yml -f docker-compose.ci.yml run
  --rm --no-deps app_fetcher bundle exec srb tc` → `No errors!`.
- `app_fetcher/bin/ci` (RuboCop + RSpec, and the Sorbet step it mirrors
  from `.github/workflows/ci.yml`).
- Confirm `app_core` Sorbet/CI remains green (untouched).
- Confirm the new `connection_pool` shim introduces no new `srb tc`
  errors in the worker's `redis.xadd` call.

## Risks

- `T.unsafe(option)` in `SortApplier`: a localized escape at the
  deserialization boundary (`try_deserialize` returns `T.nilable(T::Enum)`;
  `T.type_parameter` is not usable in a method body). Acceptable, and the
  only new `T.untyped`-adjacent construct.
- `T.must` in `UserInventorySyncService` encodes an invariant
  (`Steam::Client` populates `data` on 200). It holds today; if relaxed,
  revisit.
- `PriceUpdateWorker`'s nil-price guard means a not-yet-priced item is
  skipped. A separate open question (out of scope here):
  `PriceLogBuilder#to_cents` returns `0` when Steam reports no price, and
  `background-jobs.md` says the stream should never carry a `0` price — a
  `0`-price guard would be a behavior change, so it is not included in this
  type-only plan.
- `Item::PrivateRelation` is a generated name; a future Tapioca/Rails
  change could rename it. Regeneration via `tapioca dsl Item` would surface
  that immediately.
- The `connection_pool` shim could drift from the gem's real API; keep it
  minimal (`new`, `with`) and revisit if `tapioca gem` is ever repaired.

## Assumptions

- `bin/tapioca gem` is currently broken for the whole app because
  `solid_cache`'s model resolves the `cache` connection before Rails
  configs load; this is a tooling issue, not fixed here.
- Regenerating `connection_pool`'s RBI would still yield an empty stub
  (loaded transitively by `sidekiq` before Tapioca tracks it), so a shim is
  the durable fix.

## Completion Criteria

The plan is complete when:

- `srb tc` is green for `app_fetcher` (0 errors);
- no runtime behavior changed (existing specs green);
- `srb tc` covers the generic `SortApplier` through its production call
  sites;
- `fix_me.md` and the `connection_pool` shim reflect the outcome;
- `bin/ci` passes locally.

## Applicable Styleguides

- `agent/styleguides/ruby-sorbet.md` — constrains every type edit:
  `# typed: strict`, `T.let` on the new constant, and (via its `##
  Exceptions` section) the `T.type_parameter` generic + localized
  `T.unsafe` in `SortApplier` and the gem-RBI shim rule.
- `agent/styleguides/fetcher/list-query-objects.md` — constrains the
  `Appliers::SortApplier`/`Options::ItemFilterField` changes: `Appliers::*`
  stays resource-agnostic (no concrete `Options::*`, model, or scope named
  in it), while `Options::*` may depend on the model scopes it calls.
- `agent/styleguides/fetcher/steam-response-objects.md` — mandates the
  `data = T.must(response.data)` narrowing for fix #3.
- `agent/styleguides/fetcher/background-jobs.md` — mandates the nil-price
  guard for fix #5 (a not-yet-priced item is a normal state, never a
  raised failure).
- `agent/styleguides/rspec-conventions.md` — constrains the test plan:
  existing unit specs stay green; specs carry no sigil, so there are no
  type-level spec assertions.
- `agent/styleguides/ci-and-coverage.md` — constrains verification: run
  through `docker-compose.yml` + `docker-compose.ci.yml`, keep `bin/ci`
  equal to CI, and `srb tc` is part of the blocking `linters` job.
- `agent/styleguides/fix_me.md` — the deviations ledger this plan updates
  (remove the fixed entries; log the `tapioca gem`/`solid_cache` breakage).

## Implementation Summary

Status: `implemented`.

### Implemented

- `app/queries/appliers/sort_applier.rb` — `call` is now generic over the
  resolved enum (`T.type_parameter(:Enum)`, inferred from `default:`),
  with `enum_class: T.class_of(T::Enum)` and a single localized
  `T.unsafe(option)` after the `try_deserialize` guard. Fixed the 5
  `.apply`/`.duration`/`PricePeriod` errors downstream.
- `app/queries/options/item_filter_field.rb` — `apply` now types `scope`
  and its return as `Item::PrivateRelation`, declared via
  `T::Sig::WithoutRuntime.sig`.
- `app/parsers/item_parser.rb` — `item_name = T.must(item_name)` after the
  two-part `split`.
- `app/controllers/api/v1/item_prices_controller.rb` — `current_price_cents`
  hoisted into a local before the nil guard and reused.
- `app/services/user_inventory_sync_service.rb` — `data = T.must(response.data)`
  bound once; the four call sites read off the local.
- `app/workers/price_update_worker.rb` — `price` local + `return if
  price.nil?` before publishing; `change_24h_cents || 0` for the sig.
- `lib/faraday/user_agent_rotator.rb` — `app.call(env)` (public reader)
  instead of the undeclared `@app`.
- `config/initializers/redis.rb` — `STREAM_REDIS_POOL` wrapped in
  `T.let(..., ConnectionPool)`.
- `sorbet/rbi/shims/connection_pool.rbi` (new) — minimal `# typed: false`
  shim; `connection_pool` added to `sorbet/tapioca/config.yml`'s
  `gem.exclude`.
- `agent/styleguides/ruby-sorbet.md` — new `## Exceptions` section
  (generics/`T.unsafe`, gem-RBI shims, and `T::Sig::WithoutRuntime.sig`
  for Tapioca relation types) + two canonical entries.
- `agent/styleguides/fix_me.md` — removed the four now-fixed entries; added
  the empty `connection_pool` RBI entry.

No runtime behavior change: `price_update_worker`'s guard is reachable only
if the item is unpriced after a successful `PriceUpdateService.call`, which
doesn't happen today (`PriceLogBuilder#to_cents` always returns `Integer`).

### Tests

No new examples — these are type-only edits with no behavior change, and
spec files carry no `# typed:` sigil, so `srb tc` is the regression gate.

Commands actually run (all in the `app_fetcher` service, via
`docker compose -f docker-compose.yml -f docker-compose.ci.yml run --rm`):

- `bundle exec srb tc`
- `bundle exec rspec` (full suite)
- `bin/rubocop` on the 8 changed Ruby files

### Verification

- `srb tc`: `No errors! Great job.` (was 21 errors).
- RSpec: `378 examples, 0 failures`.
- RuboCop: `8 files inspected, no offenses detected`.
- `app_core` untouched (its Sorbet was already green).

### Deviations From The Plan

- **`Options::ItemFilterField#apply` uses `T::Sig::WithoutRuntime.sig`.**
  The plan named `Item::PrivateRelation` but assumed a normal `sig`. That
  type is defined only in Tapioca's RBI, not at runtime, so a normal `sig`
  raises `NameError` on first call (confirmed by the query specs). Per
  Tapioca's own guidance, `T::Sig::WithoutRuntime.sig` keeps the static
  scope resolution while skipping the runtime check. Recorded as a third
  `## Exceptions` entry in `ruby-sorbet.md`.
- **`fix_me.md` entry is scoped to the empty RBI file** rather than a bare
  "tooling" note, so it fits that file's one-entry-per-file format.

### Remaining Issues

- `bin/tapioca gem` still aborts on `solid_cache` resolving the `cache`
  connection before Rails loads its DB config; the `connection_pool` shim
  works around its local effect only. Logged in `fix_me.md`.
- A `0` price (`PriceLogBuilder#to_cents` returns `0` when Steam reports no
  price) can still be published to `prices_stream`; `background-jobs.md`
  says never to write `nil`/`0`. Resolving that is a behavior change,
  deliberately left out of this type-only plan.
- `app_fetcher/bin/ci` can't run at all in this environment
  (`LoadError: active_support/continuous_integration`, absent from the
  Rails 7.2 bundle), so the "run `bin/ci`" step of Verification was
  replaced by running its constituent checks directly (`bin/rubocop`,
  `bundle exec srb tc`, `bundle exec rspec`). Logged in `fix_me.md`.
