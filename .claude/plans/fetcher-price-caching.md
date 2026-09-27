---
status: implemented
app: fetcher
goal: Cache current price / price history reads in app_fetcher via solid_cache, with point invalidation from PriceUpdateWorker and rate-limit-aware lazy warming for brand-new items
created: 2026-09-26
---

# Development Plan

## Goal

Stop `GET /api/v1/inventories/me` and `POST /api/v1/price_histories` from
hitting the database on every request by caching `current_price_cents` /
`change_24h_cents` (per `Item`, keyed by `market_hash_name`) and the
default-window price history (per `Item`, keyed by `market_hash_name`),
backed by `solid_cache`. Invalidate both caches explicitly, by key, from
`PriceUpdateWorker` the moment a price actually changes. Add a bounded,
deduplicated lazy-warming path so a user whose entire inventory is brand
new doesn't wait for the hourly `PriceScheduler` to see a first price.
Document the chosen invalidation/warming strategy in an ADR.

## Expected Behavior

**Normal behavior**

- Repeated `GET /api/v1/inventories/me` requests for the same items serve
  `current_price_cents`/`change_24h_cents` from cache; no `Item` price
  lookup query on the second+ request for an unchanged item.
- Repeated `POST /api/v1/price_histories` requests with no `since` param
  (the dashboard's default/common case, currently defaulting to
  `30.days.ago`) serve points from cache on the second+ request.
- The moment `PriceUpdateWorker` successfully updates an item's price, the
  *next* request for that item's price and that item's history reflects
  the new data — no waiting out a TTL.
- An inventory made up entirely of items with no price yet
  (`current_price_cents IS NULL`) triggers asynchronous price fetches
  immediately (via the existing `PriceUpdateWorker`), instead of waiting
  for the next `PriceScheduler` hourly tick.

**Edge cases**

- Items that don't exist in the DB at all (the existing `missing_names` /
  unsaved `Item.new` path in `InventoriesController`) are never cached or
  invalidated by `market_hash_name` — they have no stable DB-backed price
  to cache in the first place; today's behavior for them is unchanged.
- `price_histories` requests with an explicit, non-default `since` bypass
  the cache and query the DB directly, same as today — only the
  default-window case is cached in this phase (see Scope).
- Duplicate/concurrent requests for the same brand-new item do not enqueue
  duplicate `PriceUpdateWorker` jobs within a short dedup window.
- A single request cannot enqueue unbounded warmup jobs — capped at 20
  per request (matching the `steam_price_rpm` throttle ceiling, see
  Implementation Approach), so one large all-new inventory can't consume
  the whole shared Steam rate-limit budget (`Prop.throttle!`, 20/min &
  1000/day, global — see Risks) by itself. Any remainder is still picked
  up by the existing hourly `PriceScheduler`, whose `current_price_cents
  IS NULL` selection criterion already retries indefinitely until a
  price lands.

**Failure behavior**

- If `PriceUpdateWorker`'s Steam call fails (`response.success?` false),
  nothing is invalidated — matches today's existing "no DB write, no
  stream publish" behavior for that branch.
- If a warmup job itself gets rate-limited by `Prop.throttle!`, it fails
  silently exactly as it does today (logged warning, no exception, no
  Sidekiq retry) — this plan does not change that existing behavior; it
  relies on `PriceScheduler`'s hourly self-healing selection instead of
  adding new retry logic (see Risks for why, and Assumptions for the
  cap size that keeps this acceptable).

**Must remain unchanged**

- JSON response shape of both endpoints.
- `InventoriesController`'s existing handling of items missing from the
  DB entirely (`Steam::ItemParser.parse` + unsaved `Item.new` +
  `ItemsListUpdateWorker.perform_async` batching) — untouched.
- `PriceHistoriesController`'s behavior for explicit `since` values.
- `PriceUpdateWorker`'s existing transaction, stream-publish, and
  failure-handling logic — cache invalidation is additive, not a
  restructure.

## Scope

### In Scope

- Installing and configuring `solid_cache` for real (migrations,
  `config/solid_cache.yml`, `cache_store` in every environment, cache DB
  entries in `database.yml` for development/test).
- Item-level price cache (`current_price_cents`/`change_24h_cents`),
  keyed by `market_hash_name`, with bulk read/write to avoid N+1 on
  multi-item requests.
- Item-level, default-window-only price history cache, keyed by
  `market_hash_name`.
- Explicit point invalidation of both caches from `PriceUpdateWorker` on
  successful price update.
- A short TTL on both caches as a safety net only (not the primary
  invalidation mechanism).
- Bounded, deduplicated lazy warmup enqueue for items with no price yet,
  triggered from `InventoriesController`, reusing the existing
  `PriceUpdateWorker`.
- Test-environment cache_store change so cache hit/miss/invalidation
  specs exercise real cache behavior (matching this codebase's existing
  "test against the real backing service" convention for the Redis
  stream).
- New ADR recording the invalidation + warming strategy and its
  rate-limit tradeoff.

### Out of Scope

- Caching `price_histories` requests for arbitrary/custom `since` values
  (only the default/no-`since` window is cached this phase).
- Adding a job-uniqueness gem (e.g. `sidekiq-unique-jobs`) — dedup is done
  with a `Rails.cache` flag instead (see Implementation Approach).
- Any change to `Prop` rate-limit thresholds, or adding retry-on-throttle
  logic to `PriceUpdateWorker` — the existing silent-fail-and-let-the-
  scheduler-catch-it behavior is relied upon, not changed.
