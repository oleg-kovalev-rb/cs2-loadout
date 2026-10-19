---
status: implemented
app: fetcher
goal: Extract ItemPricesController's warmup cap, dedup TTL/key, and PriceUpdateWorker enqueue logic into a dedicated PriceWarmupService
created: 2026-10-19
---

# Development Plan

## Applicable Styleguides

- **`agent/styleguides/fetcher/services.md`** — governs the extraction
  into `app/services/`, the single `.call` entry point,
  `ServiceResult[T::Array[Integer]]`, and the controller-called
  side-effect-service rule.
- **`agent/styleguides/fetcher/caching.md`** — governs the warmup/dedup
  pattern, dedup-key/TTL mechanics, and the rule against putting this in
  `app/caching/`.
- **`agent/styleguides/fetcher/architecture-layers.md`** — layer map for
  services vs. caching vs. controllers, and the canonical
  implementations list.
- **`agent/styleguides/fetcher/internal-api-controllers.md`** — V1
  controller thinness and the existing `ItemPricesController#dynamics`
  collaborator shape.
- **`agent/adr/fetcher/price-cache-invalidation.md`** — the architectural
  source for the warmup cap, dedup TTL, and lazy-warmup behavior.
- **`agent/adr/fetcher/cross-scenario-service-layer.md`** — confirms a
  side-effect service call is not the controller-persistence carve-out.
- **`agent/styleguides/ruby-sorbet.md`** — `# typed: strict`, explicit
  sigs, and constant typing.
- **`agent/styleguides/rspec-conventions.md`** — unit-spec shape, real
  cache/queue assertions, and no database stubbing.
- **`agent/styleguides/fix_me.md`** — checked; none of the files this
  plan touches are currently listed as known deviations.

## Goal

Move `Api::V1::ItemPricesController`'s private `enqueue_price_warmup`
logic and its `WARMUP_CAP`/`WARMUP_DEDUP_TTL` constants into a dedicated
`app/services/` class, so the controller no longer owns the warmup
policy, the dedup key format, the TTL, or the Sidekiq enqueue loop.

Behavior must remain byte-for-byte identical.

## Expected Behavior

`GET /api/v1/item_prices/dynamics` keeps the same response and side
effects:

- Only owned items with `current_price_cents == nil` are considered.
- At most **20** items are enqueued per request.
- The dedup key remains `"price_warmup_pending:<item.id>"`.
- The dedup TTL remains **90 seconds**.
- A repeated request inside that window enqueues no duplicate jobs.
- `PriceUpdateWorker.perform_async(item.id)` is still the enqueue call.
- The response is still `{ prices: ..., pending_count: ... }`; no
  endpoint contract changes.

The new service returns
`ServiceResult[T::Array[Integer]]` with `Ok` and the ids it actually
enqueued (`[]` when nothing was eligible or everything was deduplicated).

## Scope

### In Scope

- Add `app_fetcher/app/services/price_warmup_service.rb`.
- Move `WARMUP_CAP`, `WARMUP_DEDUP_TTL`, the dedup key prefix, the
  nil-price filter, the cap, the dedup write, and the worker enqueue into
  the service.
- Reduce `ItemPricesController#dynamics` to a single
  `PriceWarmupService.call(priced_items.values)` call.
- Add a unit spec for the service.
- Update living styleguides/ADRs that currently say the warmup pattern
  lives in the calling controller/worker, or that controllers may only
  call services for the named synchronous-persistence sites.

### Out of Scope

- Changing the cap (20), dedup TTL (90s), key format, Sidekiq queue, or
  worker behavior.
- Moving `pending_count`, `owned_market_hash_names`, cache reads, or
  response serialization out of the controller.
- Changing the `Item.awaiting_price` predicate or non-marketable-item
  behavior.
- Changing the HTTP response or frontend.
- Creating a general `app/actions/` layer or a generic job-uniqueness
  abstraction.
- Rewriting historical plan files that mention the old controller-owned
  warmup.

## Implementation Approach

Add a flat, top-level `PriceWarmupService` under `app/services/` — the
same layer/naming shape as `PriceUpdateService` and
`UserInventorySyncService`:

```text
Api::V1::ItemPricesController#dynamics
    ↓ ItemPriceCache.fetch_for(names)
    ↓ PriceWarmupService.call(priced_items.values)
        ↓ filter nil-price items
        ↓ first(WARMUP_CAP)
        ↓ Rails.cache.write("price_warmup_pending:<id>", ...,
                            unless_exist: true, expires_in: 90.seconds)
        ↓ PriceUpdateWorker.perform_async(item.id)
    ↓ Item.awaiting_price...count
    ↓ ItemPriceDynamicsSerializer.call(...)
```

