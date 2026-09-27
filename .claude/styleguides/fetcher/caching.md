---
description: Rails.cache/solid_cache conventions in app_fetcher — dedicated app/caching/ classes, versioned keys, by-key invalidation owned by the writing worker, TTL as a safety net only, and the warmup/dedup pattern for not-yet-priced items.
---

# Caching (`app/caching/`)

See `.claude/adr/fetcher/price-cache-invalidation.md` for why this is a
dedicated layer instead of living on the models or in the controllers.

## Purpose

Serve read-heavy, slow-changing data (an item's current price, its
default-window price history) from `solid_cache` instead of Postgres on
every request, while keeping explicit control over when that cache goes
stale. What belongs here: bulk cache read-through with a DB fallback, and
by-key invalidation. What does not: parsing Steam responses, building AR
attributes, or any business logic beyond "is this cached, and if not, go
get it" — that's still the model's/builder's job.

## When to Use

Use this pattern for a read path whose underlying data changes at a known,
infrequent cadence driven by a background job (here: `PriceUpdateWorker`,
hourly at most per item) and that's read far more often than it changes.
Don't reach for it for data that changes on every request, or where
staleness of even a few seconds would be user-visible in a way that
matters.

## Structure

- One class per cached resource, under `app/caching/`, top-level (not
  namespaced under `Steam::` — like workers and schedulers, these encode
  generic caching mechanics, not Steam-domain parsing):
  `ItemPriceCache`, `PriceHistoryCache`.
- Each class is a plain Ruby class with only class-level methods (`class
  << self; extend T::Sig; ...; end` for private ones, per
  `.claude/styleguides/ruby-sorbet.md`) — never instantiated.

## Interface

Exactly two public class methods per caching class:

- `.fetch_for(market_hash_names)` — bulk read. Returns the same shape the
  caller would have gotten from a direct query (a `market_hash_name =>
  data` mapping); callers should not need to know whether a given name
  was a cache hit or a DB fallback.
- `.invalidate(market_hash_name)` — single-key delete. Returns nothing
  meaningful; callers don't branch on its result.

No other public methods. A caching class doesn't expose `.fetch` or
`.write` primitives directly — collapsing every call site to `fetch_for`
keeps the bulk-read-avoids-N+1 property (see Rules) from being
accidentally bypassed by a future one-off caller.

## Responsibilities