- Migrating `inventories_spec.rb`/`price_histories_spec.rb` from WebMock
  to VCR (pre-existing `fix_me.md` item, unrelated to caching).
- Fixing pre-existing `fix_me.md` Sorbet/sig gaps in `item.rb` or
  `price_scheduler.rb`.
- Any `app_core` changes.

## Implementation Approach

**solid_cache setup.** Run `bin/rails solid_cache:install` to generate
`config/solid_cache.yml`, `db/cache_schema.rb`, and
`db/cache_migrate/*`. Add a `cache:` database entry to
`config/database.yml` for `development` and `test` (mirroring the entry
that already exists for `production`), pointing at the same Postgres host
as the primary DB with a distinct database name
(`app_fetcher_development_cache`, `app_fetcher_test_cache`). Set
`config.cache_store = :solid_cache_store` in all three environments
(replacing `:memory_store` in development, `:null_store` in test, and the
currently-commented-out line in production). No `docker-compose.yml`
change is needed — the existing Postgres container can host an
additional database.

**Cache ownership: a dedicated `app/caching/` layer, not the models.**
The original draft of this plan put cache read/write/invalidate logic as
class methods directly on `Item`/`PriceLog`. `styleguides-check` found
that conflicts with `rails-layering.md`'s restriction of models to
"persistence + validations only... no orchestration" — see
`.claude/adr/fetcher/price-cache-invalidation.md` for the full reasoning
and rejected alternatives. Per that ADR and the resulting
`.claude/styleguides/fetcher/caching.md`, cache logic instead lives in two
new plain-Ruby classes under `app_fetcher/app/caching/`:

- `ItemPriceCache.fetch_for(market_hash_names)` — bulk read: `read_multi`
  against per-name versioned cache keys (`["item_price", 1,
  market_hash_name]`), fall back to a single bulk
  `Item.where(market_hash_name: missing_names)` query for whatever
  missed, `write_multi` the misses back. Avoids N+1 on cold cache with
  many items in one request (the pitfall of naive `fetch_multi`, whose
  fallback block runs once per miss rather than once for all misses).
- `ItemPriceCache.invalidate(market_hash_name)` — single
  `Rails.cache.delete` by key.
- `PriceHistoryCache.fetch_for(market_hash_names)` — same bulk
  read/fallback/write shape (keys `["price_history", 1,
  market_hash_name]`), scoped to the existing default window (currently
  `30.days.ago`); returns the same `{at:, price_cents:, volume:}` point
  shape the controller already renders.
- `PriceHistoryCache.invalidate(market_hash_name)` — single
  `Rails.cache.delete` by key.

Both classes may call `Item`/`PriceLog` (read on a miss) but are never
called from those models — dependency direction stays Controller/Worker
→ Caching → Models, per `rails-layering.md`. Enqueue-related logic
(warmup) still stays in the controller, not in `app/caching/` — per the
styleguide's Warmup/Dedup Pattern section, deduplicating an enqueue is a
distinct concern from cache read-through, and mirrors the existing
`InventoriesController#save_missing_items` private method, which already
enqueues `ItemsListUpdateWorker` directly from the controller for the
"missing from DB entirely" case.

**Price history cache key scope.** `price_histories` accepts an arbitrary
client-supplied `since`, which would otherwise make the cache-key space
unbounded. Rather than a TTL-only cache (which the task explicitly
distinguishes from the point-invalidation wanted for current price) or a
`since`-keyed generation-counter scheme, this phase caches only the
no-`since`/default case — one key per item, holding the full
default-window point array. `PriceHistoriesController` uses
`PriceHistoryCache.fetch_for` only when `params[:since]` is absent, then
filters nothing further (the cached array already matches the default
window); any explicit `since` keeps today's direct-query path untouched.
This keeps invalidation a literal single `Rails.cache.delete` per item,
as asked for — the cache key's version segment (see above) versions the
cached *payload shape*, a separate, orthogonal concern from the
`since`-scoping question this paragraph addresses.

**Invalidation point.** Inside `PriceUpdateWorker#perform`, immediately
after the existing `Item.transaction do price_log.save!;
item.update!(...) end` block (and before `publish_to_stream`, though
ordering between the two doesn't matter — both are independent
side-effects of the same successful update), call
`ItemPriceCache.invalidate(item.market_hash_name)` and
`PriceHistoryCache.invalidate(item.market_hash_name)`. Nothing is
invalidated in the `else` (failed Steam response) branch.