The service owns the whole operation as one nameable verb phrase:
"enqueue price warmups for not-yet-priced items." It returns
`ServiceResult[T::Array[Integer]]` (`Ok`, enqueued ids); there is no
expected failure branch, so unexpected exceptions propagate as the
service contract allows.

The controller no longer has any warmup constants or a private
`enqueue_price_warmup` method.

## Files To Modify

- **`app_fetcher/app/controllers/api/v1/item_prices_controller.rb`**
  - Remove `WARMUP_CAP`, `WARMUP_DEDUP_TTL`, and the private
    `enqueue_price_warmup` method.
  - Replace the call with `PriceWarmupService.call(priced_items.values)`.
  - Keep `owned_market_hash_names`, the cache read, the `pending_count`
    query, `trend`, and `history` unchanged.

- **`agent/styleguides/fetcher/caching.md`**
  - Update the Warmup/Dedup Pattern section: the pattern is now owned by
    a dedicated service (e.g. `PriceWarmupService`) rather than
    necessarily the calling controller/worker; it still never belongs in
    `app/caching/`.
  - Update the interaction diagram to show
    `ItemPricesController#dynamics → PriceWarmupService → PriceUpdateWorker`.

- **`agent/styleguides/fetcher/services.md`**
  - Update the callers rule: controllers may call a service for a
    cohesive side-effect operation (warmup/enqueue), not only the named
    synchronous-persistence sites.
  - Add `PriceWarmupService` to canonical implementations as the
    single-Scenario enqueue/dedup service.

- **`agent/styleguides/fetcher/architecture-layers.md`**
  - Update the services/controller dependency wording and interaction
    diagram to show `PriceWarmupService`.
  - Add it to canonical implementations.

- **`agent/adr/fetcher/price-cache-invalidation.md`**
  - Update the current-state lazy-warmup description and implementation
    constraints to name `PriceWarmupService` as the owner of the cap,
    dedup key/TTL, and enqueue call.
  - Preserve the historical decision record otherwise.

- **`agent/adr/fetcher/cross-scenario-service-layer.md`**
  - If needed, add a short current-state note that a controller may call
    a cohesive side-effect service (warmup enqueue) without that being
    the persistence carve-out; the persistence carve-out itself is
    unchanged.

## Files To Create

- **`app_fetcher/app/services/price_warmup_service.rb`**
  - `PriceWarmupService.call(items)`.
  - Owns `WARMUP_CAP`, `DEDUP_TTL`, `DEDUP_KEY_PREFIX`.
  - Returns `ServiceResult[T::Array[Integer]]`.

- **`app_fetcher/spec/services/price_warmup_service_spec.rb`**
  - Unit spec with in-memory `Item` instances, real `Rails.cache`, and
    `Sidekiq::Testing.fake!` (already configured globally).

## Test Plan

New unit spec covering:

- enqueues only items with `current_price_cents == nil`;
- returns `Ok` with the enqueued item ids;
- returns `Ok(data: [])` when nothing is eligible;
- caps enqueues at 20 for 21+ eligible items;
- deduplicates a second call within the TTL via the real
  `Rails.cache` flag (second call enqueues nothing, first call's jobs
  remain the only ones);
- does not enqueue already-priced items.

Existing `spec/requests/api/v1/item_prices_spec.rb` remains the
integration contract and must stay green: warmup for an unpriced item,
dedup on repeat, cap at 20, and the mixed-inventory `pending_count`
behavior.

No request-spec changes are expected unless an assertion currently
reaches into controller internals (it does not).

## Implementation Steps

1. Write `spec/services/price_warmup_service_spec.rb` first and confirm
   it fails because the service does not exist.
2. Implement `PriceWarmupService` with the moved constants/logic.
3. Update `ItemPricesController#dynamics` and remove the private
   method/constants.
4. Run the new service spec and the existing item-prices request spec.
5. Update the living styleguides/ADRs listed above.
6. Run the full `app_fetcher` suite, RuboCop, and `srb tc`.

## Verification

- `docker compose run --rm --no-deps app_fetcher bundle exec rspec spec/services/price_warmup_service_spec.rb spec/requests/api/v1/item_prices_spec.rb`
- `docker compose run --rm --no-deps app_fetcher bundle exec rspec`
- `docker compose run --rm --no-deps app_fetcher bin/rubocop app/services/price_warmup_service.rb app/controllers/api/v1/item_prices_controller.rb spec/services/price_warmup_service_spec.rb`
- `docker compose run --rm --no-deps app_fetcher bundle exec srb tc`
- `git diff --check`

