---
description: Rails.cache/solid_cache conventions in app_fetcher — dedicated app/caching/ classes, versioned keys, by-key invalidation owned by the writer (worker or service), three variants (bulk read-through, single-key read-through, TTL-only), and the warmup/dedup pattern for not-yet-priced items.
---

# Caching (`app/caching/`)

See `agent/adr/fetcher/price-cache-invalidation.md` for why this is a
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

Three variants, chosen by how the underlying data goes stale and how
callers key into it:

- **Read-through + explicit invalidation** (`.fetch_for`/`.invalidate`):
  data changes at a known, infrequent cadence driven by a background job
  this codebase controls (here: `PriceUpdateWorker`, hourly at most per
  item), so that job can call `.invalidate` the moment it writes. Read far
  more often than it changes. Callers key in **bulk** — a request-shaped
  array of ids, not one at a time.
- **Single-key read-through + invalidation** (`.fetch`/`.invalidate`): the
  same staleness story as the bulk variant above (a codebase-controlled
  writer calls `.invalidate` right after it writes), but every caller only
  ever needs **one** key per call — there's no request shape that would
  benefit from a bulk `read_multi` across many steam_ids/users at once.
  Use this instead of the bulk variant when a cached resource is
  inherently scoped to "the current request's one id," never a list.
- **TTL-only** (`.read`/`.write`): data changes due to activity this
  codebase has no write path into, so there's no event to hook an
  explicit `.invalidate` call to — staleness is bounded purely by a short
  TTL instead. `ItemListCache` is this variant's current example
  (keyed by a SHA256 hash of normalized filter/sort/pagination params —
  see Rules — with no single caller-supplied id driving it).
  `UserInventoryCache` used to be its example before `ItemListCache`
  existed, but moved to the single-key read-through variant once the
  weekly sync + manual refresh (`UserInventorySyncService`, see
  `agent/adr/fetcher/cross-scenario-service-layer.md`) gave it a real
  write path to invalidate against.

Don't reach for any variant for data that changes on every request, or
where staleness of even a few seconds would be user-visible in a way that
matters.

## Structure

- One class per cached resource, under `app/caching/`, top-level (not
  namespaced under `Steam::` — like parsers, builders, services, workers,
  and schedulers, these stay flat even when they cache Steam-domain
  data): `ItemPriceCache`, `PriceHistoryCache` (bulk read-through +
  invalidation), `UserInventoryCache` (single-key read-through +
  invalidation).
- Each class is a plain Ruby class with only class-level methods (`class
  << self; extend T::Sig; ...; end` for private ones, per
  `agent/styleguides/ruby-sorbet.md`) — never instantiated.

## Interface

Exactly two public class methods per caching class, named by variant (see
When to Use) — never mix pairs from different variants on one class:

- **Bulk read-through + invalidation**: `.fetch_for(market_hash_names)` —
  bulk read, returns the same shape the caller would have gotten from a
  direct query (a `market_hash_name => data` mapping); callers should not
  need to know whether a given name was a cache hit or a DB fallback.
  Paired with `.invalidate(market_hash_name)` — single-key delete; returns
  nothing meaningful, callers don't branch on its result. A class using
  this pair doesn't expose `.read`/`.write`/`.fetch` primitives directly —
  collapsing every call site to `fetch_for` keeps the bulk-read-avoids-N+1
  property (see Rules) from being accidentally bypassed by a future
  one-off caller.