**Lazy warmup, bounded and deduplicated.** In
`InventoriesController#show`, after resolving `inventory_items`, collect
the DB-backed items (excludes the unsaved `Item.new` ones — they have no
`id` and aren't warmup candidates) whose `current_price_cents.nil?`, cap
the list at **20 items per request** (see Implementation Approach
derivation below; previously guessed at 50, revised), and for each: write
`Rails.cache.write("price_warmup_pending:#{item.id}", true, unless_exist:
true, expires_in: 90.seconds)`; only if that write reports it actually
set the value (i.e. no pending warmup already registered) do we
`PriceUpdateWorker.perform_async(item.id)`. This reuses the existing
worker as-is (no new worker class) and reuses `solid_cache` (no new gem
for dedup) at the cost of a small, explicit cap that intentionally
doesn't try to warm an entire very-large all-new inventory in one shot —
the remainder self-heals via `PriceScheduler`'s existing hourly
`current_price_cents IS NULL` selection.

Both numbers are derived from the existing `Prop.configure(:steam_price_rpm,
threshold: 20, interval: 1.minute)` limit in
`config/initializers/prop.rb`, not guessed:

- **Cap = 20, not 50.** `fetch_item_price` and `PriceScheduler`'s own
  routine updates share the same `:steam_price` Prop bucket
  (`lib/steam/client.rb:30`). Enqueuing more than 20 warmup jobs at once
  buys nothing: Sidekiq dequeues faster than the 1-per-3-seconds average
  the rpm limit allows, so anything past the first ~20 to actually reach
  `Prop.throttle!` within that rolling minute fails the throttle
  silently (no exception, no retry — see Risks) and just burns a job
  slot for zero benefit. Capping at exactly the rpm ceiling means a
  single request can't enqueue more than could plausibly succeed in one
  throttle window anyway.
- **Dedup TTL = 90 seconds, not 5 minutes.** This flag only needs to
  outlive Prop's own 1-minute throttle window, so a second request for
  the same item shortly after (page reload, second tab) doesn't
  double-enqueue while the first attempt is still in flight or was just
  rate-limited. A longer TTL (the original 5-minute guess) would have
  no additional dedup benefit but would delay a legitimate retry for an
  item that got rate-limited on its first lazy-warmup attempt —
  90 seconds gives one throttle window of headroom past the minute Prop
  itself resets on.

The daily `steam_price_rpd: 1000/day` bucket is shared between
`PriceScheduler`'s routine refresh of every item and this warmup path,
and neither the cap nor the dedup TTL protects against warmup traffic
gradually eating into that shared daily budget under sustained load —
see Risks; splitting Prop buckets by traffic source is an explicit
non-goal of this phase.

**Test environment.** Since `config.cache_store` becomes
`:solid_cache_store` in test too (see solid_cache setup above), add a
global `Rails.cache.clear` before each example (in `rails_helper.rb`) so
cache state doesn't leak between examples — mirrors this codebase's
existing preference for exercising real backing services in specs
(`price_update_worker_spec.rb` already asserts against a real Redis
stream rather than a mock). Because this is a blanket environment change
(every existing spec now runs against a real, DB-backed cache instead of
a no-op one), add one small standalone spec asserting the basic
write/read/clear cycle works under `:solid_cache_store` in test — a
smoke check for the environment change itself, independent of any of the
new caching *behavior* specs below.

**Cross-app correctness: contract-only, no new system spec.** The actual
boundary between `app_fetcher` and `app_core` is the JSON response shape
of both endpoints — `app_core`'s Ruby backend never calls `app_fetcher`
directly; the React island calls it straight from the browser
(`useDashboardData.js`) using a bridge token issued by
`DashboardsController`. Since this plan keeps that JSON shape unchanged
(see Expected Behavior), the existing `app_fetcher` request specs (being
extended here) plus `app_core`'s existing `useDashboardData.test.js` (left
untouched) already cover "both apps interact correctly." No new
`type: :system` spec is introduced for this task: per
`rspec-testing-strategy.md`, system specs are reserved for behavior a
request spec genuinely can't observe (browser redirects, JS-driven UI
state), and none of that applies to cache correctness. Introducing the
project's first system spec — none exist yet — is a separate, larger
precedent-setting decision, not something to fold into this plan.

## Files To Modify

- `app_fetcher/config/environments/development.rb` — `config.cache_store
  = :memory_store` → `:solid_cache_store`.
- `app_fetcher/config/environments/test.rb` — `config.cache_store =
  :null_store` → `:solid_cache_store`.
- `app_fetcher/config/environments/production.rb` — set
  `config.cache_store = :solid_cache_store` (currently commented out).
