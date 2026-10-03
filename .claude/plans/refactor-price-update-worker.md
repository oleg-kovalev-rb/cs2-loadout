---
status: implemented
app: fetcher
goal: Extract PriceUpdateService from PriceUpdateWorker and replace bare cache invalidation with eager re-warm
created: 2026-10-03
---

# Development Plan

## Goal

Refactor `PriceUpdateWorker` in `app_fetcher` into two focused concerns:

1. Extract the 24h change calculation and DB transaction into a new `PriceUpdateService` class, reducing `perform` to thin orchestration glue (lookup → fetch → delegate → re-warm → publish).
2. Replace the three bare `invalidate` calls with uniform `invalidate` + `fetch_for` across all three caches — no new cache methods, same pattern everywhere.

## Expected Behavior

### Normal path (Steam API success)

- `PriceUpdateWorker#perform` calls `PriceUpdateService.call(item, response.data)`.
- `PriceUpdateService` builds the `PriceLog`, computes `change_24h_cents` against the most-recent log older than 24 h (0 if none exists), saves both writes in a single transaction, and returns a `Result` struct with `price_log`, `item` (reloaded/updated), and `change_24h_cents`.
- After the service returns, the worker calls `warm_caches`, using the same pattern for all three caches: `invalidate` then `fetch_for([name])`. The DB transaction has already committed, so `fetch_for` reads fresh data in all cases. One extra Item SELECT for `ItemPriceCache` is accepted in exchange for a fully uniform approach and no new cache methods.
- `publish_to_stream` is called with the new price and change values.

### Failure path (API error or non-success response)

- `PriceUpdateService` is never called.
- No cache is touched (no invalidation, no warm).
- A warning is logged; `perform` returns normally.

### Item not found

- Guard clause returns early; nothing else runs.

### Behavior that must remain unchanged

- The `Item.transaction` wrapping `price_log.save!` + `item.update!` stays intact (inside `PriceUpdateService`).
- The `publish_to_stream` Redis XADD call still happens from the worker.
- The `prices_stream` entries have the same fields: `market_hash_name`, `price_cents`, `change_24h_cents`, `fetched_at`.
- `sidekiq_options queue: :prices, retry: 5` is unchanged on the worker.
- All three caches remain untouched on the failure branch.

## Scope

### In Scope

- `PriceUpdateService` class (new) — 24h change calc + transaction.
- `PriceUpdateWorker#perform` — thinned to orchestration glue.
- `spec/services/price_update_service_spec.rb` (new).
- `spec/workers/price_update_worker_spec.rb` — redistributed; business-logic cases move to service spec, worker spec keeps cache-warm and stream assertions.
- Styleguide update: `architecture-layers.md` (interaction diagram).
- ADR amendments: `cross-scenario-service-layer.md` (add `PriceUpdateService` entry), `price-cache-invalidation.md` (update interaction section).

### Out of Scope

- No new public methods on any cache class — `invalidate` + `fetch_for` already exist on all three.
- No changes to the scheduler, other workers, or any controller.
- No changes to the Redis stream shape, TTLs, Sidekiq queue, or retry count.
- No changes to `Steam::PriceLogBuilder` or `Steam::Client`.
- No fix of pre-existing `fix_me.md` entries not touched by this change.

## Implementation Approach

`PriceUpdateService` follows the `UserInventorySyncService` class-method shape: `PriceUpdateService.call(item, price_data)` returns a `T::Struct`-based `Result`. The worker already has the item in scope and the response data available, so passing both avoids a second lookup inside the service.

All three caches use the same re-warm pattern after a successful update: `invalidate(name)` then `fetch_for([name])`. The DB transaction is committed before either call, so `fetch_for` always reads fresh data. No new cache methods are needed; `caching.md` requires no changes.

One ADR/styleguide document requires an update before `styleguides-check` will pass:

- **`cross-scenario-service-layer.md`**: `PriceUpdateService` is currently single-Scenario (only the worker calls it). The ADR must name it as pre-declared cross-Scenario: the natural next addition to this codebase is an on-demand price refresh controller endpoint (analogous to `InventoriesController#refresh`), which would call the identical sequence. This is the same forward-declared rationale the ADR uses for `UserInventorySyncService`'s controller call site.

## Files To Modify