- **Single-key read-through + invalidation**: `.fetch(id)` — single-key
  read with DB fallback: returns the cached value, or on a miss, queries
  the DB directly (a single query, not `read_multi`/`write_multi` — there
  is only ever one key per call, so the bulk machinery doesn't apply) and
  writes the result back with the class's safety-net TTL before
  returning. Paired with `.invalidate(id)` — single-key delete, same
  contract as the bulk variant's. A class using this pair doesn't expose
  `.read`/`.write`/`.fetch_for` directly either.
- **TTL-only**: `.read(id)` — single-key read, returns the cached value or
  `nil` on a miss; no DB fallback, no write-through. Paired with
  `.write(id, value)` — single-key write with the class's TTL; the caller
  decides when to call it (typically after successfully fetching the
  value from its real source), it's not triggered by a background job's
  invalidation hook.

No other public methods on any variant.

## Responsibilities

Owns: cache key construction/versioning, the read/fallback/write-through
sequence, and single-key invalidation. Does not own: deciding *when* data
is stale enough to invalidate (that's the writer's call — see
Dependencies) or computing the underlying value (that's still `Item`'s/
`PriceLog`'s own columns and associations).

## Dependencies

May call `Item`/`PriceLog`/`UserInventory`/`UserInventoryItem` (a plain
query on a cache miss — bulk for the bulk variant, single-record for the
single-key variant). Must never be called *from* a model — dependency
direction is Controller/Worker/Service → Caching → Models, one-way, same
as every other layer in `agent/styleguides/rails-layering.md`. Callers:
`Api::V1::ItemPricesController#dynamics`/`#trend` and
`#history`'s 30-day branch (explicit `period=30d` or the absent-period
default), plus
`UserInventorySyncService` (internally, to resolve known vs. missing
items) on the read side for the bulk variant (`ItemPriceCache`/
`PriceHistoryCache`/`ItemTrendCache`), invalidated by `PriceUpdateWorker`
after a successful price update; `Api::V1::InventoriesController` (warm
path) on the read side and `UserInventorySyncService` on the invalidate
side for the single-key variant (`UserInventoryCache`) — mirroring
`PriceUpdateWorker`'s role for the bulk variant, just from the
cross-Scenario service layer instead of a worker (see
`agent/adr/fetcher/cross-scenario-service-layer.md`).

## Rules

### MUST

- **Bulk variant only**: read via `Rails.cache.read_multi` and write
  misses back via `Rails.cache.write_multi` — never a per-name
  `Rails.cache.fetch` in a loop. A per-name loop's fallback block runs
  once per miss, which reintroduces the N+1 query pattern caching was
  meant to remove. This doesn't apply to the single-key variant — there's
  only ever one key per call, so a plain `Rails.cache.fetch(key,
  expires_in: TTL) { ... }` is correct there, not a bypass of this rule.
- Construct keys as versioned arrays: `[<namespace>, <version_integer>,
  id]` (e.g. `["item_price", 1, market_hash_name]`,
  `["user_inventory", 2, steam_id]`). Bump the version segment whenever
  the cached payload's shape changes — never reuse a version number for a
  differently-shaped value.
- When a cached resource has no single natural identifier — a result
  keyed by several independent, caller-supplied filter/sort inputs
  rather than one id like `market_hash_name`/`steam_id` — normalize the
  inputs *before* building the `id` component, not after: sort any
  array-valued input and case-fold any string input, so two requests
  differing only in param order or case still resolve to the same key.
  Then use `Digest::SHA256.hexdigest` of that normalized representation
  as `id` in the same versioned-array shape above, e.g.
  `["items_catalog", 1, Digest::SHA256.hexdigest(normalized_filters.to_json)]`.
  Hashing an un-normalized input first would defeat the point — two
  equivalent-but-differently-ordered requests would hash to different
  digests and silently fragment the cache. Only include inputs that
  actually affect the cached payload in what gets normalized and hashed —
  a param a controller accepts but the resource's query object never
  reads (a confirmed no-op for that endpoint, not an oversight) must be
  left out entirely; including it would fragment the cache between two
  requests that are actually equivalent, for no benefit. `ItemListCache`
  happens to include every param it accepts (`search`/`category`/
  `rarity`/`stattrak`/`sort`) because each one genuinely does affect that
  endpoint's result, not because accepting a param obligates a class in
  this layer to fold it into the key unconditionally.
- When a cached resource has **both** a single natural identifier
  (`market_hash_name`/`steam_id`) *and* one or more independent,
  caller-supplied request-shaping params layered on top of that same id
  — a detail-style resource identified by an id, with request variants on
  top (e.g. a date range, an embedded sub-collection's own sort/page) —
  keep the natural id as its own array element and append a hash of the
  remaining inputs, normalized the same way as above:
  `[<namespace>, <version_integer>, id,
  Digest::SHA256.hexdigest(normalized_remaining_inputs.to_json)]`, a
  4-element array rather than either of the two 3-element shapes above.
  Keeping `id` visible, not folded into the hash, matters specifically
  here: unlike the no-natural-identifier case, a real caller or debugger
  inspecting cache entries for one resource can still find every variant
  of it by `id` alone, which a key that's pure hash can't offer.
- Invalidate with a single `Rails.cache.delete(key)` per id — no
  bulk/wildcard delete, no version-bump-instead-of-delete (see the ADR's
  rejected alternatives).
- Set an `expires_in:` safety-net TTL on every write (15 minutes for both
  `ItemPriceCache` and `PriceHistoryCache` today) — this is a bound on
  staleness if invalidation is ever missed, not the primary freshness
  mechanism. Pick the single-key variant's TTL deliberately per class,
  same as the bulk variant — don't copy another class's number without
  re-deriving it for the new data's own staleness tolerance.
- Only the writer named in Dependencies calls `.invalidate` for a given
  class, immediately after its own successful write — never on a failed
  external-call branch. `PriceUpdateWorker` owns
  `ItemPriceCache`/`PriceHistoryCache`'s invalidation;
  `UserInventorySyncService` owns `UserInventoryCache`'s. If a future
  writer is introduced for either resource, it must call the same
  `.invalidate` entry point rather than leaving a second, uninvalidated
  write path.
- For a TTL-only class, the `expires_in:` on `.write` *is* the primary
  freshness mechanism (there's no `.invalidate` to fall back on) — pick it
  deliberately; don't copy a safety-net TTL from a read-through variant,
  where invalidation (not the TTL) is the primary mechanism.

### SHOULD

- Keep `PriceHistoryCache` scoped to the 30-day window only; a
  `period=30d` request (or the query object's default `30d`) may use it,
  while any other range bypasses the cache and queries `PriceLog`
  directly, rather than trying to extend the cache to an arbitrary,
  client-supplied time window (see ADR Context). The controller owns
  that branch and must normalize an absent/blank `period` to the default
  `30d` before choosing it, so the implicit and explicit paths share the
  cache; a history query object never touches the cache.

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
`ItemPricesController#dynamics` enqueuing `PriceUpdateWorker` for an
item with no price yet, instead of waiting for `PriceScheduler`'s next
hourly pass) follows this shape. It never belongs in `app/caching/`
itself (it's about deduplicating an enqueue, not about the
cache-read-through pattern above). When the calling controller would
otherwise own the cap, TTL, key format, and enqueue loop, put the whole
operation in a dedicated service — `PriceWarmupService` is the canonical
shape. A worker/controller may still own a genuinely trivial one-line
variant; don't extract a service for a single `perform_async` with no
policy attached.

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
Api::V1::ItemPricesController#dynamics       Api::V1::ItemPricesController#history
    ↓ ItemPriceCache.fetch_for(names)             ↓ PriceHistoryCache.fetch_for(names)  (explicit period=30d only)
    ↓ (miss → bulk Item query → write_multi)       ↓ (miss → bulk PriceLog query → write_multi)
    ↓ PriceWarmupService.call(priced_items.values)
    ↓ (nil-price → cap 20 → Rails.cache dedup → PriceUpdateWorker.perform_async)

Api::V1::ItemPricesController#trend
    ↓ ItemTrendCache.fetch_for(names)
    ↓ (miss → bulk Item + PriceLog query → cursor downsample → write_multi)

PriceUpdateWorker#perform  (after successful transaction)
    ↓ ItemPriceCache.invalidate(market_hash_name)
    ↓ PriceHistoryCache.invalidate(market_hash_name)
    ↓ ItemTrendCache.invalidate(market_hash_name)

Api::V1::InventoriesController#show (warm path)
    ↓ UserInventoryCache.fetch(steam_id)
    ↓ (miss → UserInventory/UserInventoryItem/Item query → write)

UserInventorySyncService.call  (after UserInventory.sync! succeeds)
    ↓ UserInventoryCache.invalidate(steam_id)
```

## Testing

General RSpec mechanics (spec levels, `FactoryBot`, `Sidekiq::Testing.
fake!`) are governed by `agent/styleguides/rspec-conventions.md`; this
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

- Bulk read-through + invalidation: `app_fetcher/app/caching/item_price_cache.rb`,
  `app_fetcher/app/caching/price_history_cache.rb`,
  `app_fetcher/app/caching/item_trend_cache.rb`.
- Single-key read-through + invalidation: `app_fetcher/app/caching/user_inventory_cache.rb`.
- TTL-only: `app_fetcher/app/caching/item_catalog_cache.rb` — the
  no-single-natural-identifier key shape (hash of normalized filter/sort/
  pagination params).
- TTL-only, hybrid key (natural id + hashed remaining inputs): no current
  implementation — `InventoryDetailCache`
  (`agent/plans/public-inventory-endpoints.md`) will be the first.

`ItemPriceCache`/`PriceHistoryCache` are tracked in
`agent/plans/fetcher-price-caching.md`; `ItemTrendCache` is tracked in
`agent/plans/dashboard-api-redesign.md`; `UserInventoryCache`'s
single-key read-through shape is tracked in
`agent/plans/user-inventory-persistence.md`; `ItemListCache` is
tracked in `agent/plans/item-catalog-query-refactor.md`. Prop's use of
`Rails.cache` for rate-limiting, in `config/initializers/prop.rb`,
predates this styleguide and doesn't follow any of the three variants.

## Related ADR

- `agent/adr/fetcher/price-cache-invalidation.md`
- `agent/adr/fetcher/cross-scenario-service-layer.md` — why
  `UserInventoryCache`'s invalidation is owned by `UserInventorySyncService`
  rather than a worker.
