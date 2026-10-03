# Cache Reads Through a Dedicated Caching Layer, Invalidated By Key From PriceUpdateWorker

## Status

Accepted

## Context

`GET /api/v1/inventories/me` and `POST /api/v1/price_histories` hit
Postgres on every request (an `Item` lookup, and a `PriceLog` lookup
followed by an in-Ruby `group_by`), even though the values they return
change at most once per hour per item — `PriceScheduler` only re-enqueues
an item once `updated_at < 1.hour.ago`. `solid_cache` is already declared
in `app_fetcher`'s `Gemfile` but was never installed or configured
(no `config/solid_cache.yml`, no cache DB, no `cache_store` set in any
environment).

Two existing styleguides constrain where the fix can live, and neither
has room for it as originally drafted:

- `.claude/styleguides/rails-layering.md` restricts models to
  "persistence + validations only... no orchestration," and explicitly
  rules out "multi-step orchestration, conditional persistence" directly
  on a model. A cache read-through — read cache, conditionally query the
  DB on a miss, conditionally write the cache — is exactly that shape,
  regardless of the absence of external I/O.
- `.claude/styleguides/fetcher/internal-api-controllers.md` frames a
  controller action's one collaborator as either "a `Steam::Client` call,
  or a plain ActiveRecord query." A cache-read-with-DB-fallback is
  neither. It also doesn't fit `.claude/styleguides/fetcher/
  architecture-layers.md`'s ingestion-pipeline scenario map, which
  explicitly excludes "code that only reads already-persisted data for a
  response" from its scope — caching is orthogonal to that map, not a
  fourth ingestion scenario.
- Invalidation has to be triggered from `PriceUpdateWorker`, which is
  neither a controller nor a model — so placing cache logic only in a
  controller (even if that were otherwise acceptable) can't cover the
  write/invalidate side without duplicating key-construction logic in an
  unrelated file.

Separately, the task requires a **lazy warmup** path: when
`InventoriesController#show` sees items with no price yet
(`current_price_cents IS NULL`), it should trigger `PriceUpdateWorker`
immediately rather than wait for `PriceScheduler`'s next hourly pass. This
interacts with an existing constraint: `Prop.throttle!`
(`config/initializers/prop.rb`) enforces a **global** `steam_price_rpm`
(20/min) and `steam_price_rpd` (1000/day) budget, shared with
`PriceScheduler`'s own routine refreshes, on the exact same `:steam_price`
limit key `fetch_item_price` uses (`lib/steam/client.rb`). A rate-limited
`PriceUpdateWorker` run fails silently today — logged warning, no
exception, so Sidekiq's `retry: 5` never engages — so any warmup design
has to assume attempts beyond that budget are simply lost, not retried.

## Decision

Introduce a new `app/caching/` layer: plain Ruby classes, not
`ActiveRecord` models and not Sidekiq workers, one per cached resource —
`ItemPriceCache` and `PriceHistoryCache`. Each exposes exactly two class
methods:

- `.fetch_for(market_hash_names)` — bulk read: `Rails.cache.read_multi`
  across per-name keys, a single bulk `ActiveRecord` query for whatever
  missed, then `Rails.cache.write_multi` to populate the cache before
  returning. Never a per-key `fetch` in a loop — that reintroduces N+1 on
  a cold cache.
- `.invalidate(market_hash_name)` — a single `Rails.cache.delete` by key.

These classes may call `Item`/`PriceLog` (read on a miss) but are never
called *from* those models — dependency direction stays Controller/Worker
→ Caching → Models, the same one-way shape
`.claude/styleguides/rails-layering.md` already requires between its
existing layers; this is a new named layer slotted into that existing
direction, not an exception to it.

Cache keys are versioned arrays: `[<namespace>, <version_integer>,
market_hash_name]`. Bump the version segment when the cached payload's
shape changes, instead of a manual cache-wide flush.