## Risks

- **Behavior drift in dedup semantics.** The key prefix, TTL, `unless_exist:
  true`, and enqueue order must stay exactly as they are; only their
  location changes.
- **Accidentally filtering by marketability.** Existing behavior filters
  only on `current_price_cents.nil?`; adding a marketable filter would
  change which jobs are enqueued, even though the `pending_count` query
  is marketability-aware.
- **Service result ignored by the controller.** That is acceptable here:
  the operation is a best-effort side effect and the controller has no
  branch on its outcome, same as `InventoryValueRecordingService`'s
  cold-start seed call. The service still returns the produced ids for
  testability.
- **Styleguide drift.** `caching.md`, `services.md`, and the
  price-cache ADR currently describe controller-owned warmup logic and
  controller service calls limited to persistence; leaving them stale
  would contradict the implementation.

## Assumptions

- The new service belongs in `app/services/` (not `app/caching/`), per
  `caching.md`: it deduplicates an enqueue and touches a worker, so it is
  orchestration, not cache read-through mechanics.
- A single-Scenario service is allowed by the current `services.md`
  responsibility-based rule.
- Returning enqueued item ids is useful enough for the `ServiceResult`
  payload; no caller currently needs a count instead.

## Completion Criteria

- `ItemPricesController` has no warmup constants or
  `enqueue_price_warmup` method.
- `PriceWarmupService` owns the cap, TTL, key format, dedup, and enqueue,
  with identical behavior.
- Service unit spec and existing request specs pass.
- Full suite, RuboCop, and `srb tc` are green.
- Living docs no longer describe warmup logic as controller-owned.

---

# Implementation Summary

## Implemented

- Added `app_fetcher/app/services/price_warmup_service.rb`:
  `PriceWarmupService.call(items)` owns the nil-price filter,
  `WARMUP_CAP = 20`, `DEDUP_TTL = 90.seconds`, the
  `"price_warmup_pending:<id>"` key prefix, the real `Rails.cache`
  `unless_exist` write, and the `PriceUpdateWorker.perform_async` loop.
  It returns `ServiceResult[T::Array[Integer]]` (`Ok` + enqueued ids).
- `Api::V1::ItemPricesController#dynamics` now calls
  `PriceWarmupService.call(priced_items.values)` and no longer defines
  `WARMUP_CAP`, `WARMUP_DEDUP_TTL`, or `enqueue_price_warmup`. Cache
  reads, `owned_market_hash_names`, `pending_count`, and response
  serialization are unchanged.
- Updated `caching.md`, `services.md`, `architecture-layers.md`,
  `price-cache-invalidation.md`, and `cross-scenario-service-layer.md`
  to name `PriceWarmupService` as the warmup-policy owner and to allow
  controller-called side-effect services.

## Tests

Added `app_fetcher/spec/services/price_warmup_service_spec.rb`:

- unpriced-only enqueue + `Ok` ids;
- empty result when nothing is eligible;
- 20-item cap;
- dedup across two calls within the TTL.

Commands executed:

- `docker compose run --rm --no-deps app_fetcher bundle exec rspec spec/services/price_warmup_service_spec.rb`
  — RED first (`uninitialized constant PriceWarmupService`).
- `docker compose run --rm --no-deps app_fetcher bundle exec rspec spec/services/price_warmup_service_spec.rb spec/requests/api/v1/item_prices_spec.rb`
  — 25 examples, 0 failures (after fixing the spec's memoized
  `subject(:call)` so the dedup example actually calls the service twice).
- `docker compose run --rm --no-deps app_fetcher bundle exec rspec`
  — 474 examples, 0 failures.
- `docker compose run --rm --no-deps app_fetcher bin/rubocop app/services/price_warmup_service.rb app/controllers/api/v1/item_prices_controller.rb spec/services/price_warmup_service_spec.rb`
  — 3 files, no offenses.
- `docker compose run --rm --no-deps app_fetcher bundle exec srb tc`
  — No errors.
- `git diff --check` — clean.

## Verification

- Warmup behavior preserved: same 20 cap, same 90-second TTL, same
  `price_warmup_pending:<id>` key, same worker call, same nil-price-only
  selection.
- Existing `item_prices` request specs (enqueue, dedup, cap,
  `pending_count`, response shape) stay green.
- Full `app_fetcher` suite: **474 examples, 0 failures**.
- RuboCop and Sorbet: clean.

## Deviations

- No implementation deviation. The only correction during TDD was in the
  spec itself: using `subject(:call)` twice memoized the first result, so
  the dedup example now calls `described_class.call(items)` explicitly
  twice.

## Remaining Issues

None.