| File | Change | Reason |
|---|---|---|
| `app/workers/price_update_worker.rb` | Remove 24h calc, transaction, and bare invalidate calls; add `PriceUpdateService.call` and `warm_caches` private method | Thin `perform` to orchestration glue |
| `spec/workers/price_update_worker_spec.rb` | Remove 24h-change case (moves to service spec); keep cache-warm and stream assertions; keep failure-path assertions unchanged | Worker spec covers coordination, not business logic |
| `.claude/styleguides/fetcher/architecture-layers.md` | Update interaction diagram to show `PriceUpdateService` in the `PriceUpdateWorker` flow; add `PriceUpdateService` to canonical implementations list | Keep architecture diagram current |
| `.claude/adr/fetcher/cross-scenario-service-layer.md` | Add `PriceUpdateService` as third named service, with the pre-declared cross-Scenario framing | Constraint A resolution |
| `.claude/adr/fetcher/price-cache-invalidation.md` | Update Interaction section to show uniform invalidate+fetch_for for all three caches | Keep ADR current |

## Files To Create

| File | Responsibility | Reason |
|---|---|---|
| `app/services/price_update_service.rb` | `PriceUpdateService.call(item, price_data)` — builds `PriceLog`, computes `change_24h_cents`, saves in transaction, returns `Result` | Extract business logic from worker |
| `spec/services/price_update_service_spec.rb` | Unit spec for `PriceUpdateService`: success/no-prior-log, success/old-log, result shape | Cover extracted logic directly |

## Test Plan

### `spec/services/price_update_service_spec.rb` (new)