Invalidation is explicit, by key, and owned solely by `PriceUpdateWorker`
— called immediately after its existing successful transaction (`price_
log.save!` + `item.update!`), never when the wrapped Steam call fails.
After a successful transaction, the worker re-warms all three caches with
a uniform `invalidate(name)` → `fetch_for([name])` sequence:
`ItemPriceCache`, `PriceHistoryCache`, and `ItemTrendCache`. Because the
transaction has already committed before either call, `fetch_for` always
reads fresh data. This eliminates the cache-miss window that a bare
`invalidate`-only approach leaves between invalidation and the next
request.

TTL (15 minutes, all caches) exists only as a safety net for a missed or
buggy invalidation, not as the primary freshness mechanism.

`price_histories` caching covers only the no-`since` (default-window)
request shape; any request with an explicit `since` bypasses the cache
and queries `PriceLog` directly, unchanged from today — this keeps
invalidation a single by-key delete instead of needing a scheme for an
otherwise-unbounded `since`-keyed cache space.

Lazy warmup, triggered from `InventoriesController#show` for items with
`current_price_cents.nil?`, is capped at **20 items per request** —
exactly `steam_price_rpm`'s own ceiling, not an arbitrary larger number —
and deduplicated via `Rails.cache.write(key, true, unless_exist: true,
expires_in: 90.seconds)` before calling the existing
`PriceUpdateWorker.perform_async`, rather than a job-uniqueness gem.

## Alternatives Considered

### Alternative: Class methods on `Item`/`PriceLog`

The original design: `Item.cached_prices_for`, `PriceLog.cached_history_
for`, etc., as class methods directly on the models.

Rejected because this is exactly the "multi-step orchestration...
conditional persistence" `rails-layering.md`'s MUST NOT rule prohibits on
a model — read-cache → conditionally-query-DB → conditionally-write-cache
is orchestration, not persistence/validation, regardless of there being
no external I/O involved.

### Alternative: A shared `Cacheable` concern mixed into both models

Same logic, organized as a module included into `Item` and `PriceLog`
instead of written inline.

Rejected because it doesn't change *where* the orchestration executes —
it's still model-layer code via `extend`, just packaged differently. The
rule is about what a model does, not how the code defining it is
arranged.

### Alternative: Cache logic inline in the controllers, duplicated into the worker for invalidation

Rejected on two counts: `internal-api-controllers.md` already requires
controllers stay thin, delegating anything beyond a single trivial model
lookup; and invalidation must be triggered from `PriceUpdateWorker`,
which isn't a controller — a controller-only placement can't own both
the read and the invalidate side of the same cache without duplicating
key-construction logic across unrelated files.

### Alternative: TTL-only cache, no explicit invalidation

Rely purely on a short TTL for both caches instead of an explicit delete.

Rejected as insufficiently fresh for this app's actual purpose (the
dashboard reflecting prices "as of the last worker run"): a pure TTL
leaves a window, up to the full TTL, where a price that just changed
wouldn't show up at all. Explicit point invalidation was confirmed as the
intended mechanism for both current-price and price-history caching, not
just current-price.

### Alternative: Version-bump invalidation instead of explicit delete

Bump a per-item version counter on update, so old cache entries are
silently abandoned (and eventually evicted by `solid_cache`) rather than
deleted.

Rejected for this phase: it doesn't satisfy the literal requirement that
the fetcher itself invalidate the cache by key, and it leaves orphaned
rows accumulating in the cache store until `solid_cache`'s own eviction
catches up. An explicit delete is simpler to reason about here.

### Alternative: `sidekiq-unique-jobs` for warmup dedup

A dedicated job-uniqueness gem would dedupe `PriceUpdateWorker.perform_
async` enqueues more robustly (cross-process locks, configurable
uniqueness windows) than a cache flag.

Rejected for this phase: it's a new dependency for a problem `solid_cache`
— already being introduced for this task anyway — solves adequately with
a simple write-once flag. Revisit only if the flag-based approach proves
insufficient in practice.

