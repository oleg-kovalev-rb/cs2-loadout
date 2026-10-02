---
status: implemented
app: fetcher
goal: Add persistent per-user Steam inventory storage (user_inventories/user_inventory_items), synced weekly via a new UserInventorySyncService service and decoupled from a daily DB-only inventory-value calculation, plus an immediate rate-limited manual refresh endpoint, replacing UserInventoryCache's role as the sole source of truth
created: 2026-10-01
---

# Development Plan

## Goal

Give `app_fetcher` a durable, queryable record of what items each Steam
user currently owns — today this only exists as a 5-minute
`Rails.cache` entry (`UserInventoryCache`) with no DB backing and no
real invalidation. Replace that with `user_inventories`/
`user_inventory_items` tables, synced from Steam **weekly** by a
dedicated worker/scheduler pair, plus a rate-limited manual "refresh
now" endpoint for immediate freshness. Inventory **value** calculation
(`InventoryValueLog`, the existing daily chart) is decoupled from that
weekly Steam sync entirely — it now reads already-persisted
`user_inventory_items`/`items` prices from the DB and makes **zero**
Steam calls, since item prices are already kept fresh independently by
`PriceScheduler`/`PriceUpdateWorker` (hourly). `UserInventoryCache` is
demoted from "only copy of the data" to a read-shielding Redis cache in
front of the DB.

This plan follows a `research-codebase` pass and an extended design
discussion with the user in the same session, including two deliberate
pivots partway through (see below). The decisions recorded here are
final, not proposals to re-derive. The single most consequential one —
a new shared `app/services/` layer in `app_fetcher`, whose first class
(`UserInventorySyncService`) is called synchronously from a controller
and persists data, overriding `layered-ingestion-pipeline.md`'s general
"only a worker persists" rule and introducing a layer that ADR
explicitly says this app doesn't have — is called out explicitly in
Implementation Approach and must be resolved via an ADR amendment
during `styleguides-check` before implementation starts.

**Design pivot #1, recorded for context:** an earlier iteration of this
plan coupled weekly/daily cadence to a single worker (the existing
`InventoryValueUpdateWorker` doing both the Steam fetch *and* the value
sum, daily). The user explicitly decoupled these: the Steam-calling
sync (content) and the DB-only calculation (value) don't need to share
a cadence or a call site once persistence exists, and splitting them
cuts the shared `steam_inventory_rpd: 1000/day` Prop budget's per-user
cost roughly 7x (weekly vs. daily), which matters for how many
self-seeded users this feature can support before hitting that shared
ceiling. The accepted tradeoff: the value chart's numbers are now
computed against a composition snapshot that can be up to a week stale
if the user never clicks refresh — mitigated by shipping the manual
refresh button's backend endpoint in this same plan (not deferred), so
a user who just traded has an immediate way to force freshness. A
further idea (physically separating "Steam-calling" vs "DB-only"
workers into different folders/namespaces) was discussed and
**explicitly rejected** — see Implementation Approach's note on this;
don't reopen it without the user raising it again. The existing
queue-based separation (`:prices` vs `:default`, per
`background-jobs.md`) already serves that purpose.

**Design pivot #2, recorded for context:** an earlier iteration of this
plan split the Steam-calling/backfill logic into a *pure* shared
resolver (no Steam call, no persistence) plus separate, per-caller
persistence code in the controller and in `UserInventorySyncWorker`.
The user considered this, then explicitly rejected the split: since
both callers need the exact same sequence (fetch from Steam, resolve
known/missing items, backfill, persist), the user asked to extract the
**entire** sequence — including the Steam call and the persistence —
into one shared service (`UserInventorySyncService`), called identically
by both. This also has a secondary benefit the user didn't initially
intend but which resolves itself as a consequence: it satisfies
`internal-api-controllers.md`'s "one collaborator per action" rule
without needing a separate exception, since `show`/`refresh` now each
call exactly one collaborator (the service), not several inline steps.

## Expected Behavior

**Normal behavior**

- `GET /api/v1/inventories/me` for a `steam_id` with an existing
  `user_inventories` row: served from `user_inventories`/
  `user_inventory_items` JOIN `items` (through the reshaped
  `UserInventoryCache`), no Steam call, same response shape as today
  (`items_count`, `items` with `market_hash_name`/`metadata`/
  `current_price_cents`/`change_24h_cents`).
- First-ever `GET /api/v1/inventories/me` for a `steam_id` (no
  `user_inventories` row yet): calls `UserInventorySyncService.call(steam_id)`
  synchronously — fetches from Steam, resolves known vs. missing
  items, backfills missing `Item` rows, and persists
  `user_inventories`/`user_inventory_items`, all before the response
  renders. By the time this response is sent, the user's full current
  inventory is durably saved server-side.
- New `POST /api/v1/inventories/refresh`: rate-limited (see
  Assumptions for the exact window), calls the same
  `UserInventorySyncService.call(steam_id)` (full replace of
  `user_inventory_items`), returns the same response shape as `show`.
  Ships as part of this plan, not deferred — it's the user's main
  lever against the weekly sync's staleness window.
- **Weekly, per `steam_id`**: a new `UserInventorySyncScheduler`
  (cron-triggered, like every other scheduler, but its own run does no
  I/O) enqueues a new `UserInventorySyncWorker` for any `steam_id`
  whose `user_inventories.updated_at` is more than 7 days old. That
  worker calls the same `UserInventorySyncService.call(steam_id)` —
  identical persistence path to cold-start/refresh, just triggered
  from a worker (Scenario 3) instead of a controller (Scenario 1).
- **Daily, per `steam_id` already in `InventoryValueLog`**: the
  existing `InventoryValueScheduler` (unchanged) fans out to
  `InventoryValueUpdateWorker`, which now makes **no Steam call at
  all** — it reads that `steam_id`'s current `user_inventory_items`
  joined to `items.current_price_cents`, sums, and upserts today's
  `InventoryValueLog` row, exactly as before in shape.

**Edge cases**

- A literally-empty Steam inventory (0 items): `user_inventories` row
  still exists/updates, `user_inventory_items` simply has zero rows
  for that user — distinguishable from "never synced" (no
  `user_inventories` row at all), which still triggers cold-start
  behavior.
- An item present in a previous sync but absent from the latest Steam
  response is removed from `user_inventory_items` on the next sync
  (full replace, not a diff) — true for the weekly worker, cold start,
  and manual refresh alike, since all three go through the same
  `UserInventorySyncService.call`.
- A `steam_id` that has visited `GET /api/v1/inventory_values` (so it's
  self-seeded into `InventoryValueLog`, and `InventoryValueScheduler`
  will fan out to it) but has **never** visited `GET
  /api/v1/inventories/me`: no `user_inventories` row exists for them at
  all yet. `InventoryValueUpdateWorker` must handle this without error
  — treat it the same as a zero-item inventory (`total_value_cents: 0`
  for that day), not as a failure. These two self-seed triggers are
  genuinely independent today (see Risks) — this plan doesn't unify
  them, just makes sure the value worker doesn't blow up on the gap.