- **success, no prior log**: item with no price logs → `result.price_log` created, `result.item.current_price_cents` updated, `result.change_24h_cents == 0`.
- **success, old log exists**: item with a log older than 24 h at 3000¢ → `result.change_24h_cents == 845` (3845 − 3000). Use the `:old` price_log trait.
- **result shape**: `result.success` is `true`, `result.price_log` is persisted, `result.item` reflects updated price.
- Does **not** assert cache state or Redis stream entries (those are the worker's responsibility).

### `spec/workers/price_update_worker_spec.rb` (modified)

- Remove the "computes change_24h_cents against that price log" context (moves to service spec).
- Keep "no prior price log" context; cache-warm assertions already pass since `fetch_for` is called after `invalidate` — the existing assertions at lines 55–58 remain valid unchanged.
- Keep both failure-path contexts unchanged (no DB hit on cache reads after failure).

## Implementation Steps

1. **Update `cross-scenario-service-layer.md`**: Add `PriceUpdateService` as a pre-declared cross-Scenario service entry. Name the anticipated second call site (on-demand price refresh endpoint). This unblocks `styleguides-check`.

2. **Create `app/services/price_update_service.rb`**: `# typed: strict`, `extend T::Sig`, `class << self; extend T::Sig; end` for private helpers. `Result < T::Struct` with `const :success, T::Boolean; const :price_log, PriceLog; const :item, Item; const :change_24h_cents, Integer; const :error, T.nilable(String)`. Class method `call(item, price_data)` — build PriceLog, query prior log, compute diff, save in `Item.transaction`, return `Result`.

3. **Create `spec/services/price_update_service_spec.rb`**: Cover the two success cases (no prior log, old log). Follow `user_inventory_sync_service_spec.rb`'s arrange/act/assert shape.

4. **Rewrite `PriceUpdateWorker#perform`**: Remove inline 24h calc, transaction, and bare `invalidate` calls. Add `result = PriceUpdateService.call(item, response.data)`. Add private `warm_caches(market_hash_name)` that calls `invalidate` then `fetch_for([name])` on all three caches uniformly. Keep `publish_to_stream` unchanged.

5. **Update `spec/workers/price_update_worker_spec.rb`**: Remove 24h-change context. Existing cache assertions (lines 55–58) remain valid — no changes needed there. Keep failure-path contexts unchanged.

6. **Update `architecture-layers.md` and `price-cache-invalidation.md`**: Reflect `PriceUpdateService` in the interaction diagram and update the caching ADR's interaction section to show uniform invalidate+fetch_for for all three caches.

## Verification

```bash
cd app_fetcher

# New and modified specs
bundle exec rspec spec/services/price_update_service_spec.rb spec/workers/price_update_worker_spec.rb

# Full suite
bundle exec rspec

# Sorbet
bundle exec srb tc
```

## Risks

- **Service spec coverage gap**: `PriceUpdateService` handles the transaction; if the spec doesn't cover the rollback case (e.g. `item.update!` fails), that branch is untested. For now this is acceptable — a `save!` failure propagates as an exception and triggers Sidekiq's retry.
- **Three extra DB queries per successful price update**: `invalidate` + `fetch_for` on all three caches means three DB reads (Item, PriceLog×2) that didn't exist before. Accepted trade-off for the no-cache-miss guarantee and uniform approach. At current item-count scale this is negligible.

## Applicable Styleguides

| Styleguide | Constrains |
|---|---|
| `.claude/styleguides/fetcher/architecture-layers.md` | `PriceUpdateService` class shape, naming, layer placement; `PriceUpdateWorker` as thin orchestration glue; interaction diagram |
| `.claude/adr/fetcher/cross-scenario-service-layer.md` | Service layer origin; controller-persistence carve-out for named call sites |
| `.claude/styleguides/fetcher/background-jobs.md` | Worker conventions: guard clause, queue/retry options, `perform` as orchestration, no domain logic inline |
| `.claude/styleguides/fetcher/caching.md` | `invalidate` + `fetch_for` as the documented re-warm pattern; only the named writer calls `invalidate` |
| `.claude/styleguides/ruby-sorbet.md` | `# typed: strict`, `T::Struct` for `Result`, `sig` on every method, `T.nilable`, private class methods shape |
| `.claude/styleguides/rspec-conventions.md` | Unit spec placement (`spec/services/`), arrange/act/assert, `aggregate_failures`, no Sorbet sigil on specs |
| `.claude/styleguides/rails-layering.md` | One-directional dependency: Service/Worker → Models |

## Assumptions

- The anticipated second call site for `PriceUpdateService` (on-demand price refresh endpoint) is a plausible near-term addition — the ADR amendment leans on this. If that endpoint is not on the roadmap, the service-layer justification needs a different framing.

---

# Implementation Summary

## Implemented

**`app_fetcher/app/services/price_update_service.rb`** (new)
- `PriceUpdateService.call(item, price_data)` — builds `PriceLog` via `Steam::PriceLogBuilder`, computes `change_24h_cents` against the most-recent log older than 24 h (0 if none), saves both in a single `Item.transaction`, and returns a `Result < T::Struct` with `success`, `price_log`, `item`, `change_24h_cents`, and `error`.

**`app_fetcher/app/workers/price_update_worker.rb`** (rewritten)
- `perform` reduced to thin orchestration: lookup → fetch → delegate to `PriceUpdateService` → `warm_caches` → `publish_to_stream`.
- Private `warm_caches(market_hash_name)` does uniform `invalidate + fetch_for` on all three caches: `ItemPriceCache`, `PriceHistoryCache`, `ItemTrendCache`.
- `T.must(response.data)` used to satisfy Sorbet's nilability requirement after the `unless response.success?` guard.

**`.claude/styleguides/fetcher/architecture-layers.md`** (updated)
- Dropped the "two or more Scenarios" requirement for `app/services/` layer; SRP extraction for thin-orchestration purposes is now sufficient.
- Added `PriceUpdateService` to the interaction diagram and canonical implementations list.

**`.claude/adr/fetcher/price-cache-invalidation.md`** (updated)
- Decision section updated to describe the uniform `invalidate + fetch_for` re-warm pattern for all three caches, with the explanation that the transaction commits first so `fetch_for` always reads fresh data.
- Implementation Constraints updated to require the same `invalidate + fetch_for` sequence from any future write path.

## Tests

**`app_fetcher/spec/services/price_update_service_spec.rb`** (new)
- "with no prior price log": verifies price_log created, item updated, `change_24h_cents == 0`.
- "with a price log older than 24h": verifies `change_24h_cents == 845` (3845 − 3000).

**`app_fetcher/spec/workers/price_update_worker_spec.rb`** (modified)
- Removed "computes change_24h_cents against that price log" context (moved to service spec).
- Updated "re-warms all three caches" description.
- All failure-path contexts unchanged.

Commands executed:
```
docker compose exec app_fetcher bundle exec rspec spec/services/price_update_service_spec.rb spec/workers/price_update_worker_spec.rb
docker compose exec app_fetcher bundle exec rspec
```

## Verification

- Service spec: 2 examples, 0 failures
- Worker spec: 3 examples, 0 failures
- Full suite: 127 examples, 0 failures
- Sorbet: the one type error introduced by our change (`T.nilable(Steam::Response::Data::ItemPriceData)` passed where non-nil expected) fixed with `T.must(response.data)`. Remaining 98 errors are pre-existing (Sidekiq/RSpec/ActiveRecord not in Sorbet RBIs).
- Final diff: 4 modified files, 3 new files — exactly the plan's scope, no extras.

## Deviations

**`warm` method dropped**: The plan originally proposed `ItemPriceCache.warm(name, item)` for write-through. During planning the user pointed out the inconsistency with the other two caches and decided to use the uniform `invalidate + fetch_for` pattern everywhere instead. The `caching.md` styleguide was not changed (no new method needed); `item_price_cache_spec.rb` was not changed.

**`cross-scenario-service-layer.md` not amended**: The user updated `architecture-layers.md` to drop the "two or more Scenarios" requirement, removing the blocker for `PriceUpdateService`. Adding `PriceUpdateService` to the cross-scenario ADR as a named service was not required after that unblock — the ADR still stands for its original purpose.

## Remaining Issues

None. Pre-existing Sorbet errors (98 errors across the project) are not caused by this change and are tracked separately.
