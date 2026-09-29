---
status: closed-not-implemented
app: fetcher
goal: Extend app_fetcher's existing per-item price-history cache to serve a bounded, downsampled 1-year window alongside today's 30-day raw default — the backend building block for Задача 3's "time machine" simulation, without any whole-inventory aggregation or real-time infrastructure
created: 2026-09-29
---

## Resolution: closed without implementation

Decided, after the design below was fully worked out (including a real
`styleguides-check` finding — see "Missing Styleguides" further down),
**not to build any of this for now.** `POST /api/v1/price_histories`
already supports an explicit `since` param that queries `PriceLog`
directly for *any* period, uncached — that existing, unmodified path is
enough to answer "price history a year back" today. The entire reason
this plan needed a new cached/bucketed `period: "1y"` variant was
performance/scale (bounding point count, avoiding a DB hit every
request) — not a missing capability. Given no real usage at that scale
exists yet, paying that cost now, along with the `caching.md`
multi-variant-cache-key question it would have reopened, wasn't judged
worth it.

This plan is kept as-is (not deleted) because the design work — the
rejection of a whole-inventory hash-cached simulation endpoint in favor
of a per-item extension, the cursor-based bucketing algorithm avoiding
`sumAsOfEachHour`'s O(H×M) trap, the exact styleguide gap this would
have hit — is real, hard-won reasoning worth not re-deriving from
scratch if long-window caching genuinely becomes necessary later (e.g.
once `since`'s uncached direct-query cost is actually observed to be a
problem). Задача 3 (Машина времени) is closed for this session's
3-phase rearchitecture without a code change — "the answer was already
in the codebase" is itself the outcome, not a placeholder for later.

---

# Development Plan (not implemented — see Resolution above)

## Goal

Give `app_fetcher` the ability to serve a per-item, day-bucketed price
history over a full year (`period: "1y"`), cached the same way the
existing 30-day default already is. This is the entire backend surface
"Задача 3 — Машина времени" needs: computing "what would my current
inventory have been worth in the past" becomes a client-side sum over
per-item series once those series are available for a long-enough
window — that summation, and any UI for it, is explicit follow-up work,
not this plan.

## Why this shape, not a whole-inventory simulation endpoint

Gemini's original brainstorm framed this as a new
`GET /api/v1/portfolio/simulation?period=1y` endpoint: fetch the user's
current inventory, sum per-item history server-side into one
total-value-over-time series, hard-cache the result keyed by a hash of
the inventory's composition. Reached and rejected through live design
discussion this session, for two compounding reasons:

- A hash-of-composition cache key is a new keying shape with zero
  precedent in this codebase, and sits close enough to
  `.claude/adr/fetcher/price-cache-invalidation.md`'s rejected
  "version-bump invalidation" alternative to warrant real scrutiny (on
  balance it's closer to `UserInventoryCache`'s already-accepted
  TTL-only shape — there's no invalidation signal for a user's Steam
  trades either — but it's still new complexity this plan doesn't need).
- Summing N items × M days server-side, for an aggregate that's unique
  per user (no cross-user cache reuse the way a per-item cache gets), is
  a real performance problem with no existing precedent to lean on.
  Aggregation across items already happens client-side today
  (`app_core/app/frontend/dashboard/utils/portfolioSeries.js`) for the
  24h/7d/30d ranges — extending that to a longer window is smaller,
  reuses working code, and doesn't need a new backend concept.