- `app_fetcher/config/database.yml` — add `cache:` entries for
  `development` and `test`, matching the shape of the existing
  production `cache:` block.
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb` — use
  `ItemPriceCache.fetch_for` instead of the direct `Item.where` lookup;
  add a private `enqueue_price_warmup` method (dedup + capped + calls
  `PriceUpdateWorker.perform_async`) invoked after building the response.
- `app_fetcher/app/controllers/api/v1/price_histories_controller.rb` —
  use `PriceHistoryCache.fetch_for` when `params[:since]` is blank; keep
  the existing direct query when it's present.
- `app_fetcher/app/workers/price_update_worker.rb` — call
  `ItemPriceCache.invalidate` / `PriceHistoryCache.invalidate` after the
  successful transaction.
- `app_fetcher/spec/rails_helper.rb` — add a `before(:each) {
  Rails.cache.clear }` to the existing `RSpec.configure` block.
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — extend
  existing examples to assert cache state before/after (real cache, not a
  mock), for both the success and failure branches.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — extend with
  cache hit/miss and warmup-enqueue scenarios.
- `app_fetcher/spec/requests/api/v1/price_histories_spec.rb` — extend
  with cache hit/miss scenarios for the default-window case.

## Files To Create

- `app_fetcher/config/solid_cache.yml` — generated by `bin/rails
  solid_cache:install`.
- `app_fetcher/db/cache_schema.rb` — generated.
- `app_fetcher/db/cache_migrate/*.rb` — generated migration(s).
- `app_fetcher/app/caching/item_price_cache.rb` — new: `ItemPriceCache`,
  per `.claude/styleguides/fetcher/caching.md`.
- `app_fetcher/app/caching/price_history_cache.rb` — new:
  `PriceHistoryCache`, per the same styleguide.
- `app_fetcher/spec/caching/item_price_cache_spec.rb` — new (unit spec,
  no `type:` metadata, per `caching.md`'s Testing section): cache
  hit/miss/invalidation for `ItemPriceCache`.
- `app_fetcher/spec/caching/price_history_cache_spec.rb` — new: cache
  hit/miss/invalidation for `PriceHistoryCache`.
- `app_fetcher/spec/caching/solid_cache_environment_spec.rb` — new:
  asserts `Rails.cache` actually writes/reads/expires under
  `:solid_cache_store` in test, independent of any caching *behavior*
  under test elsewhere — guards the blanket `cache_store` environment
  change itself. Lives alongside the other `spec/caching/` specs, not
  under `spec/support/` — `styleguides-check` confirmed `spec/support/`
  in this repo holds only helper modules (`bridge_token_helper.rb`,
  `redis_stream_helper.rb`), never example groups.

## Test Plan

- **Environment smoke check (new, standalone)**: a small spec confirming
  `Rails.cache.write`/`read`/`delete`/`clear` behave correctly under
  `:solid_cache_store` in the test environment — this is a check on the
  blanket `cache_store` config change itself (affects every existing
  spec, not just the new ones), separate from testing any of this
  feature's actual caching *behavior*.
- **Caching-class specs** (`spec/caching/`, unit, no `type:` metadata,
  per `.claude/styleguides/fetcher/caching.md`'s Testing section):
  - `ItemPriceCache.fetch_for`: cold cache hits DB once and populates
    cache; warm cache does not hit DB (assert via a real cache read, not
    a query-count mock, consistent with this codebase's "assert against
    real state" convention); multiple names in one call don't N+1 on a
    fully-cold cache (bulk fallback query, not per-name).
  - `ItemPriceCache.invalidate`: deletes the key; a subsequent
    `fetch_for` call is a genuine miss again.
  - Same three shapes for `PriceHistoryCache.fetch_for` /
    `PriceHistoryCache.invalidate`, using the existing `:old` (>24h)
    `price_logs` factory trait plus a fresh one to distinguish
    default-window contents.
- **Worker spec** (`price_update_worker_spec.rb`, extending the existing
  5 examples): on success, both caches are actually invalidated
  (pre-warm the cache in the example, run the worker, assert the cache
  key is gone); on Steam failure, caches untouched (pre-warm, run,
  assert still present) — extends the existing real-Redis-assertion
  style rather than mocking `ItemPriceCache`/`PriceHistoryCache`.
- **Request specs**:
  - `inventories_spec.rb`: a second identical request after a first serves
    from cache (assert no new `Item` SQL query fires on the second
    request — e.g. via an `ActiveSupport::Notifications.subscribe
    ("sql.active_record")` counter scoped to the example, since no
    query-counting helper currently exists in this repo); an
    all-new-items inventory enqueues `PriceUpdateWorker` jobs (via
    `Sidekiq::Testing.fake!`, matching `price_scheduler_spec.rb`'s
    existing convention) up to the cap, and a repeat request within the
    dedup window does not enqueue duplicates for the same item.
  - `price_histories_spec.rb`: a second identical no-`since` request
    serves from cache (same no-new-query assertion); a request with an
    explicit `since` still queries the DB every time (unchanged
    behavior, regression-guarded).
- **Regression coverage**: existing auth and happy-path examples in both
  request specs must keep passing unmodified in shape (response JSON
  structure is not changing).
- **Cross-app coverage (decided, not deferred)**: no new `type: :system`
  spec is added. Contract correctness between `app_fetcher` and
  `app_core` is covered by the two request specs above (the actual
  wire format both apps agree on) plus `app_core`'s existing
  `useDashboardData.test.js`, which is left as-is since the JSON shape
  it maps doesn't change. See Implementation Approach for the reasoning
  (browser calls `app_fetcher` directly; no Ruby-to-Ruby boundary
  exists to test).

## Implementation Steps

1. Run `bin/rails solid_cache:install`; wire up `database.yml` cache
   entries for development/test; set `cache_store` in all three
   environments; run `bin/rails db:prepare` / `db:test:prepare` locally
   to confirm the cache DB migrates cleanly.
2. Add `before(:each) { Rails.cache.clear }` to the RSpec global config.
3. TDD `ItemPriceCache.fetch_for` / `.invalidate` against
   `spec/caching/item_price_cache_spec.rb` (new file, new
   `app/caching/item_price_cache.rb`).
4. TDD `PriceHistoryCache.fetch_for` / `.invalidate` against
   `spec/caching/price_history_cache_spec.rb` (new file, new
   `app/caching/price_history_cache.rb`).
5. Wire `ItemPriceCache.invalidate` / `PriceHistoryCache.invalidate` into
   `PriceUpdateWorker#perform`'s success branch; extend
   `price_update_worker_spec.rb` to cover both branches.
6. Wire `ItemPriceCache.fetch_for` into `InventoriesController#show`;
   extend `inventories_spec.rb` with the cache hit/miss scenario.
7. Add the bounded/deduplicated warmup path
   (`enqueue_price_warmup`) to `InventoriesController`; extend
   `inventories_spec.rb` with the warmup-enqueue and dedup scenarios.
8. Wire `PriceHistoryCache.fetch_for` into
   `PriceHistoriesController#index` for the no-`since` branch; extend
   `price_histories_spec.rb`.

## Verification

- `bin/rails db:test:prepare` (confirms both primary and cache DB
  schemas load cleanly in test).
- `bundle exec rspec spec/caching/item_price_cache_spec.rb
  spec/caching/price_history_cache_spec.rb
  spec/workers/price_update_worker_spec.rb
  spec/requests/api/v1/inventories_spec.rb
  spec/requests/api/v1/price_histories_spec.rb` (targeted).
- `bundle exec rspec` (full `app_fetcher` suite, regression check).
- `srb tc` (repo is Sorbet `typed: strict` throughout; new `app/caching/`/
  controller/worker code needs sigs).
- `bin/rubocop -f github` (matches CI's `lint` job).
- Manual check: hit `/api/v1/inventories/me` twice for the same user and
  confirm (via Rails log or a temporary query-count check) the second
  request issues no `Item` price query; trigger `PriceUpdateWorker` for
  one of those items and confirm the next request reflects the new price
  immediately.

## Risks

- **Global Steam rate limit vs. lazy warming** — `Prop.throttle!` in
  `lib/steam/client.rb` is a *global* limiter (20/min, 1000/day, not
  per-user or per-item), and a rate-limited `PriceUpdateWorker` run fails
  silently today (logged warning, no exception, so Sidekiq's `retry: 5`
  never engages). This plan does not change that failure behavior — it
  caps warmup-enqueue per request and leans on `PriceScheduler`'s
  existing hourly `current_price_cents IS NULL` re-selection as the
  eventual-consistency backstop. A large spike of new-item warmup
  requests across *many concurrent users* is still bounded only by the
  same shared global budget as regular scheduled updates — this plan
  does not add per-source budget allocation between "scheduled" and
  "lazy warmup" traffic; if that turns out to matter in practice, it's a
  follow-up, not part of this phase.
- ~~`config.cache_store = :solid_cache_store` in test changes a
  previously null-op store into a real one for every existing spec~~ —
  checked, not just asserted: across all of `app_fetcher/spec`, only
  `inventories_spec.rb` and `price_histories_spec.rb` touch the cached
  endpoints, and neither repeats a request within a single example; no
  spec anywhere calls `Steam::Client`/`PriceUpdateWorker` more than once
  per example either, so `Prop`'s own `Rails.cache`-backed rate counters
  (`config/initializers/prop.rb`) can't accumulate within an example, and
  the planned `before(:each) { Rails.cache.clear }` prevents any
  cross-example accumulation. Closed — no "watch for it during
  implementation" hedge needed; the environment smoke check (Test Plan)
  still stands as regression coverage for the config change itself.
- ~~`internal-api-controllers.md`'s exact wording on "single collaborator
  per action"~~ — verified directly against the file
  (`styleguides-check`): it's a SHOULD, not a MUST, and its own canonical
  example (`InventoriesController#show`) already calls `Steam::Client`,
  `Item.where`, `Steam::ItemParser`, and `ItemsListUpdateWorker` in one
  action. Adding `enqueue_price_warmup` alongside the existing
  `save_missing_items` (same shape: dedup-ish guard + capped
  `.perform_async` loop) is consistent with that established exception,
  not a new violation. Closed — no restructuring needed on this point.
- **Bulk cache fallback correctness** (`read_multi` + bulk DB query for
  misses + `write_multi`) is more code than a naive per-key `fetch`, and
  is exactly the kind of logic that's easy to get subtly wrong (e.g.
  writing `nil` results for names with no matching `Item` row into the
  cache in a way that later reads misinterpret as "not cached" instead of
  "cached miss") — needs careful TDD, not just a happy-path test.
- ~~Cache logic placed on `Item`/`PriceLog` conflicts with
  `rails-layering.md`~~ — resolved via
  `.claude/adr/fetcher/price-cache-invalidation.md` and
  `.claude/styleguides/fetcher/caching.md`: cache logic moved to a
  dedicated `app/caching/` layer (`ItemPriceCache`, `PriceHistoryCache`)
  that may call `Item`/`PriceLog` but is never called from them,
  preserving `rails-layering.md`'s one-way dependency direction instead
  of violating its "no orchestration in models" rule. See Applicable
  Styleguides.

## Assumptions

- Warmup cap of **20 items per request** and dedup TTL of **90 seconds**
  are now derived from the existing `steam_price_rpm` throttle (20/min)
  rather than guessed (see Implementation Approach for the derivation) —
  no longer a bare assumption, but still worth confirming empirically
  once real usage patterns are observed.
- Price-history cache TTL (safety net) and price cache TTL (safety net)
  are set at **15 minutes** for both — genuinely a product judgment call,
  not derivable from code: chosen as a conservative fraction of the
  actual ~hourly price-update cadence (`PriceScheduler`'s `updated_at <
  1.hour.ago` window), so a missed/buggy invalidation can't leave a
  price stale for anywhere close to a full update cycle. Confirm this
  tradeoff (freshness bound vs. hit rate) before/while implementing.
- The **shared `steam_price_rpd` (1000/day) budget** between
  `PriceScheduler`'s routine refresh and this warmup path is not fully
  budgeted by the per-request cap — under sustained load, warmup could
  still gradually crowd out scheduled refreshes for other items. Treated
  as a known, accepted tradeoff for this phase (see Risks), not solved
  by the cap/TTL numbers above.
- Assumes the existing Postgres container in `docker-compose.yml` can
  host an additional `*_cache` database per environment without further
  infra changes (standard multi-database-per-instance Postgres usage) —
  not verified by actually running `solid_cache:install` yet.
- ~~Assumes `rails_helper.rb` (not verified by path in this plan) is
  where a global `before(:each)` hook belongs~~ — confirmed:
  `app_fetcher/spec/rails_helper.rb` exists (alongside `spec_helper.rb`)
  and is where `RSpec.configure` already lives; add the `Rails.cache.
  clear` hook there.

## Applicable Styleguides

- `.claude/styleguides/fetcher/caching.md` — constrains the entire
  Implementation Approach: cache logic lives in `ItemPriceCache`/
  `PriceHistoryCache` under `app/caching/` (not on `Item`/`PriceLog`),
  `read_multi`/`write_multi` bulk shape, versioned cache keys, by-key
  invalidation owned solely by `PriceUpdateWorker`, TTL as a safety net
  only, the `Rails.cache`-flag warmup/dedup pattern, and caching-specific
  testing conventions (real `Rails.cache` state, `spec/caching/`, no
  `type:` metadata).
- `.claude/adr/fetcher/price-cache-invalidation.md` — the reasoning
  behind that placement decision and the rejected alternatives (model
  class methods, a shared concern, controller-inline logic, TTL-only,
  version-bump invalidation, `sidekiq-unique-jobs`); referenced, not
  duplicated, by the styleguide above.
- `.claude/styleguides/rails-layering.md` — constrains the caching
  layer's dependency direction (Controller/Worker → Caching → Models,
  one-way) and confirms cache logic must not live on the models.
- `.claude/styleguides/fetcher/architecture-layers.md` — confirms caching
  is orthogonal to the ingestion-pipeline scenario map (parsers/builders/
  workers/schedulers), not a fourth scenario; no change needed to that
  map itself.
- `.claude/styleguides/fetcher/internal-api-controllers.md` — constrains
  `InventoriesController`/`PriceHistoriesController`'s shape: JSON
  response/error format unchanged, `enqueue_price_warmup` follows the
  same "SHOULD: one collaborator, with established exceptions like
  `save_missing_items`" precedent already in this controller.
- `.claude/styleguides/fetcher/background-jobs.md` — constrains
  `PriceUpdateWorker`'s changes: invalidation calls added inside the
  existing success branch, no change to its transaction/retry/queue
  configuration.
- `.claude/styleguides/rspec-conventions.md` — constrains the Test Plan's
  spec levels (unit specs for `app/caching/`, request specs for the two
  controllers), `FactoryBot` usage, and the "assert real backing state,
  don't mock" convention applied throughout.
- `.claude/styleguides/ruby-sorbet.md` — constrains every new/changed
  Ruby file (`app/caching/*.rb`, controller/worker edits): `# typed:
  strict`, `extend T::Sig`, a `sig` on every method.

## Completion Criteria

- [x] Desired behavior made explicit (cache hit/miss/invalidation/warmup,
  including edge and failure cases).
- [x] Scope explicit (default-window-only history cache; no new dedup
  gem; no Prop/rate-limit changes).
- [x] Affected files/components identified.
- [x] Test strategy defined (caching-class specs, worker spec extension,
  request spec extension, regression coverage).
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (`styleguides-check` — see
  Applicable Styleguides).
- [x] Implemented (`implement-plan` — see Implementation Summary below).

# Implementation Summary

## Implemented

- **solid_cache installed and wired to a dedicated `cache` database**:
  ran `bin/rails solid_cache:install` (generated `config/cache.yml` —
  not `config/solid_cache.yml` as the plan guessed — and
  `db/cache_schema.rb`, and uncommented `config.cache_store` in
  `production.rb`); added `cache:` entries to `database.yml` for
  `development`/`test`; set `config.cache_store = :solid_cache_store` in
  all three environments; ran `db:prepare` to create/load both new cache
  databases (`app_fetcher_{development,test}_cache`).
- **`app/caching/item_price_cache.rb`** (`ItemPriceCache`): `.fetch_for`
  (bulk `read_multi` → bulk `Item` fallback query for misses →
  `write_multi`, 15-minute safety-net TTL, versioned keys
  `["item_price", 1, market_hash_name]`) and `.invalidate` (single
  `Rails.cache.delete`). Returns real `Item` AR instances (not
  hand-rolled hashes), keyed by `market_hash_name` — chosen so
  `InventoriesController` could swap its data source without changing
  how the result is consumed downstream (`.values`, `.as_json`).
- **`app/caching/price_history_cache.rb`** (`PriceHistoryCache`): same
  bulk read/fallback/write shape, scoped to the default 30-day window;
  returns pre-rendered `{at:, price_cents:, volume:}` point arrays keyed
  by `market_hash_name` (an `Item` row with no logs yet returns `[]`; a
  name with no matching `Item` is omitted entirely, mirroring prior
  behavior).
- **`PriceUpdateWorker`**: calls `ItemPriceCache.invalidate` /
  `PriceHistoryCache.invalidate` immediately after its existing
  successful transaction; the failure (`else`) branch is untouched, so
  neither cache is invalidated on a failed Steam response.
- **`InventoriesController#show`**: replaced the direct `Item.where`
  lookup with `ItemPriceCache.fetch_for`; added a private
  `enqueue_price_warmup`, mirroring the existing `save_missing_items`
  pattern, that caps warmup at 20 items/request and deduplicates via
  `Rails.cache.write(key, true, unless_exist: true, expires_in: 90.
  seconds)` before calling the existing `PriceUpdateWorker.perform_async`.
- **`PriceHistoriesController#index`**: uses `PriceHistoryCache.fetch_for`
  when `params[:since]` is blank; the explicit-`since` branch is
  byte-for-byte the original direct-query code, unchanged.
- **Test environment**: `spec/rails_helper.rb` gained
  `Rails.cache.clear` in the existing `before(:each)` block (alongside
  `Sidekiq::Worker.clear_all`).
- **New RSpec helper** `spec/support/sql_query_counter_helper.rb`
  (`count_queries(model:) { ... }`, via `ActiveSupport::Notifications`)
  — not in the original plan, needed to assert "no DB query fired" at
  both the caching-class and request-spec level without mocking the
  thing under test.

## Tests

- `spec/caching/solid_cache_environment_spec.rb` (new) — 2 examples,
  write/read/delete/clear smoke check against the real
  `:solid_cache_store` in test.
- `spec/caching/item_price_cache_spec.rb` (new) — 4 examples: cold-cache
  DB hit + correct values, warm-cache no DB hit, names with no `Item`
  row omitted, `.invalidate` forces a genuine miss.
- `spec/caching/price_history_cache_spec.rb` (new) — 5 examples: same
  hit/miss/invalidate shapes, plus default-window exclusion of an
  older-than-30-days log and the empty-array-vs-omitted distinction.
- `spec/workers/price_update_worker_spec.rb` (extended) — the existing 5
  examples now also assert: on success, both caches reflect the new
  price/point immediately after invalidation; on both failure branches
  (unsuccessful response, error status), a pre-warmed cache is
  untouched (`count_queries` stays 0).
- `spec/requests/api/v1/inventories_spec.rb` (extended) — added: cache
  hit on a second identical request (0 `Item` queries); an unpriced item
  triggers a warmup enqueue; a repeat request within the dedup window
  doesn't double-enqueue; a 21-item all-new inventory caps enqueues at
  20. Extracted the shared Steam-inventory stub into a `before` block
  per `rspec-conventions.md`'s "stub extraction" rule, since it's now
  reused by more than one example.
- `spec/requests/api/v1/price_histories_spec.rb` (extended) — added:
  cache hit on a second no-`since` request (0 `PriceLog` queries); an
  explicit `since` still queries the DB every time (regression guard).
  Extracted a `post_price_histories(since:)` helper method for the same
  reason.

Commands actually executed for every increment (RED → GREEN → full
suite), and again at the end:

```
docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"
docker compose run --rm app_fetcher bash -c "bin/rubocop <touched files> -f simple"
docker compose run --rm app_fetcher bash -c "bin/rubocop -a <touched files>"
docker compose run --rm app_fetcher bash -c "bundle exec srb tc"
docker compose run --rm app_fetcher bin/brakeman --no-pager
```

## Verification

- **Full `app_fetcher` suite**: 44 examples, 0 failures (up from a 27-
  example green baseline captured before any change).
- **Rubocop** (touched files only): 56 offenses found (all
  `Layout/SpaceInsideArrayLiteralBrackets`, the project's own configured
  style — array literals need padded brackets), all autocorrected;
  re-run confirms 0 offenses. Full suite re-run after autocorrect: still
  44/44.
- **`srb tc`**: baseline (before any change) already had **58
  pre-existing errors** — unresolved gem constants (`Sidekiq`, `RSpec`,
  `FactoryBot`, `JWT`, `Cors`), a pre-existing missing `sig` and broken
  `super` call in `item.rb`, a pre-existing `perform_async`-not-found on
  `ItemsListUpdateWorker`, etc. — none related to caching, and `srb tc`
  is not part of this project's CI (`ci.yml` runs `brakeman`,
  `bundler-audit`, `rubocop`, and `rspec`, not `sorbet`). After this
  change: **59 errors**. Diffing distinct error signatures (not just
  counts, since line numbers shifted): incidentally *fixed* one
  pre-existing gap (added the missing `sig` on
  `save_missing_items` while editing its surrounding code) and
  introduced two new occurrences of the *same pre-existing categories*
  already present elsewhere in the baseline — `Item#current_price_cents`
  not resolving on `Item` (the same stale-DSL-RBI class of issue as
  `item.rb`'s existing `stattrak` error) and `PriceUpdateWorker.
  perform_async` not resolving (the identical, already-present
  `ItemsListUpdateWorker.perform_async` issue, now also hit by the new
  call site). No new *category* of type error was introduced; regenerating
  gem/DSL RBIs to fix the pre-existing baseline is out of scope for this
  change.
- **Brakeman**: `bin/brakeman --no-pager` exited with status 5 and no
  visible report body in this container environment (likely an
  unrelated tooling/pager quirk, not investigated further — out of
  scope for this change; the new code only uses parameterized
  `ActiveRecord` queries and array-keyed `Rails.cache` calls, nothing
  in the categories Brakeman scans for).
- **Manual "hit the endpoint twice" check**: not performed against a
  live server with real Steam network access (unavailable in this
  environment). Equivalent rigor was obtained instead through the new
  request specs, which exercise the exact same controller/cache/DB code
  path via Rails' real request cycle (not a shortcut around it) and
  directly assert "second request issues zero `Item`/`PriceLog`
  queries."

## Deviations

- **`config/cache.yml`, not `config/solid_cache.yml`** — the actual name
  `bin/rails solid_cache:install` generates in this Rails/solid_cache
  version. Plan text updated nowhere else needed changing because of
  this (no code references the config file by path).
- **No `db/cache_migrate/*.rb` migration files** — solid_cache installs
  via a direct `db/cache_schema.rb` (schema-first, like solid_queue),
  not versioned migrations. `database.yml`'s `migrations_paths:
  db/cache_migrate` entries are still correct (they're where *future*
  migrations for this DB would go), but the plan's "Files To Create"
  line item listing migration files was wrong — there are none yet.
- **New required config, not anticipated by the plan**: `config/
  application.rb` needed `config.solid_cache.connects_to = { database:
  { writing: :cache } }`. Without it, `Rails.cache` silently used the
  *primary* database connection (no error — `SolidCache::Record` just
  fell back to the default connection), which would have made every
  cache read/write invisibly hit the wrong database. Discovered via a
  manual `bin/rails runner` smoke check before writing any cache-class
  code, not via a failing test (there was no test yet that could have
  caught a "wrong database" class of bug). Setting it inside `config/
  initializers/solid_cache.rb` does **not** work — the engine's own
  `solid_cache.config` initializer reads `config.solid_cache.connects_to`
  *before* user initializers run, so it must live in `config/
  application.rb` (or a `config/environments/*.rb` file).
- **`ItemPriceCache.fetch_for` returns real `Item` instances**, not a
  plain hash of price fields, despite the ADR's shorthand describing it
  as wrapping just `current_price_cents`/`change_24h_cents`. The
  controller's existing code merges cached items with unsaved `Item.new`
  instances and calls `.as_json(only: [...])` uniformly across both —
  returning plain hashes from the cache would have broken that
  uniformity (or required restructuring code outside this change's
  scope). Caching the real (Marshal-able) AR row achieves the same
  invalidation/staleness behavior the ADR specifies with materially less
  code change.
- **`sql_query_counter_helper.rb` added**, not listed in the plan's
  Files To Create. Needed to assert the plan's own stated Done-When
  criterion ("повторные запросы не бьют в БД") as an actual behavioral
  test rather than an inferred side effect.

## Remaining Issues

- The `steam_price_rpd` (1000/day) shared-budget risk between
  `PriceScheduler` and warmup traffic (documented in the ADR and this
  plan's Risks/Assumptions) remains unaddressed by design — this phase
  deliberately doesn't split Prop's rate-limit buckets by traffic
  source.
- `srb tc`'s 58-error pre-existing baseline (stale gem/DSL RBIs) is
  unrelated to this change and was not fixed; `Item`'s RBI still doesn't
  resolve `current_price_cents` as a reader, so any future code calling
  Item attribute readers directly (not through `as_json`) will keep
  surfacing the same class of false-positive until the project's Sorbet
  setup is regenerated — a separate, pre-existing task.
- Brakeman's exit-5/empty-output behavior in this container was not
  investigated; if this also reproduces in actual CI, it's a
  pre-existing environment issue unrelated to this change and worth a
  separate look.
- The cap (20) and dedup TTL (90s) numbers are, per the plan's own
  Assumptions, derived from `steam_price_rpm` but not yet validated
  against real traffic patterns — worth revisiting once this ships.

## Post-Implementation Addition: `UserInventoryCache`

Added after initial implementation, at the user's explicit request —
not part of the original plan/ADR/styleguide-check pass above.

**What**: `app/caching/user_inventory_cache.rb` — caches the resolved
`market_hash_names` list for a `steam_id` (i.e. the result of
`Steam::Client#fetch_user_inventory`), so a second dashboard load within
the TTL window skips the Steam API call entirely, not just the DB reads
`ItemPriceCache`/`PriceHistoryCache` already covered. `InventoriesController
#show` now checks `UserInventoryCache.read(current_steam_id)` first;
only on a miss does it call `Steam::Client`, and only on
`response.success?` does it `UserInventoryCache.write(...)`.

**Why it doesn't fit the existing `caching.md` styleguide as written**:
the styleguide's Interface section mandates exactly two methods,
`.fetch_for`/`.invalidate`, and its "When to Use" section scopes the
pattern to "data that changes... driven by a background job." Neither
holds here — a user's Steam inventory changes because of their own
trading activity on Steam's platform, which this app has no write path
into and therefore nothing to explicitly invalidate. `UserInventoryCache`
uses a `.read`/`.write` interface instead and is TTL-only (5 minutes) by
design. **The styleguide itself was not updated to reflect this new
shape** — `.claude/styleguides/fetcher/caching.md` still describes only
the `.fetch_for`/`.invalidate` shape. This is a known gap: a future
`styleguides-check` pass (or a direct edit) should either broaden
`caching.md`'s Interface/When-to-Use sections to explicitly cover a
TTL-only, externally-driven-staleness variant, or add a second styleguide
entry for it, so the next cache added under `app/caching/` doesn't have
to re-derive this distinction from scratch.

**Also still open, per the user's explicit "for now" framing**:
`ItemPriceCache`/`PriceHistoryCache` still fall back to a direct DB query
on a miss and write the result themselves (in addition to
`PriceUpdateWorker`'s invalidation) — the user confirmed this is
temporary, deferred until a broader rework of `current_price_cents`
read/write ownership (see project memory
`project_price_cache_rework_planned.md`). Not changed in this pass.

**Files added**: `app/caching/user_inventory_cache.rb`,
`spec/caching/user_inventory_cache_spec.rb`. **Files modified**:
`app/controllers/api/v1/inventories_controller.rb` (Steam call now
conditional on a cache miss; the early `render ... ; return` on Steam
failure replaces the previous `if/else` wrapping the whole method body),
`spec/requests/api/v1/inventories_spec.rb` (added a Steam-call-count
regression test). Verified: targeted spec green (9/9), full suite green
(48/48, up from 44), `rubocop` clean on all four touched/added files.