- Manual refresh (or a cold-start visit) within the last 7 days
  "counts" toward the weekly scheduler's staleness check — it reads
  `user_inventories.updated_at`, which any of the three sync paths
  (weekly worker, cold start, manual refresh) touches identically
  (all going through the same `UserInventorySyncService.call` →
  `UserInventory.sync!`), so a recently-refreshed user is correctly
  skipped by that week's scheduler pass with no extra bookkeeping.
- `POST /api/v1/inventories/refresh` with no prior `GET` (cold
  refresh): still works, behaves like cold start.
- A second `POST /api/v1/inventories/refresh` for the same `steam_id`
  within the rate-limit window: rejected before
  `UserInventorySyncService.call` runs at all — no Steam call.

**Failure behavior**

- Cold start / `refresh`: `UserInventorySyncService.call` returns a
  `Result` with `success: false`; the controller renders
  `{ message: result.error }` / `:bad_request`, identical to today's
  `show` failure branch.
- `UserInventorySyncWorker`: `UserInventorySyncService.call` returns
  `success: false` → worker logs
  `[UserInventorySyncWorker] Failed for <steam_id>: <error>` and
  returns — no `user_inventories`/`user_inventory_items` change. A
  failed sync must never wipe out the last-known-good persisted
  inventory, and must not touch `updated_at` either (so the next
  scheduler pass retries it, rather than treating a failed attempt as
  a fresh sync).
- `InventoryValueUpdateWorker` has no external-call failure branch at
  all (it does no I/O beyond Postgres) — a plain read-sum-write, no
  `Steam::Client` involved, no rescue needed beyond normal Sidekiq
  retry semantics for a genuine DB error.
- `refresh` when rate-limited: `{ message: "..." }` /
  `:too_many_requests` (`429`), no Steam call, matching the shape
  convention used elsewhere for request-triggered dedup (distinct from
  the silent warmup-dedup, since this is a direct user action the
  caller needs to understand).

**Must remain unchanged**

- `GET /api/v1/inventories/me`'s response shape and its price-warmup
  enqueue behavior (cap 20, 90s dedup).
- `ItemPriceCache`/`PriceHistoryCache` and `PriceUpdateWorker`'s
  invalidation — untouched.
- `Api::V1::InventoryValuesController`/`InventoryValueLog`'s own
  response shape, self-seed-on-first-read behavior, and
  `InventoryValueScheduler`'s own fan-out logic — untouched; only
  `InventoryValueUpdateWorker`'s internals (not its external contract:
  same `perform(steam_id)` signature, same upsert target) change.

## Scope

### In Scope

- Migration creating `user_inventories` and `user_inventory_items`.
- `UserInventory`/`UserInventoryItem` models, including
  `UserInventory.sync!` (full-replace persistence for one steam_id's
  item set).
- A new shared service, `UserInventorySyncService` (see Implementation
  Approach), owning the full fetch-from-Steam → resolve known/missing
  → backfill → persist sequence, called identically from
  `InventoriesController#show`/`refresh` and the new
  `UserInventorySyncWorker`. This is `app_fetcher`'s first class under
  a new `app/services/` layer.
- `InventoriesController#show`: cold-start branch calls
  `UserInventorySyncService.call` instead of enqueuing
  `ItemsListUpdateWorker`; warm path reads through the reshaped
  `UserInventoryCache` from the DB.
- New `InventoriesController#refresh` action, route, and rate-limit
  dedup flag — ships now, not deferred.
- New `UserInventorySyncWorker` + `UserInventorySyncScheduler` (weekly
  cadence, staleness-gated by `user_inventories.updated_at`) —
  Steam-calling content sync, decoupled from value calculation.
- `InventoryValueUpdateWorker`: simplified to a DB-only read/sum/upsert
  — no Steam call, no service dependency, no backfill (structurally
  impossible for it to see an unknown item once
  `user_inventory_items.item_id` is FK-enforced).
- `UserInventoryCache`: interface reshape from TTL-only
  (`.read`/`.write`) to a DB-backed read-shielding cache — exact
  method shape pending `styleguides-check` (see Assumptions).
- The ADR amendment the synchronous-persistence-via-a-new-service
  decision requires (produced by `styleguides-check`, not drafted
  here — see Implementation Approach).
- Tests for every new/changed class listed above.

### Out of Scope

- The actual `app_core`/frontend UI button — confirmed explicitly with
  the user: "ship the button now" means the `app_fetcher` backend
  endpoint ships now (already true), not that this plan grows into a
  cross-app (`fetcher+core`) plan. The `app_core` button remains a
  separate future task.
- Physically separating Steam-calling vs. DB-only workers into
  different folders/namespaces — discussed and explicitly rejected by
  the user this session (would also require either breaking
  `background-jobs.md`'s "workers stay top-level, not namespaced" rule
  or extra Zeitwerk `collapse` configuration; the existing `:prices`
  vs. `:default` queue split already distinguishes them). Do not
  introduce this as a side effect of implementing this plan.
- Quantity/stack-count tracking — explicitly declined by the user;
  `market_hash_names` is already deduplicated
  (`Steam::Response::Data::InventoryData#market_hash_names`,
  `lib/steam/response/data/inventory_data.rb:18-21`), matching today's
  `items_count` semantics exactly.
- Any change to `ItemPriceCache`/`PriceHistoryCache`'s interface or
  `PriceUpdateWorker`'s invalidation.
- Any change to `InventoryValueLog`'s schema, `InventoryValueScheduler`
  itself, or `Api::V1::InventoryValuesController`'s behavior/shape.
- Unifying `InventoryValueLog`'s self-seed trigger
  (`inventory_values#index`) with `user_inventories`' cold-start
  trigger (`inventories#show`) — flagged as a real gap in Risks, but
  fixing it (e.g. seeding both from one visit) is not part of this
  plan.