## Consequences

### Positive

- Repeated requests for known prices/history stop hitting Postgres,
  cutting DB load and response latency on the dashboard's two hottest
  read paths.
- Cache logic for each resource lives in exactly one place, reusable by
  both the read side (controllers) and the write side
  (`PriceUpdateWorker`), instead of being duplicated or awkwardly split
  across layers that weren't built to hold it.
- The new `app/caching/` layer is orthogonal to the existing
  ingestion-pipeline layer map (`architecture-layers.md`) — a read-path
  concern, not a fifth ingestion scenario competing with parsers/builders/
  workers/schedulers for meaning.

### Negative

- A new top-level `app/` layer to learn, on top of the existing
  parsers/builders/workers/schedulers/controllers/models set.
- Bulk read/write-through logic (`read_multi` + fallback query +
  `write_multi`) is more code than a naive per-key `Rails.cache.fetch`,
  and easy to get subtly wrong around "no matching `Item` row" vs.
  "not yet cached."
- `price_histories` caching only covers the default-window request shape;
  any custom `since` still queries Postgres directly every time —
  deliberately narrow for this phase, not a general-purpose history
  cache.

### Risks

- The warmup cap (20/request) and dedup TTL (90s) bound a single
  request's impact on the shared `steam_price_rpm` budget, but do not
  protect the shared `steam_price_rpd` (1000/day) budget from gradually
  being consumed by warmup traffic across many concurrent users, at the
  expense of `PriceScheduler`'s own routine refresh of already-known
  items. Splitting Prop's rate-limit buckets by traffic source (scheduled
  vs. request-triggered) would close this but is out of scope here.
- If `PriceUpdateWorker`'s invalidation call is ever skipped (a bug, or a
  future direct write to `Item`/`PriceLog` bypassing the worker), the
  15-minute safety-net TTL bounds, but does not eliminate, the resulting
  staleness window.

## Implementation Constraints

- `ItemPriceCache`/`PriceHistoryCache` may call `Item`/`PriceLog` (read on
  a cache miss) but must never be called *from* those models —
  Controller/Worker → Caching → Models stays one-directional.
- Only `PriceUpdateWorker` calls `.invalidate` and `.fetch_for` as a
  re-warm pair. If a future writer of `Item#current_price_cents`/`PriceLog`
  rows is introduced, it must follow the same `invalidate + fetch_for`
  sequence on all three caches — don't let a second write path skip the
  re-warm and reintroduce a cache-miss window.
- Cache keys are versioned arrays (`[namespace, version,
  market_hash_name]`); bump the version segment on any change to the
  cached payload's shape instead of a manual full-cache flush.
- The `Rails.cache.write(..., unless_exist: true)` dedup flag is scoped
  per item, TTL'd at 90 seconds, and is not a substitute for a real
  distributed lock — it only needs to reduce duplicate enqueues under
  normal request cadence, not guarantee exactly-once semantics under
  adversarial concurrency.
- Lazy warmup enqueues at most 20 `PriceUpdateWorker.perform_async` calls
  per request, matching (not exceeding) `steam_price_rpm`'s own ceiling —
  don't raise this cap without revisiting the shared daily-budget risk
  above.

## Related

- `.claude/styleguides/fetcher/caching.md`
- `.claude/styleguides/rails-layering.md`
- `.claude/styleguides/fetcher/architecture-layers.md`
- `.claude/styleguides/fetcher/internal-api-controllers.md`
- `.claude/styleguides/fetcher/background-jobs.md`
- `.claude/adr/fetcher/price-updates-via-redis-stream.md` — the other
  side effect `PriceUpdateWorker` triggers after a successful update
- `app_fetcher/config/initializers/prop.rb` — the shared rate-limit
  budget this decision's warmup cap is derived from
- `.claude/plans/fetcher-price-caching.md`