Owns: cache key construction/versioning, the read/fallback/write-through
sequence, and single-key invalidation. Does not own: deciding *when* data
is stale enough to invalidate (that's the writer's call — see
Dependencies) or computing the underlying value (that's still `Item`'s/
`PriceLog`'s own columns and associations).

## Dependencies

May call `Item`/`PriceLog` (a plain bulk `ActiveRecord` query on a cache
miss). Must never be called *from* a model — dependency direction is
Controller/Worker → Caching → Models, one-way, same as every other layer
in `.claude/styleguides/rails-layering.md`. Callers: `Api::V1::
InventoriesController`/`Api::V1::PriceHistoriesController` on the read
side, `PriceUpdateWorker` on the invalidate side.

## Rules

### MUST

- Read via `Rails.cache.read_multi` and write misses back via
  `Rails.cache.write_multi` — never a per-name `Rails.cache.fetch` in a
  loop. A per-name loop's fallback block runs once per miss, which
  reintroduces the N+1 query pattern caching was meant to remove.
- Construct keys as versioned arrays: `[<namespace>, <version_integer>,
  market_hash_name]` (e.g. `["item_price", 1, market_hash_name]`). Bump
  the version segment whenever the cached payload's shape changes —
  never reuse a version number for a differently-shaped value.
- Invalidate with a single `Rails.cache.delete(key)` per
  `market_hash_name` — no bulk/wildcard delete, no version-bump-instead-
  of-delete (see the ADR's rejected alternatives).
- Set an `expires_in:` safety-net TTL on every write (15 minutes for both
  `ItemPriceCache` and `PriceHistoryCache` today) — this is a bound on
  staleness if invalidation is ever missed, not the primary freshness
  mechanism.
- Only `PriceUpdateWorker` calls `.invalidate`, immediately after its
  existing successful transaction — never on a failed Steam response
  branch. If a future job writes `Item#current_price_cents` or a new
  `PriceLog` row, it must call the same `.invalidate` entry point.

### SHOULD

- Keep `PriceHistoryCache` scoped to the default/no-`since` request
  shape only; a request with an explicit `since` should bypass the cache
  and query `PriceLog` directly, rather than trying to extend the cache
  to an arbitrary, client-supplied time window (see ADR Context).

### MUST NOT

- Don't put cache read/write/invalidate logic directly on `Item` or
  `PriceLog` (as instance or class methods), and don't hide the same
  model-level placement behind a shared concern/module included into
  those models — either way, the orchestration still executes as the
  model, which `rails-layering.md` prohibits.
- Don't call a caching class from within `Item`/`PriceLog` themselves.
- Don't add a job-uniqueness gem (e.g. `sidekiq-unique-jobs`) for warmup
  deduplication — use a `Rails.cache.write(key, true, unless_exist: true,
  expires_in: ...)` flag instead (see the warmup pattern below).

## Warmup/Dedup Pattern

A request-triggered "warm this up now" enqueue (e.g.
`InventoriesController` enqueuing `PriceUpdateWorker` for an item with no
price yet, instead of waiting for `PriceScheduler`'s next hourly pass)
follows this shape, kept in the *calling* controller/worker, not in
`app/caching/` itself (it's about deduplicating an enqueue, not about the
cache-read-through pattern above):

1. Before enqueuing, `Rails.cache.write("<prefix>:#{id}", true,
   unless_exist: true, expires_in: <short TTL>)`.
2. Only enqueue if that write reports it actually set the value (i.e. no
   pending attempt was already registered).
3. Cap how many such enqueues a single request can trigger, tied to the
   relevant `Prop` rate-limit ceiling for whatever external call the
   enqueued job makes (see the ADR's Implementation Constraints for the
   current `PriceUpdateWorker`/`steam_price_rpm` numbers) — never enqueue
   more per request than could plausibly clear that ceiling anyway.

## Interaction With Other Layers

```text
Api::V1::InventoriesController#show          Api::V1::PriceHistoriesController#index
    ↓ ItemPriceCache.fetch_for(names)             ↓ PriceHistoryCache.fetch_for(names)  (no-`since` only)
    ↓ (miss → bulk Item query → write_multi)       ↓ (miss → bulk PriceLog query → write_multi)

PriceUpdateWorker#perform  (after successful transaction)
    ↓ ItemPriceCache.invalidate(market_hash_name)
    ↓ PriceHistoryCache.invalidate(market_hash_name)
```

## Testing

General RSpec mechanics (spec levels, `FactoryBot`, `Sidekiq::Testing.
fake!`) are governed by `.claude/styleguides/rspec-conventions.md`; this
section only adds what's specific to caching.

### MUST

- Assert cache hit/miss/invalidation against real `Rails.cache` state
  (`Rails.cache.exist?`/`Rails.cache.read` after the fact), not by mocking
  `Rails.cache` or stubbing `ItemPriceCache`/`PriceHistoryCache` — matches
  this codebase's existing preference for exercising a real backing
  service (see `price_update_worker_spec.rb`'s real-Redis-stream
  assertions) over mocking the exact thing under test.
- `ItemPriceCache`/`PriceHistoryCache` specs are unit specs (`spec/
  caching/`, no `type:` metadata), following `rspec-conventions.md`'s
  default mapping.
- Any request spec asserting "no DB hit on the second request" subscribes
  to `sql.active_record` via `ActiveSupport::Notifications` rather than
  mocking the model's query methods — the DB round-trip actually not
  happening is the thing being verified, not that a particular method was
  or wasn't called.

## Canonical Implementations

None yet — this is the first use of `Rails.cache`/`solid_cache` as an
explicit pattern in `app_fetcher` (Prop's use of `Rails.cache` for
rate-limiting, in `config/initializers/prop.rb`, predates this and
doesn't follow this pattern). The first implementation is tracked in
`.claude/plans/fetcher-price-caching.md`, expected at
`app_fetcher/app/caching/item_price_cache.rb` and
`app_fetcher/app/caching/price_history_cache.rb`.

## Related ADR

`.claude/adr/fetcher/price-cache-invalidation.md`