- Reconciling with `.claude/plans/user-inventory-cache-invalidation.md`
  (status: `blocked`) — that plan covers a narrower, different approach
  to a subset of this problem; the user explicitly disregarded its
  contents for this design. It is not extended, superseded in text, or
  referenced further by this plan. (Note: this plan's final
  `UserInventorySyncService` design independently converges on a shape
  and name close to that old plan's proposed `UserInventorySyncService`
  action object — a coincidence of arriving at a similar answer via a
  fuller design this time, not a reuse of that plan's reasoning.)
- Deciding the fate of `ItemsListUpdateWorker` (see Risks — it likely
  has no remaining callers after this plan) beyond flagging it;
  removing or repurposing it is an explicit implementation-time
  decision, not pre-made here.
- Writing the actual ADR amendment / styleguide text — that is
  `styleguides-check`'s/`create-styleguide`'s job, not this plan's.

## Implementation Approach

**Schema.** Two tables, following this app's existing plain
`create_table`/`add_index`/`add_foreign_key` migration style (see
`db/migrate/20260507094717_create_price_logs.rb`'s
`add_foreign_key "price_logs", "items"` as the one existing FK
precedent):

```ruby
create_table :user_inventories do |t|
  t.string :steam_id, null: false
  t.timestamps
end
add_index :user_inventories, :steam_id, unique: true

create_table :user_inventory_items do |t|
  t.bigint :user_inventory_id, null: false
  t.bigint :item_id, null: false
  t.timestamps
end
add_index :user_inventory_items, [ :user_inventory_id, :item_id ], unique: true
add_foreign_key :user_inventory_items, :user_inventories
add_foreign_key :user_inventory_items, :items
```

`user_inventories` exists as a parent row per `steam_id` specifically
so a literally-empty inventory still has somewhere to carry
`updated_at` ("last synced") — this was a deliberate choice over
deriving staleness from `MAX(user_inventory_items.updated_at)`, which
has no row to read when a user owns nothing. That same `updated_at` is
now also the weekly scheduler's staleness signal (see below).

**The central architectural decision: a new `app/services/` layer,
called synchronously from the controller.** `.claude/adr/fetcher/
layered-ingestion-pipeline.md` currently states `app_fetcher` has no
request-orchestration layer ("there is no `app/actions/` here... not
something this app has or needs") and, separately, that only a worker
(Scenario 3) persists parsed/built data — a controller (Scenario 1) may
parse and render in-memory data (the existing `Item.new` carve-out in
`show`) but must defer actual writes to an async worker. The ADR's own
Risks section explicitly pre-empts reverting the persistence rule.

This plan deliberately introduces both changes together, as one
decision: a new `UserInventorySyncService` service
(`app/services/user_inventory_sync_service.rb`), `app_fetcher`'s first
class under a new `app/services/` layer, which:

1. Calls `Steam::Client#fetch_user_inventory(steam_id)`.
2. Resolves known items (`ItemPriceCache.fetch_for`) vs. missing names,
   parses the missing ones (`Steam::ItemParser.parse`).
3. Backfills missing `Item` rows (`Item.upsert_all`).
4. Persists `user_inventories`/`user_inventory_items`
   (`UserInventory.sync!`).
5. Returns a `Result` (`success`, `error`, `items`).

```ruby
# app/services/user_inventory_sync_service.rb
module Steam
  class ResolveInventory
    extend T::Sig

    class Result < T::Struct
      const :success, T::Boolean
      const :error, T.nilable(String)
      const :items, T.nilable(T::Array[Item])
    end

    class << self
      extend T::Sig

      sig { params(steam_id: String).returns(UserInventorySyncService::Result) }
      def call(steam_id)
        response = Steam::Client.new.fetch_user_inventory(steam_id)
        return Result.new(success: false, error: response.error, items: nil) unless response.success?

        names = response.data.market_hash_names
        known_items = ItemPriceCache.fetch_for(names)
        missing_names = names - known_items.keys
        missing_attrs = missing_names.map { |name| Steam::ItemParser.parse(name) }

        Item.upsert_all(missing_attrs, unique_by: :market_hash_name) if missing_attrs.any?
        backfilled = missing_attrs.empty? ? [] : Item.where(market_hash_name: missing_attrs.map { |a| a[:market_hash_name] })
        all_items = known_items.values + backfilled

        UserInventory.sync!(steam_id, all_items.map(&:id))

        Result.new(success: true, error: nil, items: all_items)
      end
    end
  end
end
```

Namespaced under `Steam::` (per `ruby-sorbet.md`: "anything Steam-related
lives under `Steam::` regardless of which app"), filed under
`app/services/steam/` — mirroring the existing
`app/parsers/steam/`/`app/builders/steam/` folder→namespace convention,
so Zeitwerk needs no special configuration.

> **Post-implementation rename**: code review renamed this class to
> `UserInventorySyncService`, flat under `app/services/` (no `Steam::`
> namespace, no `steam/` subfolder) — the same top-level exception
> `background-jobs.md` already carves out for workers/schedulers that
> call `Steam::Client` without being Steam-domain parsing/building code
> themselves. See `cross-scenario-service-layer.md` and
> `architecture-layers.md` (both updated) for the current, authoritative
> shape; treat every `Steam::ResolveInventory`/`app/services/steam/`
> reference below as historical design-process record, not current fact.

Both callers become a single collaborator call:

```ruby
# InventoriesController#show (cold-start branch) / #refresh
result = UserInventorySyncService.call(current_steam_id)
# render based on result.success — same shape as today's show

# UserInventorySyncWorker#perform(steam_id)
result = UserInventorySyncService.call(steam_id)
return unless result.success  # log and return on failure
```

**Why this is a bigger decision than just "controller persists
synchronously."** An earlier iteration of this plan tried to keep the
exception narrow — a pure resolver (no Steam call, no persistence)
shared between callers, with each caller doing its own persistence
inline. The user explicitly rejected that split (see Design pivot #2):
since the full sequence is identical for both callers, splitting it
only avoided facing the real question. Consolidating it into one
service means `app_fetcher` now has a reusable class that both calls
`Steam::Client` *and* persists, callable from both a controller and a
worker — which is a more substantial change to
`layered-ingestion-pipeline.md`'s stance than a narrow carve-out. The
user explicitly chose to make this change anyway, on the view that
styleguides/ADRs are meant to evolve as the codebase grows, and that
`styleguides-check`'s job is to surface and formalize that evolution,
not block it indefinitely. See Missing Styleguides for exactly what
the resulting ADR amendment must cover.

One upside this consolidation produces, not originally intended but
worth recording: `internal-api-controllers.md`'s "one collaborator per
action" SHOULD rule is now satisfied structurally, with no separate
exception needed — `show`/`refresh` each call exactly one collaborator
(`UserInventorySyncService`), same as any other action in that
controller.

**Weekly content sync, decoupled from daily value calculation.** Two
independent worker/scheduler pairs now exist where there was one:

```text
sidekiq-cron (daily trigger, cheap — gating happens inside)
    ↓
UserInventorySyncScheduler#perform
    ↓ query: UserInventory.where("updated_at < ?", 7.days.ago)
    ⇢ UserInventorySyncWorker.perform_async(steam_id) — only for stale ones
UserInventorySyncWorker#perform(steam_id)
    ↓ UserInventorySyncService.call(steam_id)

sidekiq-cron (daily trigger)
    ↓
InventoryValueScheduler#perform   (unchanged — queries InventoryValueLog)
    ⇢ InventoryValueUpdateWorker.perform_async(steam_id)
InventoryValueUpdateWorker#perform(steam_id)
    ↓ UserInventory.find_by(steam_id)&.user_inventory_items&.includes(:item)
    ↓ sum current_price_cents (nil → 0, same as today)
    ↓ InventoryValueLog.upsert_all(...)   — no Steam::Client call
```

`UserInventorySyncScheduler` runs on a daily cron trigger like every
other scheduler (cheap, no I/O, per `architecture-layers.md`'s
Scenario 2) — but its own staleness filter means any given `steam_id`
only actually triggers a Steam call roughly once every 7 days, not
every time the scheduler itself runs. This also means a user who
manually refreshes, or who just had their cold-start sync, is
correctly skipped by that week's pass with no separate bookkeeping —
`user_inventories.updated_at` is a single signal shared by all three
write paths (weekly worker, cold start, manual refresh), since all
three go through the same `UserInventorySyncService.call` →
`UserInventory.sync!`.

**`UserInventory.sync!`, a plain model method, called internally by
`UserInventorySyncService`.** The "replace this steam_id's
`user_inventory_items`" step is pure AR persistence with no branching
on external failure and no orchestration beyond a delete+bulk-insert —
unlike the cache read-through case `price-cache-invalidation.md`
deliberately pulled off the model, this fits `rails-layering.md`'s
"Models: persistence + validations only" directly:

```ruby
# on UserInventory
sig { params(steam_id: String, item_ids: T::Array[Integer]).void }
def self.sync!(steam_id, item_ids)
  transaction do
    user_inventory = find_or_create_by!(steam_id: steam_id)
    user_inventory.touch
    UserInventoryItem.where(user_inventory_id: user_inventory.id).delete_all
    UserInventoryItem.insert_all(item_ids.map { |id| { user_inventory_id: user_inventory.id, item_id: id, created_at: Time.current, updated_at: Time.current } }) if item_ids.any?
  end
end
```

Wrapped in a transaction — a partial delete+insert must not leave
`updated_at` touched without the rows actually matching, per
`background-jobs.md`'s consistency rule even though this lives on a
model rather than in a worker. Only `UserInventorySyncService` calls
this method; it's no longer called directly by the controller or
`UserInventorySyncWorker` themselves (see Design pivot #2).

**`InventoryValueUpdateWorker`, now DB-only.** No `Steam::Client`, no
service dependency, no backfill, no failure branch beyond ordinary
Sidekiq retry on a genuine DB error. Moves off the `:prices` queue
(reserved for Steam-calling work, per `background-jobs.md`) onto
`:default`, with a lower retry count matching
`ItemsListUpdateWorker`'s (3, not `PriceUpdateWorker`'s
Steam-flakiness-driven 5) — it's cheap local work now, not a
rate-limited external call:

```ruby
sig { params(steam_id: String).void }
def perform(steam_id)
  user_inventory = UserInventory.find_by(steam_id: steam_id)
  total_value_cents = user_inventory&.items&.sum { |item| item.current_price_cents || 0 } || 0

  InventoryValueLog.upsert_all(
    [ { steam_id: steam_id, log_date: Date.current, total_value_cents: total_value_cents } ],
    unique_by: [ :steam_id, :log_date ]
  )
end
```

(`&.` handles the "self-seeded into `InventoryValueLog` but never
visited `inventories#show`" edge case from Expected Behavior — no
`user_inventory` row yet is treated the same as a zero-item one.)

**Read path.** `UserInventoryCache` stops being the only copy of the
data and becomes a read-shielding cache in front of
`user_inventories`/`user_inventory_items`/`items` — purely to avoid a
DB round-trip on every dashboard render, not a freshness mechanism
(freshness now comes from the weekly sync + manual refresh). This
likely moves it from today's TTL-only `.read`/`.write` shape (per
`caching.md`, chosen specifically because "there is no write path in
this app to hook an explicit `.invalidate` into" — no longer true once
the sync writes the DB) to the read-through + invalidate
(`.fetch_for`/`.invalidate`) shape `ItemPriceCache`/`PriceHistoryCache`
already use, invalidated from the same sync paths that call
`UserInventory.sync!` (i.e. from inside `UserInventorySyncService`). The
user explicitly ruled out HTTP-level caching (conditional GET/ETag) in
favor of this. Treat the exact final method names/shape as pending
`styleguides-check`'s confirmation, not settled by this plan.

**Worker/namespace organization — explicitly not changed.** The user
raised, then explicitly dropped, the idea of physically separating
Steam-calling workers (`PriceUpdateWorker`, the new
`UserInventorySyncWorker`) from DB-only ones
(`InventoryValueUpdateWorker`, and formerly `ItemsListUpdateWorker`)
into different folders/modules. All workers stay flat under
`app/workers/`, top-level naming, per the existing
`background-jobs.md` rule — this plan does not touch that structure.
(The new `app/services/` layer is a different, deliberate structural
change — see above — not a reopening of this rejected one.)

## Files To Modify

- `app_fetcher/app/controllers/api/v1/inventories_controller.rb` —
  `show`'s cold-start branch calls `UserInventorySyncService.call(current_steam_id)`
  instead of enqueuing `ItemsListUpdateWorker`; warm path reads through
  the reshaped `UserInventoryCache`. Add `refresh` action +
  `REFRESH_DEDUP_TTL` constant, calling the same service after the
  rate-limit check passes. `save_missing_items`/`enqueue_price_warmup`
  interplay reviewed — `save_missing_items` is removed (superseded by
  the service's own backfill).
- `app_fetcher/app/workers/inventory_value_update_worker.rb` —
  simplified to a pure DB read/sum/upsert (see Implementation
  Approach); drops `Steam::Client` entirely; `sidekiq_options` moves
  from `queue: :prices, retry: 5` to `queue: :default, retry: 3`.
- `app_fetcher/app/caching/user_inventory_cache.rb` — reshape to
  read-through + invalidate over the new tables (see Implementation
  Approach; exact shape pending `styleguides-check`).
- `app_fetcher/config/routes.rb` — add
  `post "inventories/refresh", to: "inventories#refresh"`.
- `app_fetcher/config/schedule.yml` — add a daily cron entry for the
  new `UserInventorySyncScheduler`, alongside the existing
  `PriceScheduler`/`InventoryValueScheduler` entries.
- `app_fetcher/db/schema.rb` — regenerated by the new migration.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — update
  existing examples for the new persist-on-cold-start behavior (assert
  DB rows, not just enqueued jobs); add a `POST /api/v1/inventories/refresh`
  context.
- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb` —
  rewritten: drop all `WebMock`/Steam-failure examples (no longer
  applicable); seed `user_inventory`/`user_inventory_items` directly
  via factories instead; remove the "item with no Item row at all"
  example entirely (structurally impossible now, see Implementation
  Approach) — its coverage is superseded by
  `resolve_inventory_spec.rb`'s backfill examples; add a "no
  `user_inventory` row yet for this steam_id" example asserting
  `total_value_cents: 0`, no error.
- `app_fetcher/spec/caching/user_inventory_cache_spec.rb` — rewritten
  for the new interface.
- `.claude/adr/fetcher/layered-ingestion-pipeline.md`,
  `.claude/styleguides/fetcher/architecture-layers.md`,
  `.claude/styleguides/fetcher/caching.md` — flagged for
  `create-styleguide-from-scratch`/`create-styleguide`/ADR-amendment;
  not edited by this plan.

## Files To Create

- `app_fetcher/db/migrate/<timestamp>_create_user_inventories.rb`,
  `app_fetcher/db/migrate/<timestamp>_create_user_inventory_items.rb`
  — the new schema (see Implementation Approach).
- `app_fetcher/app/models/user_inventory.rb` — `UserInventory`:
  `has_many :user_inventory_items, dependent: :destroy`, `has_many
  :items, through: :user_inventory_items`, `validates :steam_id,
  presence: true, uniqueness: true`, `self.sync!`.
- `app_fetcher/app/models/user_inventory_item.rb` — `UserInventoryItem`:
  `belongs_to :user_inventory`, `belongs_to :item`.
- `app_fetcher/app/services/user_inventory_sync_service.rb` —
  `UserInventorySyncService` (see Implementation Approach). Necessary
  because the full fetch→resolve→backfill→persist sequence now runs
  identically from two independent call sites
  (`InventoriesController`, `UserInventorySyncWorker`) and needs to be
  independently unit-testable without an HTTP round-trip.
- `app_fetcher/app/workers/user_inventory_sync_worker.rb` —
  `UserInventorySyncWorker`: thin Sidekiq wrapper calling
  `UserInventorySyncService.call(steam_id)`, logging and returning on
  failure.
- `app_fetcher/app/schedulers/user_inventory_sync_scheduler.rb` —
  `UserInventorySyncScheduler`: queries `UserInventory` for
  `updated_at`-stale rows, fans out via `.perform_async`. Scenario 2,
  no `Steam::Client` dependency, mirroring `PriceScheduler`'s shape.
- `app_fetcher/spec/models/user_inventory_spec.rb` — covers
  `.sync!`: full replace (old rows gone, new rows present), `touch`
  behavior, empty `item_ids` (zero-item inventory), idempotent repeat
  call.
- `app_fetcher/spec/models/user_inventory_item_spec.rb` — association/
  validation coverage.
- `app_fetcher/spec/services/steam/resolve_inventory_spec.rb` — the
  main new unit spec (see Test Plan): Steam success with all-known
  names, Steam success with a mix requiring backfill, Steam failure,
  repeat-call full-replace semantics.
- `app_fetcher/spec/workers/user_inventory_sync_worker_spec.rb` — thin:
  delegates to `UserInventorySyncService.call` and logs on failure (its
  own edge cases live in `resolve_inventory_spec.rb`, per
  `rspec-conventions.md`'s "prefer a unit spec over a request spec to
  exercise a class's edge cases" — the same reasoning now applies one
  level up, to the worker vs. the service it delegates to).
- `app_fetcher/spec/schedulers/user_inventory_sync_scheduler_spec.rb`
  — enqueues only for stale `user_inventories` rows, skips fresh ones,
  enqueues nothing when no rows exist (mirrors
  `inventory_value_scheduler_spec.rb`'s shape).
- `app_fetcher/spec/factories/user_inventories.rb`,
  `app_fetcher/spec/factories/user_inventory_items.rb` — FactoryBot,
  per `rspec-conventions.md`.

## Test Plan

- **`spec/models/user_inventory_spec.rb`** (unit, no `type:`):
  `.sync!` replaces a prior item set entirely (old `user_inventory_item`
  rows for that steam_id gone, new ones present); handles an empty
  `item_ids` array (zero rows, parent row still touched); calling it
  twice in a row is idempotent (no duplicate-key error, final state
  matches the second call's input); `steam_id` uniqueness validated.
- **`spec/services/steam/resolve_inventory_spec.rb`** (unit, no
  `type:`, `WebMock`-stubbed Steam call per `rspec-conventions.md`):
  Steam success, all names already known (no backfill,
  `UserInventory.sync!` called with existing ids, `result.success` true);
  Steam success, mix of known/unknown (unknown ones backfilled into
  `Item`, included in the synced id list and in `result.items`); Steam
  failure (`success: 0`/`429`/`5xx` via `WebMock`) → `result.success`
  false, `result.error` set, no DB write, `user_inventories.updated_at`
  untouched; a second call for the same `steam_id` fully replaces the
  prior item set (an item owned last call but absent this call is
  gone).
- **`spec/workers/user_inventory_sync_worker_spec.rb`** (unit, no
  `type:`): calls `UserInventorySyncService.call` with the given
  `steam_id`; on failure, logs
  `[UserInventorySyncWorker] Failed for <steam_id>: <error>` and
  returns — no re-raising.
- **`spec/schedulers/user_inventory_sync_scheduler_spec.rb`** (unit,
  `Sidekiq::Testing.fake!`): a `steam_id` with `updated_at` older than
  7 days gets enqueued; one updated within the last 7 days does not;
  no `user_inventories` rows at all → enqueues nothing.
- **`spec/requests/api/v1/inventories_spec.rb`**: existing cold-start
  example updated to assert `user_inventories`/`user_inventory_items`
  rows exist immediately after the response (not just that a worker
  was enqueued); warm-path example (existing `user_inventories` row)
  asserts no Steam call and no DB write beyond the read; new
  `POST /api/v1/inventories/refresh` context: happy path (re-fetches,
  `have_been_made.once` scoped to the refresh call, full-replaces
  `user_inventory_items`, same response shape as `show`); rate-limited
  repeat call same window → `429`, no Steam call; cold refresh (no
  prior `GET`) still succeeds. Existing warmup-cap/dedup examples stay,
  unaffected by this change. Per `rspec-conventions.md`'s
  responsibilities split, this file now owns boundary concerns (auth,
  status/render shape, one representative happy path per action) —
  exhaustive backfill/failure branches live in
  `resolve_inventory_spec.rb`.
- **`spec/workers/inventory_value_update_worker_spec.rb`**: existing
  priced/unpriced/already-logged examples stay as regression coverage,
  rewritten to seed `user_inventory`/`user_inventory_items` via
  factories instead of stubbing Steam; the "unknown item"/Steam-failure
  examples are removed (no longer applicable — see Files To Modify);
  new example: no `user_inventory` row at all for this `steam_id` →
  `total_value_cents: 0`, no error (the two-independent-self-seeds edge
  case from Expected Behavior).
- **`spec/caching/user_inventory_cache_spec.rb`**: rewritten per
  `caching.md`'s read-through+invalidate testing rules — asserts
  against real `Rails.cache`/DB state, not mocks; a request-spec-level
  "no DB query on second request" assertion (via
  `ActiveSupport::Notifications` subscription, per `caching.md`'s MUST)
  should be added to `inventories_spec.rb`'s warm-path example if not
  already adequately covered there.

## Implementation Steps

1. Migration + `UserInventory`/`UserInventoryItem` models + factories;
   TDD `.sync!` (with its transaction) against
   `spec/models/user_inventory_spec.rb` (replace semantics,
   empty-array case, idempotency).
2. `UserInventorySyncService`, TDD against
   `spec/services/steam/resolve_inventory_spec.rb` — depends on
   `UserInventory.sync!` from step 1; covers the full Steam
   success/failure/backfill/replace matrix (see Test Plan).
3. `UserInventorySyncWorker` + `UserInventorySyncScheduler`, thin
   wrappers, TDD against their new spec files.
4. Simplify `InventoryValueUpdateWorker` to the DB-only shape; move its
   `sidekiq_options` to `:default`/`retry: 3`; rewrite its spec per
   Test Plan. Re-run the full existing worker + scheduler spec files
   to confirm `InventoryValueScheduler`'s own fan-out is unaffected.
5. Rewrite `InventoriesController#show`'s cold-start branch to call
   `UserInventorySyncService.call`; point the warm path at the reshaped
   `UserInventoryCache`. Re-run the full existing `inventories_spec.rb`
   suite before adding anything new, to isolate this extraction's own
   regressions from the new `refresh` feature.
6. Add the `refresh` action, route, and rate-limit dedup flag; TDD
   against new `inventories_spec.rb` contexts (happy path, rate-limited
   repeat, cold refresh, Steam-failure).
7. Reshape `UserInventoryCache` to the read-through+invalidate
   interface once `styleguides-check` confirms the exact shape;
   rewrite its spec accordingly.
8. Add the `UserInventorySyncScheduler` cron entry to
   `config/schedule.yml`.
9. Full regression pass across all touched spec files (see Test Plan).

## Verification

- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"` — full suite green.
- `docker compose run --rm app_fetcher bash -c "bin/rubocop <touched files> -f simple"`.
- `docker compose run --rm app_fetcher bash -c "bundle exec srb tc"` — compare error count/category against the existing baseline recorded in `fetcher-price-caching.md`'s Verification section; no new category introduced.
- `docker compose run --rm app_fetcher bin/brakeman --no-pager`.
- Manual: `curl` a cold-start `GET /api/v1/inventories/me` for a
  never-seen `steam_id` and confirm `user_inventories`/
  `user_inventory_items` rows exist in the DB immediately, not just
  that the HTTP response looks right; confirm a same-day repeat
  `POST /api/v1/inventories/refresh` is rejected; confirm
  `UserInventorySyncScheduler#perform` enqueues nothing for a freshly
  cold-started `steam_id` (it's not 7 days stale yet); rough latency
  sanity check on the cold-start/refresh path now that it does
  synchronous DB writes, not just a Steam call.

## Risks

- **Hard precondition on the ADR amendment, now broader in scope.**
  This plan's central design choice — a new `app/services/` layer
  whose first class both calls `Steam::Client` and persists, called
  synchronously from a controller — is not valid without the amendment
  described in Implementation Approach. This is a larger change to
  `layered-ingestion-pipeline.md`'s stance than a narrow
  synchronous-persistence carve-out alone would have been; the user
  made this call explicitly and with full awareness of the tradeoff
  (see Design pivot #2). `styleguides-check` must produce the
  amendment before `implement-plan` proceeds with steps 2, 5, and 6
  above; if it's declined or revised, this plan's Implementation
  Approach needs rework, not a quiet workaround.
- **`UserInventoryCache`'s new interface shape is a proposal, not a
  confirmed design.** If `styleguides-check` lands on something other
  than `.fetch_for`/`.invalidate`, Implementation Step 7 and the
  corresponding spec rewrite need to follow that instead.
- **`UserInventorySyncService`'s location (`app/services/`) is
  unprecedented** in this app (no existing `app/services/` directory)
  — same category of decision `app/caching/` needed its own ADR for
  before first use, but larger in scope here since this class also
  persists and calls `Steam::Client` (not just reads, like
  `app/caching/` classes do). `styleguides-check` may redirect its
  namespace/location/shape, though the namespacing under `Steam::` and
  the `app/services/<domain>/` folder convention mirroring
  `app/parsers/steam/`/`app/builders/steam/` are reasonably
  well-grounded in existing precedent.
- **`ItemsListUpdateWorker` likely has no remaining callers** after
  this plan — `show`'s cold-start path now calls
  `UserInventorySyncService` instead of enqueuing it, which does its own
  inline backfill rather than deferring to it. This plan deliberately
  does not decide its fate (keep as dead code pending a future caller,
  repurpose, or delete) — flagged for an explicit call during
  `implement-plan`, not assumed away.
- **Two independent self-seed triggers** (`inventory_values#index` for
  `InventoryValueLog`, `inventories#show` for `user_inventories`) can
  now diverge in a new way: a `steam_id` self-seeded into one but not
  the other produces a correct-but-uninformative `total_value_cents: 0`
  until they visit the other endpoint too. Not a bug introduced by this
  plan (the gap exists today in a different shape), but worth a
  deliberate look at whether the dashboard's actual request pattern
  (see `app_core`'s recent "render dashboard items before price
  history loads" change) already calls both close enough together that
  this rarely matters in practice, or whether it's a real
  user-visible gap.
- **Weekly staleness means the value chart can reflect a stale
  composition for up to 7 days** if a user neither revisits nor clicks
  refresh — an explicitly accepted tradeoff (see Goal), not an
  oversight, but worth calling out again here since it's the main
  behavioral cost of this design relative to the daily-coupled
  alternative that was considered and dropped.
- **Added request latency on cold-start/refresh** from
  `UserInventorySyncService`'s synchronous `Item.upsert_all` +
  `user_inventories`/`user_inventory_items` writes — accepted by the
  user, but worth the manual latency check in Verification, not
  assumed negligible by default.
- **`InventoryValueUpdateWorker`'s spec needs a near-complete rewrite**,
  not an incremental edit — its Steam-stubbing setup disappears
  entirely and its test data now comes from factories instead. Treat
  this as a fresh file, cross-checking against the *behavior* the old
  examples verified (priced sum, unpriced-counts-as-0,
  already-logged-today-updates-in-place) rather than trying to
  line-edit the old `WebMock`-based version.
- **Full-replace on every sync** (delete+insert, not diff) means a
  sync that partially fails mid-write could leave
  `user_inventory_items` inconsistent with `user_inventories.updated_at`
  having already been touched — mitigated by wrapping
  `UserInventory.sync!`'s delete+insert pair in a transaction (now
  reflected in Implementation Approach's code sketch).

## Assumptions

- **Weekly staleness threshold = 7 days.** The user's own earlier
  reference point ("Steam inventories change at least once every few
  weeks, sometimes once a week for case drops") and the original
  TTL-sizing discussion both land here; not a derived constant the way
  the warmup cap/dedup numbers elsewhere in this codebase are — a
  product judgment call, confirm it feels right once shipped.
- **Manual refresh rate-limit window.** Discussed as "a button, rate
  limited" without the user pinning an exact number in this session;
  this plan assumes once per `steam_id` per day, mirroring the shape
  of the existing warmup-dedup pattern (`Rails.cache.write(key, true,
  unless_exist: true, expires_in: ...)`) — not derived from a specific
  Prop config. Confirm or adjust during implementation.
- **`UserInventoryCache`'s final public interface** — assumed
  read-through + invalidate (`.fetch_for`/`.invalidate`) as the most
  likely fit now that a DB source of truth and a real write/invalidate
  event both exist; not confirmed by `styleguides-check` yet.
- **`UserInventorySyncService`'s location/name**
  (`app/services/user_inventory_sync_service.rb`) — a starting proposal
  only; `styleguides-check` owns the final call, same as it owned
  `app/caching/`'s placement originally.
- **`UserInventory.sync!` as a model class method** (rather than a
  separate top-level class) — assumed to fit `rails-layering.md`'s
  "Models: persistence + validations only" since it's pure bulk
  persistence with no branching on external failure; `styleguides-check`
  should confirm this reading holds, since it's adjacent to (but
  distinct from) the orchestration shape `price-cache-invalidation.md`
  deliberately pulled off models.
- **`UserInventorySyncScheduler`'s own cron cadence** is assumed daily
  (cheap, no I/O — the staleness filter is what actually bounds Steam
  calls to roughly weekly per user), matching every other scheduler's
  trigger cadence in this app, rather than configuring a literal
  once-a-week cron entry. Either achieves the same effect; daily is
  simpler and naturally staggers load across the week.
- No `app_core`/frontend trigger exists yet for `POST
  /api/v1/inventories/refresh` — confirmed explicitly with the user as
  separate future work; this plan ships only the backend endpoint.

## Applicable Styleguides

Re-checked after `create-styleguide-from-scratch`/`create-styleguide`
produced the three previously-missing documents below, all approved by
the user. Every technical area this plan touches now has sufficient,
project-specific guidance.

- **`.claude/adr/fetcher/cross-scenario-service-layer.md`** (new) —
  constrains Implementation Approach's central decision in full: the
  existence and narrow scope of the new `app/services/` layer,
  `UserInventorySyncService`'s location/namespacing
  (`app/services/user_inventory_sync_service.rb`), the carve-out permitting
  it to call `Steam::Client` and persist, and the carve-out permitting
  `InventoriesController#show`'s cold-start branch and `#refresh` to
  call it synchronously. Also governs that this exception does not
  generalize beyond these named call sites.
- **`.claude/adr/fetcher/layered-ingestion-pipeline.md`** (amended with
  a cross-reference to the ADR above) — constrains everything about
  `app_fetcher`'s existing layering this plan leaves unchanged: the
  general "only a worker persists" rule for every other controller
  action, `ItemsListUpdateWorker`'s own unrelated role, and the
  three-Scenario map `InventoryValueUpdateWorker`/
  `UserInventorySyncWorker`/`UserInventorySyncScheduler` all still fit
  into without modification.
- **`.claude/styleguides/fetcher/architecture-layers.md`** (amended) —
  constrains `UserInventorySyncService`'s Structure placement
  (`app/services/<domain>/`, namespaced, mirroring
  `app/parsers/steam/`/`app/builders/steam/`), its allowed dependencies
  (`Steam::Client`, `ItemPriceCache`, `Steam::ItemParser`, models), and
  confirms it as this layer's first Canonical Implementation.
- **`.claude/styleguides/fetcher/caching.md`** (amended) — constrains
  `UserInventoryCache`'s new interface: the single-key read-through +
  invalidation variant, `.fetch(steam_id)`/`.invalidate(steam_id)`, a
  single DB query (not `read_multi`) on a miss, and that
  `UserInventorySyncService` is the sole caller of `.invalidate`.
- **`.claude/styleguides/fetcher/background-jobs.md`** (unchanged,
  sufficient as-is) — constrains `UserInventorySyncWorker`'s queue/retry
  (`:prices`, `retry: 5`, matching `PriceUpdateWorker`'s Steam-calling
  shape), `UserInventorySyncScheduler`'s Scenario-2 shape (no
  `Steam::Client`, query-then-`.perform_async` only), and
  `InventoryValueUpdateWorker`'s move to `:default`/`retry: 3` once it
  no longer calls Steam.
- **`.claude/styleguides/fetcher/internal-api-controllers.md`**
  (unchanged, sufficient as-is — the "one collaborator per action"
  SHOULD rule is satisfied structurally by `show`/`refresh` each
  calling exactly one collaborator, `UserInventorySyncService`; no
  amendment needed, see Design pivot #2) — constrains the response
  shape, auth, and routing for `refresh`.
- **`.claude/styleguides/rails-layering.md`** (unchanged, sufficient
  as-is) — constrains `UserInventory.sync!`'s placement as a plain
  model method (persistence only, no orchestration, no external I/O).
- **`.claude/styleguides/ruby-sorbet.md`** (unchanged, sufficient as-is)
  — constrains Sorbet typing (`# typed: strict`, `sig` on every method,
  `T.let` on constants, `Steam::` namespacing) across every new class.
- **`.claude/styleguides/rspec-conventions.md`** (unchanged, sufficient
  as-is) — constrains test level placement for every new/changed spec
  (unit for models/services/workers/schedulers, request for the
  controller, `FactoryBot`, `WebMock` at the unit level,
  `Sidekiq::Testing.fake!` for enqueue assertions).

## Completion Criteria

- [x] Desired behavior made explicit (persistence, decoupled
  weekly/daily sync cadence, refresh endpoint, edge/failure cases).
- [x] Scope explicit (no frontend work, no quantity tracking, no
  changes to price caches or the value-log chart's own shape, no
  worker folder reorg).
- [x] Affected files/components identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides — see "Applicable Styleguides"
  above; all three previously-missing documents are now in place and
  approved.
- [x] Implemented — see Implementation Summary below.

# Implementation Summary

## Implemented

- **Schema**: `user_inventories` (parent, unique `steam_id`) and
  `user_inventory_items` (join to `items`, FK-enforced, unique
  `(user_inventory_id, item_id)`) via two migrations.
- **Models**: `UserInventory` (`has_many :items, through:`,
  `UserInventory.sync!` — transactional full-replace + `touch`) and
  `UserInventoryItem`.
- **`UserInventorySyncService`** (`app/services/user_inventory_sync_service.rb`,
  `app_fetcher`'s first `app/services/` class): fetches from Steam,
  resolves known/missing items via `ItemPriceCache`/`Steam::ItemParser`,
  backfills missing `Item`s, calls `UserInventory.sync!`, invalidates
  `UserInventoryCache`, returns a `Result`.
- **`UserInventorySyncWorker`/`UserInventorySyncScheduler`**: weekly
  Steam-calling content sync, gated by `user_inventories.updated_at`
  staleness (7 days), decoupled from value calculation.
- **`InventoryValueUpdateWorker`**: simplified to a pure DB read/sum/
  upsert — no `Steam::Client`, moved `:prices`→`:default` queue,
  `retry: 5`→`3`.
- **`InventoriesController`**: `show`'s cold-start branch and new
  `refresh` action each call `UserInventorySyncService.call` as their
  single collaborator; warm path reads through the reshaped
  `UserInventoryCache`. New `POST /api/v1/inventories/refresh` route,
  rate-limited once/day via the existing dedup-flag pattern.
- **`UserInventoryCache`**: reshaped from TTL-only (`.read`/`.write`) to
  single-key read-through + invalidation (`.fetch`/`.invalidate`),
  `CACHE_KEY_VERSION` bumped 1→2 (payload shape changed from
  `Array[String]` to `Array[Item]`).
- **`ItemsListUpdateWorker`**: deleted (zero remaining callers after the
  above — confirmed via full-codebase grep; explicitly approved by the
  user). Its role as the canonical example in
  `layered-ingestion-pipeline.md`, `architecture-layers.md`,
  `background-jobs.md`, and `internal-api-controllers.md` was corrected
  in each: either swapped for a still-live example
  (`InventoryValueUpdateWorker`, `UserInventorySyncWorker`) or marked
  "no current implementation, rule still applies" where no live
  replacement exists.
- `config/routes.rb`, `config/schedule.yml` (new daily cron entry for
  `UserInventorySyncScheduler`) updated.
- `spec/rails_helper.rb`: added `ActiveSupport::Testing::TimeHelpers`
  (needed for `UserInventory.sync!`'s `touch`-behavior spec).
- Logged two incidental findings in `fix_me.md` (not fixed inline, out
  of scope): `InventoryValueScheduler` missing an explicit
  `sidekiq_options retry:` (same deviation already flagged for
  `PriceScheduler`); updated the retry-count comparator example there
  from the now-deleted `ItemsListUpdateWorker` to
  `InventoryValueUpdateWorker`.

## Tests

- `spec/models/user_inventory_spec.rb`, `spec/models/user_inventory_item_spec.rb` (new)
- `spec/services/user_inventory_sync_service_spec.rb` (new)
- `spec/workers/user_inventory_sync_worker_spec.rb` (new)
- `spec/schedulers/user_inventory_sync_scheduler_spec.rb` (new)
- `spec/workers/inventory_value_update_worker_spec.rb` (rewritten —
  factory-seeded, no more Steam stubbing)
- `spec/caching/user_inventory_cache_spec.rb` (rewritten for the new
  interface)
- `spec/requests/api/v1/inventories_spec.rb` (rewritten — cold start,
  cache-warm path, price warmup, Steam failure, plus a new
  `POST /api/v1/inventories/refresh` describe block)
- `spec/factories/user_inventories.rb`, `spec/factories/user_inventory_items.rb` (new)
- Deleted: `spec/workers/items_list_update_worker_spec.rb`

Commands executed (TDD, RED confirmed before every GREEN):
```
docker compose up -d db_fetcher redis
docker compose run --rm app_fetcher bash -c "bin/rails db:migrate RAILS_ENV=test"
docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"
```

## Verification

- **Full suite**: `RAILS_ENV=test bundle exec rspec` — **82 examples, 0
  failures**.
- **Rubocop** (all new/touched app files): `bin/rubocop <files> -f simple`
  — **10 files inspected, no offenses detected**.
- **`srb tc`**: 82 errors, up from a previously-recorded 59-error
  baseline (an earlier point in this codebase's history, not an
  immediately-prior snapshot). Verified by category, not just count: every
  error code present (5002, 6002, 7002, 7003, 7005, 7017, 7027, 7048) was
  already a pre-existing category (unresolved `Sidekiq`/`RSpec`/
  `FactoryBot`/`JWT`/`Cors`/`Redis` gem constants, untyped AR attribute
  readers, a pre-existing missing `sig` on `Item#stattrak`, nilable
  `Steam::Response#data` access without `T.must` — the same pattern
  `PriceUpdateWorker` already has). No new category introduced; the
  count increase is new instances of these same pre-existing gaps on new
  files (new Sidekiq workers/schedulers, new specs requiring
  `rails_helper`).
- **Brakeman**: `bin/brakeman --no-pager` exits non-zero before scanning
  due to its `--ensure-latest` flag detecting a newer Brakeman release
  is available (8.0.4 installed vs. 8.1.0 latest) — an environment/gem-
  staleness issue unrelated to this change. Ran the actual scan directly
  via `bundle exec brakeman --no-pager -q`: **0 new warnings**; the one
  existing warning (`Unmaintained Dependency: Rails 7.2.3.1 EOL`) is
  pre-existing and unrelated.

## Deviations

- **`ItemsListUpdateWorker` deleted**, which the plan's own Risks section
  left as an open implementation-time call. Confirmed zero remaining
  callers, got explicit user sign-off before deleting, and additionally
  corrected the four governing docs that used it as their canonical
  example — a larger documentation touch-up than the plan anticipated,
  also explicitly approved by the user mid-implementation.
- **`UserInventoryCache.fetch`'s `skip_nil: true`**: not explicitly
  spelled out in the plan's code sketch. `Rails.cache.fetch` caches a
  block's `nil` result by default, which would have made "never synced"
  indistinguishable from "cache populated with nil" on the next read.
  Caught by the TDD RED/GREEN cycle itself (a test expecting no cache
  write on a miss failed against the first implementation), not a
  deviation from intended behavior — just an implementation-detail fix
  needed to make the plan's actual intent work.
- **`UserInventorySyncService` calling `UserInventoryCache.invalidate`**:
  the plan's Applicable Styleguides section named this requirement
  (from `caching.md`'s amendment) but the plan's own code sketch for the
  service omitted the call. Added it, with a dedicated spec example, to
  match the styleguide's actual rule.

## Remaining Issues

- `UserInventorySyncScheduler`'s cron entry runs daily at 01:00 (cron
  `"0 1 * * *"`) — a specific hour wasn't specified anywhere in the plan
  or prior discussion; chosen to run shortly after
  `InventoryValueScheduler`'s existing midnight entry, not derived from
  any stated constraint. Revisit if a different time is preferred.
- No `app_core`/frontend work — confirmed out of scope; the backend
  `POST /api/v1/inventories/refresh` endpoint has no caller yet outside
  tests.
- `InventoryValueScheduler`'s own missing `sidekiq_options retry:` (a
  pre-existing deviation, now also logged in `fix_me.md` alongside the
  already-known `PriceScheduler` one) was not fixed — out of scope for
  this plan, flagged for a future pass.