What's actually missing today, confirmed via research, is much
narrower: `PriceHistoryCache` only ever returns **raw, un-bucketed**
points for its one hardcoded 30-day window — there's no backend
equivalent of the frontend's carry-forward bucketing
(`bucketing.js`'s `bucketByHour`/`sumAsOfEachHour`) at any resolution
coarser than "every logged point." That's the actual gap this plan
closes — one more cacheable window, not a new architecture.

**Real-time was also considered and explicitly dropped.** The
underlying data changes at most hourly (`PriceScheduler`'s cron) and
often less (`Prop`'s shared, global `steam_price_rpm`/`steam_price_rpd`
budget), so pushing updates via `prices_stream` would buy negligible
real freshness over ordinary request/reload cadence for real
architectural cost. `prices_stream` stays unconsumed, exactly as
`.claude/adr/fetcher/price-updates-via-redis-stream.md` already
anticipated.

## Expected Behavior

**Normal behavior**

- `POST /api/v1/price_histories` with `period: "1y"` (and no `since`)
  returns, per requested `market_hash_name`, one point per day for the
  last 365 days — each point is that item's last known price at or
  before that day's boundary, carried forward from the most recent
  earlier log if none fall exactly on that day (mirrors the *concept*
  of `bucketByHour`'s carry-forward, implemented fresh in Ruby).
- Repeated requests with `period: "1y"` for the same items serve from
  cache (no new `PriceLog` query) until invalidated.
- A price update (`PriceUpdateWorker`'s existing successful branch)
  invalidates **every** cached period for that item — default (30-day
  raw) and `1y` alike — not just the default, the way it does today.
- No `period` (and no `since`) behaves exactly as today: the 30-day raw
  default.
- An explicit `since` still bypasses caching entirely and queries
  `PriceLog` directly, unchanged — `since` and `period` are not
  meaningfully combined; if both are present, `since` wins (matches the
  existing branch order: the `since` check happens first).

**Edge cases**

- An item whose earliest price log falls partway through the 1-year
  window: buckets before that log carry no value and are omitted
  (mirrors `sumAsOfEachHour`'s existing "only emit a bucket once there's
  *some* data" behavior) — not a zero, not an error.
- An item with a price log from *before* the window start but none
  inside the window yet: the window's early buckets still carry forward
  that pre-window price rather than showing no data, since the actual
  question being answered ("what was this item worth on day X") doesn't
  care whether the most recent known price happens to be inside or
  outside the requested window.
- An item (or name) with zero price logs at all: empty array, same as
  today's default-window behavior for that case.
- `period` present but not one of the supported values (today, just
  `"1y"`): `:bad_request` with `{message: "..."}"`, matching this
  controller's existing JSON error shape convention — not a silent
  fallback to the default window.

**Must remain unchanged**

- The default (no `period`, no `since`) response shape and caching
  behavior.
- The explicit-`since` response shape and its uncached, direct-query
  behavior.
- `PriceUpdateWorker`'s own transaction/publish/failure-handling logic —
  its one new obligation is that its existing
  `PriceHistoryCache.invalidate(name)` call now clears more than one
  cached entry, which happens inside `PriceHistoryCache` itself; the
  worker's own call site doesn't change.

## Scope

### In Scope

- `PriceHistoryCache`: a `period:` keyword argument on `.fetch_for`
  (defaulting to today's implicit shape), a small period → bucket-size
  lookup table (just `"1y" => 1.day` for now, structured so a future
  period is a one-line addition), a cursor-based (not per-bucket
  rescanning) bucketing implementation, and a versioned cache key that
  includes the period segment.
- `PriceHistoryCache.invalidate`: clears every known period's cached
  entry for a `market_hash_name`, not just the default.
- `Api::V1::PriceHistoriesController#index`: accept and validate an
  optional `period` param (only in the no-`since` branch), reject an
  unsupported value explicitly.
- Test coverage for all of the above.

### Out of Scope

- Any new `Api::V1::` endpoint, any "simulation"/"portfolio" naming, any
  whole-inventory aggregation, any hash-of-composition caching — see
  "Why this shape" above.
- Any `app_core`/frontend change — extending `chartConfig.js`'s
  `RANGE_MS`/`RANGES` with a `1y` option, wiring a request for it, and
  fixing `sumAsOfEachHour`'s own algorithmic issue (see Risks) are all
  explicit follow-up work, not this plan.
- Real-time / `prices_stream` consumption.
- Any period other than `1y` (e.g. a `5y` case discussed hypothetically
  this session) — the lookup-table design makes adding one cheap later,
  but only `1y` is being built now.
- Any change to `price_logs` retention/pruning.

## Implementation Approach

**`PriceHistoryCache` gains a `period:` dimension, not a new class.**
Per `.claude/styleguides/fetcher/caching.md`'s existing shape (bulk
read-through with a DB fallback, by-key invalidation, no other public
methods), this stays inside the existing class rather than becoming a
new one — it's the same cache serving a second, coarser-grained view of
the same underlying data, not a different concern.

- `PERIODS = { "1y" => { window: 365.days, bucket: 1.day } }` — a
  constant lookup table. `DEFAULT_PERIOD = "default"` names today's
  existing 30-day-raw shape so it can be addressed the same way as any
  other period internally (cache key, invalidation loop), without
  changing its actual behavior.
- `.fetch_for(market_hash_names, period: DEFAULT_PERIOD)` — cache key
  becomes `["price_history", CACHE_KEY_VERSION, market_hash_name,
  period]`. For `period == DEFAULT_PERIOD`, the fallback path on a miss
  is byte-for-byte what exists today (windowed raw query). For a known
  non-default period, the fallback path instead: queries **all** of that
  item's `price_logs` (ascending by `created_at`, no lower bound — see
  Assumptions for why an unbounded-per-item query is acceptable here),
  then buckets them via a new private `bucket_points` method.
- `bucket_points(logs, window:, bucket_size:)` — walks bucket boundaries
  from `Time.current - window` to `Time.current` in `bucket_size` steps,
  advancing a single cursor into the (already sorted) logs array forward
  only, never rescanning from the start. This is a deliberate response
  to a real algorithmic trap identified this session in the frontend's
  own `bucketByHour`/`sumAsOfEachHour` (which rescans each item's point
  list from index 0 on every bucket — O(bucket-count × log-count) per
  item, tolerable at 30-day/hourly scale but not at a full year) — the
  new Ruby implementation is written cursor-based (O(bucket-count +
  log-count) per item) from the start, not as a later fix.
- `.invalidate(market_hash_name)` — loops over `[DEFAULT_PERIOD] +
  PERIODS.keys` and deletes each period's cache key. `PriceUpdateWorker`
  itself doesn't change — it already calls
  `PriceHistoryCache.invalidate(item.market_hash_name)` once; that one
  call now clears more entries internally.

**`Api::V1::PriceHistoriesController#index`.** Inside the existing
`else` branch (no explicit `since`): read `params[:period]`, default to
`PriceHistoryCache::DEFAULT_PERIOD` if blank, validate it's either the
default or a key in `PriceHistoryCache::PERIODS` — render
`:bad_request` with `{message: "..."}` otherwise (matching this
controller's existing error shape) — then call `PriceHistoryCache
.fetch_for(names, period:)`. Still exactly one collaborator call per
action, per `internal-api-controllers.md`.

## Files To Modify

- `app_fetcher/app/caching/price_history_cache.rb` — add `period:`
  support to `.fetch_for`, the `PERIODS` lookup table, the cursor-based
  `bucket_points` private method, and the multi-period `.invalidate`.
- `app_fetcher/app/controllers/api/v1/price_histories_controller.rb` —
  parse/validate `period`, pass it through.
- `app_fetcher/spec/caching/price_history_cache_spec.rb` — extend with
  `period: "1y"` scenarios.
- `app_fetcher/spec/requests/api/v1/price_histories_spec.rb` — extend
  with `period` scenarios (happy path, unsupported value, `since`
  taking precedence when both given).
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — extend the
  existing invalidation assertion to confirm the `1y` cache entry is
  also cleared, not just the default (regression-guarded, not just
  assumed from `PriceHistoryCache`'s own unit coverage).

## Files To Create

None — this plan adds no new table, model, worker, scheduler, or
controller; it extends two existing files.

## Test Plan

- **`PriceHistoryCache` (unit, extending existing spec)**:
  `period: "1y"` on a cold cache hits the DB once and returns one point
  per day for a window, with prices carried forward correctly across a
  gap in logs; a log dated before the window start still seeds
  carry-forward for the window's early buckets; an item with no logs at
  all returns `[]`; a warm `1y` cache serves without a DB hit;
  `.invalidate` clears both the default and `1y` entries for a name —
  a subsequent `fetch_for` at either period is a genuine miss.
- **`Api::V1::PriceHistoriesController` (request, extending existing
  spec)**: `period: "1y"` happy path returns the expected point shape;
  an unsupported `period` value returns `:bad_request` with a message;
  supplying both `since` and `period` behaves as `since`-only
  (regression-style check of precedence); default (neither param)
  behavior unchanged.
- **`PriceUpdateWorker` (unit, extending existing spec)**: after a
  successful price update, both the default *and* the `1y` cache
  entries for that item are gone (pre-warm both, run the worker, assert
  both misses) — extends the existing real-cache-state assertion style
  rather than trusting `PriceHistoryCache`'s own spec alone to prove the
  integration.
- **Regression**: existing default-window and explicit-`since` examples
  in both specs must keep passing unmodified in shape.

## Implementation Steps

1. TDD `PriceHistoryCache`'s `bucket_points` + `period:`-aware
   `.fetch_for` against `spec/caching/price_history_cache_spec.rb`,
   starting with the simplest case (dense daily logs across the whole
   window) before the gap/carry-forward/pre-window-seed edge cases.
2. TDD the multi-period `.invalidate` against the same spec file.
3. TDD `Api::V1::PriceHistoriesController#index`'s `period` handling
   (valid, invalid, precedence-vs-`since`) against its request spec.
4. Extend `price_update_worker_spec.rb` to assert both cache periods
   are invalidated after a successful update.
5. Full `app_fetcher` suite; `rubocop`; `srb tc` (informational, not
   CI-blocking, per established precedent this session).

## Verification

- `bundle exec rspec spec/caching/price_history_cache_spec.rb
  spec/requests/api/v1/price_histories_spec.rb
  spec/workers/price_update_worker_spec.rb` (targeted), then the full
  `app_fetcher` suite (regression).
- `bin/rubocop` on touched files.
- `bundle exec srb tc` — informational only, matching this session's
  established precedent that this isn't part of CI and carries a large
  pre-existing baseline.
- Manual: not planned to be performed live (same environment limitation
  noted in every prior plan this session).

## Risks

- **The frontend's own `sumAsOfEachHour` has the same class of
  algorithmic problem this plan's new backend code deliberately avoids**
  (rescans each item's point list from the start on every bucket instead
  of advancing a cursor), and additionally always buckets by hour
  regardless of window length. Neither is fixed by this plan (frontend
  work, out of scope) — but whoever picks up wiring a `1y` range into
  the dashboard will hit real lag if they feed a year's worth of daily
  points into the unmodified function expecting hourly buckets, or if
  they still bucket by hour for a year (~8,760 buckets). Flagging this
  explicitly so it isn't rediscovered from scratch.
- **Unbounded per-item log query for non-default periods** (see
  Assumptions) — acceptable at this project's current scale (no
  retention/pruning, modest data volume), but would need a bound
  (e.g., a seed query for "most recent log before window start" plus a
  windowed query, instead of "all logs ever") if any single item
  accumulates a very large number of price logs over time.
- **Cache key space grows slightly** (one more segment, a small fixed
  enum) — bounded and intentional, not a concern, but worth noting since
  `caching.md`'s existing guidance was written before any per-item
  cache had more than one shape.

## Assumptions

- Fetching *all* of an item's price logs (no lower bound) for a
  non-default period, rather than a windowed query plus a separate
  "seed" query for the last known price before the window, is
  acceptable given confirmed-in-research facts: no retention/pruning
  exists on `price_logs`, and this project's actual data volume is
  small. Revisit if that stops being true.
- `"1y"` means a rolling 365 days ending "now" (`Time.current`), not a
  calendar year — not verified against any product spec, just the most
  natural reading of Gemini's original `period=1y` framing.
- Bucket boundaries anchor to `Time.current` and step backward/forward
  in fixed `1.day` increments (not calendar-day/midnight-aligned) — a
  reasonable default consistent with how `bucketByHour` anchors to
  `Date.now()` today, but a genuine implementation choice, not a fact
  derived from existing code (nothing "day-buckets" anywhere yet).

## Missing Styleguides

### `.claude/styleguides/fetcher/caching.md` — insufficient for a resource with more than one cacheable variant

`caching.md` is sufficient for everything this plan reuses unchanged
(bulk `read_multi`/`write_multi`, the `app/caching/` placement, the
two-public-method interface as a *shape*) — but its two most relevant
MUST rules are written for exactly **one** cacheable variant per
resource, and this plan introduces a second one for `PriceHistoryCache`
specifically:

- "Construct keys as versioned arrays: `[<namespace>, <version_integer>,
  market_hash_name]`" — this plan's key is `["price_history",
  CACHE_KEY_VERSION, market_hash_name, period]`, a fourth segment the
  rule as written doesn't mention. Not obviously wrong, but not
  *specified* either — a future resource with, say, two independent
  variable dimensions (not just one `period`-like axis) has no stated
  convention to follow, and could reasonably order/shape the key
  differently than this plan does, producing inconsistent key schemes
  across `app/caching/` classes over time.
- "Invalidate with a single `Rails.cache.delete(key)` per
  `market_hash_name` — no bulk/wildcard delete" — this plan's
  `.invalidate` performs *multiple* precise, single-key deletes (one per
  known period) for one `market_hash_name`. This is not the "bulk/
  wildcard delete" the rule is actually guarding against (checked the
  ADR's reasoning — that MUST exists to rule out imprecise invalidation,
  not to cap the delete count at exactly one), but the rule's literal
  text ("a single... delete per market_hash_name") doesn't say so, and a
  future reader relying only on the written rule could conclude this
  plan's design is non-compliant, or choose a materially different
  mechanism (e.g. a version-counter-per-name instead of enumerating known
  variants) for the next resource that needs the same shape — exactly
  the inconsistency styleguides exist to prevent.

Also implicitly affected: `.claude/adr/fetcher/price-cache-invalidation.md`'s
"Implementation Constraints" section states the same three-segment key
shape as a settled decision — if the styleguide is updated, this ADR's
constraint should at least cross-reference the update rather than be
left contradicting it.

Must define/decide:

- The general key shape for a cacheable resource with more than one
  variant (e.g. `[namespace, version, resource_id, variant]`, matching
  what this plan already does, or something else) — so the *next* class
  that needs this shape doesn't re-derive it independently.
- Whether "invalidate by key" is understood to mean "delete every known
  cached variant for this resource," and what "known variants" means
  operationally (a class-level constant enumerating them, as this plan
  does, or some other mechanism) — worded precisely enough that a future
  `.invalidate` implementation for a similar case doesn't have to guess.

Depends on: this plan's `PriceHistoryCache.fetch_for(period:)`'s cache
key shape and its multi-period `.invalidate` (Implementation Approach).

## Completion Criteria

- [x] Desired behavior made explicit (period support, carry-forward
  bucketing, edge cases, invalidation scope, unsupported-period error).
- [x] Scope explicit (per-item cache extension only; no aggregation, no
  real-time, no frontend change).
- [x] Affected files/components identified (no new files at all).
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [ ] Plan checked against styleguides (`styleguides-check`).
- [ ] Implemented (`implement-plan`).
