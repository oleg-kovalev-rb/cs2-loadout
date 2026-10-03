---
status: implemented
app: fetcher+core
goal: Split app_fetcher's inventory/price API into a 5-endpoint shape (persisted skeleton inventory, batch hot prices, batch micro-trend, real portfolio-value history, per-item price history) and rewire app_core's dashboard to consume it
created: 2026-09-29
---

# Development Plan

## Goal

Implement the API design the user specified in chat, adjusted per a series
of explicit decisions made across `research-codebase`, this plan, and a
later revision once a separate, already-implemented plan
(`.claude/plans/user-inventory-persistence.md`) landed a persistent
per-user inventory store mid-session:

1. No `:steam_id` in any route path — identity stays `current_steam_id`
   from the bridge JWT everywhere, matching every existing endpoint.
2. Endpoint 2 ("hot prices") reuses the existing Solid-Cache-backed
   `ItemPriceCache` instead of introducing Redis as a second cache store.
3. Endpoint 3 ("portfolio value history") reuses the existing
   `InventoryValueLog` table/self-seeding pattern instead of a new
   `portfolio_snapshots` table plus per-period Solid Cache presets fed by
   a dedicated nightly worker.
4. Endpoint 4 ("per-item history") sources its price from
   `PriceLog#lowest_price_cents` — the same column every other price in
   this system already uses — not `median_price_cents` as the originally
   pasted example implied. `Item#current_price_cents` (and therefore
   endpoint 2, the inventory-value sum, and the Redis price stream) is
   built exclusively from `lowest_price_cents`; `median_price_cents` is
   stored but read nowhere. Using it for history alone would make the
   detail chart's latest point disagree with the price shown everywhere
   else for the same item.
5. A fifth endpoint, **not present in the original 4-endpoint design**,
   is added: `item_prices/trend` — a batch, heavily downsampled (~5
   points/item, 7-day window) price trend, backed by a new
   `ItemTrendCache`. This exists because the original design has no way
   to feed `ItemRow`'s sparkline or `MarketVolumeTile`'s aggregate volume
   — both need a short series for many items at once, and endpoint 5
   (per-item history) is explicitly single-item. See "Why a 5th
   endpoint" below.
6. No pagination is added to endpoint 1 (the inventory skeleton) despite
   its item count scaling with inventory size — considered and rejected,
   see Out of Scope.
7. No additional inventory-size cap is added beyond what already
   exists — `Steam::Client#fetch_user_inventory` requests `count: 2000`
   and does not follow Steam's continuation token, so anything past
   ~2000 raw Steam assets is already silently dropped today. This plan
   makes that existing limit observable (log a warning on `more_items`)
   rather than adding a second, redundant cap.
8. Endpoint 2 (dynamics)'s price-warmup (`enqueue_price_warmup`) gives no
   signal to the caller about when a warmed-up price actually lands. Two
   alternatives (synchronous Steam calls inline; a WebSocket/SSE
   consumer for the already-existing-but-unconsumed `prices_stream`
   Redis stream) were considered and rejected in favor of a **bounded
   client-side retry**. See "Why bounded retry" below.
9. **Revision, made after `.claude/plans/user-inventory-persistence.md`
   landed mid-session:** endpoints 2 and 3 were originally designed to
   accept an explicit `market_hash_names` array from the client (as a
   `POST` body, per a `styleguides-check` correction — see superseded
   reasoning further down) because, at the time, `app_fetcher` had no
   durable record of what a `steam_id` owns — only a 5-minute
   `Rails.cache` entry with no real invalidation, too fragile to lean on
   for "what should I fetch prices for." That gap is now closed:
   `UserInventoryCache.fetch(steam_id)` reads through a real,
   FK-enforced `user_inventories`/`user_inventory_items` table,
   invalidated by event (on every sync/refresh), not just a TTL. Both
   endpoints are revised to take **no body/params at all** — plain `GET`,
   deriving the owned-item list from the same `UserInventoryCache.fetch`
   call `InventoriesController#show`'s warm path already makes. See
   "Why endpoints 2/3 need no params" below for the full reasoning and
   why this also resolves two Risks this plan previously carried.

The five endpoints, after all of the above:

1. `GET /api/v1/inventories/me` (route unchanged) — inventory skeleton,
   **no price fields** in the response.
2. `GET /api/v1/item_prices/dynamics` (new, **no params**) — current
   price + 24h change/percent for every item the authenticated user owns
   (a snapshot, no series).
3. `GET /api/v1/item_prices/trend` (new, **no params**) — ~5-point,
   7-day price+volume trend for every item the authenticated user owns
   (a coarse series, for sparklines/volume, not detailed analysis).
4. `GET /api/v1/inventory_values?period=7d|30d|1y|all` (route unchanged,
   `period` param added) — portfolio value history.
5. `GET /api/v1/item_prices/:market_hash_name/history?period=...` (new)
   — one item's full-resolution price-log history, for the detail chart
   opened on click.

`POST /api/v1/price_histories` (today's only history endpoint) is
**retired entirely** — every need it served is now split across endpoints
3 and 5, and nothing else in either app calls it.

**Not part of this plan, but sharing code this plan touches:**
`POST /api/v1/inventories/refresh` (added by
`user-inventory-persistence.md`) renders through the same private
`render_inventory` helper as `show` — trimming price fields and relocating
warmup out of that helper (see Implementation Approach) changes
`refresh`'s response shape too, as a direct consequence, not a separate
decision.

## Why a 5th endpoint (`trend`), not a workaround

Two smaller alternatives were considered first:

- **Reuse the existing `price_histories` batch endpoint, rescoped to
  fewer items, unchanged.** Works mechanically, but once endpoint 5's
  field-sourcing bug was caught (see decision 4 above), keeping
  `price_histories` around meant maintaining a *second*,
  differently-shaped price series (`lowest_price_cents`-based, ISO
  timestamps, full 30-day resolution) alongside endpoint 5's series —
  and full 30-day-resolution history for a user's entire inventory on
  every dashboard load is real, avoidable weight a sparkline doesn't
  need.
- **Let the detail-chart click reuse whatever's already in memory from
  the batch fetch, for the default period, and only hit the network for
  longer periods.** Rejected: it only works if the sparkline's window
  and the detail chart's default window happen to coincide (an
  accident, not a guarantee — they already don't), and it means the
  detail chart's fetch-vs-no-fetch behavior differs invisibly depending
  on which period the user last looked at.

`trend` resolves both: deliberately **downsampled** (~5 points, not 30
days of raw points) so fetching it for the user's entire inventory is
cheap regardless of inventory size. The detail chart (endpoint 5) always
fetches its own data on click, with an explicit loading state — simpler
to reason about, and correct regardless of which sparkline resolution
happens to be configured today.

## Why bounded retry, not synchronous fetch or a stream consumer

Endpoint 2 (`dynamics`) omits items with no price yet, enqueuing an async
warmup (`PriceUpdateWorker`) for them — but gives the caller no signal
for when that warmup actually completes. Left as-is, a brand-new user
with an entirely unpriced inventory sees no prices at all until
something unrelated (a reload) happens to re-call `dynamics`. Three ways
to close this gap were considered:

- **Fetch synchronously from Steam inline, on a cache miss, inside
  `#dynamics` itself.** Rejected: `Prop.throttle!(:steam_price, ...)` is
  a *global* budget (20/min, 1000/day) shared across every user — the
  entire reason the existing warmup is async, capped at 20/request, and
  deduplicated is to keep one user's page load from draining that shared
  budget. Fetching synchronously reintroduces exactly the risk that
  design already avoids, and directly contradicts this endpoint's own
  stated purpose (the original design's own words: "молниеносный
  `read_multi`... к базе данных не обращается вообще").
- **A WebSocket/SSE consumer pushing live updates.** `PriceUpdateWorker`
  already publishes every successful price update to a `prices_stream`
  Redis stream (`.claude/adr/fetcher/price-updates-via-redis-stream.md`),
  built explicitly as "write-ahead-of-read infrastructure... no consumer
  yet, deliberate." A real consumer is the architecturally "correct"
  long-term answer, but it's a substantial, separate feature — a new
  transport not present anywhere in this app today, WebSocket-specific
  auth on top of the existing bearer-token bridge, and subscription
  management. Roughly doubles this plan's scope; deferred as a follow-up,
  not built speculatively now.
- **Bounded client-side retry, scoped to whatever's still missing a
  price** (chosen). After `useItemPrices`' initial fetch, any
  still-unpriced item is retried — not indefinitely. See Implementation
  Approach for the exact schedule.

## Why endpoints 2/3 need no params

Earlier in this plan's life, before `user-inventory-persistence.md`
landed, `dynamics`/`trend` took an explicit `market_hash_names` array
from the client (as a `POST` body — `internal-api-controllers.md`
requires `POST`, not `GET`, for a request needing a body, citing the
retired `price_histories` route as precedent for exactly this shape).
That design was necessary because `app_fetcher` had no durable record of
a `steam_id`'s inventory — only `UserInventoryCache`'s old 5-minute,
non-invalidated TTL entry, too fragile for a second endpoint to lean on
without duplicating the same Steam-fallback logic `show` already had.

That gap is now closed. `UserInventoryCache.fetch(steam_id)` reads
through a real, FK-enforced `user_inventories`/`user_inventory_items`
table (`.claude/plans/user-inventory-persistence.md`), invalidated by
event (every sync/manual refresh), not a timer. `InventoriesController
#show`'s warm path already calls exactly this method to answer "what
does this user own" — `dynamics`/`trend` can call the same method
themselves, needing no input from the client at all:

```ruby
names = (UserInventoryCache.fetch(current_steam_id) || []).map(&:market_hash_name)
```

A `nil` result (never synced) is treated as "nothing to report yet" —
`{}` — not as a trigger to sync. `show` already owns "make sure this
`steam_id` is synced" (cold-start → `UserInventorySyncService.call`,
synchronously, before it responds); `dynamics`/`trend` don't need, and
shouldn't duplicate, that responsibility — by the time the frontend's
hooks for these two endpoints fire (gated on the skeleton fetch
resolving first, see Implementation Approach), a `user_inventories` row
is guaranteed to already exist.

**One correctness subtlety worth being explicit about:**
`UserInventoryCache.fetch`'s own cached `Item` objects can be up to 15
minutes stale on *price* (it's invalidated only when inventory
*composition* changes, not when `PriceUpdateWorker` updates a price —
that invalidates `ItemPriceCache`/`PriceHistoryCache`/`ItemTrendCache`
instead). `dynamics`/`trend` therefore use `UserInventoryCache.fetch`
**only** to resolve the current `market_hash_name` list (composition,
fine to be briefly stale), then re-fetch **prices** through
`ItemPriceCache`/`ItemTrendCache` (point-invalidated, tight freshness) —
never rendering price fields straight off the `Item` objects
`UserInventoryCache` itself returned.

This also fully resolves two Risks this plan previously carried: fetching
for "the whole filtered set" on every filter change (now: fetch once for
the whole owned inventory, independent of filters, matching endpoint 1's
own "load it all, it's cheap" reasoning) and the sort/filter-correctness
gap for items outside the current page (now: every owned item always has
a price, so client-side sort by price/delta is always correct, not just
eventually).

## Route/controller inventory after this plan

| # | Route | Controller#action | Status |
|---|-------|--------------------|--------|
| 1 | `GET /api/v1/inventories/me` | `InventoriesController#show` | existing, response shape trimmed |
| — | `POST /api/v1/inventories/refresh` | `InventoriesController#refresh` | existing (separate plan), response shape trimmed as a side effect |
| 2 | `GET /api/v1/item_prices/dynamics` | `ItemPricesController#dynamics` | **new**, no params |
| 3 | `GET /api/v1/item_prices/trend` | `ItemPricesController#trend` | **new**, no params |
| 4 | `GET /api/v1/inventory_values` | `InventoryValuesController#index` | existing, `period` param added |
| 5 | `GET /api/v1/item_prices/:market_hash_name/history` | `ItemPricesController#history` | **new** |
| — | `POST /api/v1/price_histories` | `PriceHistoriesController#index` | **deleted** — no remaining caller |

## Expected Behavior

### Endpoint 1 — `GET /api/v1/inventories/me` (and `POST .../refresh`)

**Current actual behavior (post `user-inventory-persistence.md`), for
context — this plan builds on top of this, not on the original
pre-persistence flow:**
- `show`: `items = UserInventoryCache.fetch(current_steam_id)` — a
  real, FK-backed read (not a names-only TTL cache). If present,
  `render_inventory(items)`. If `nil` (never synced), calls
  `UserInventorySyncService.call(current_steam_id)` synchronously
  (fetches from Steam, backfills missing `Item` rows, persists
  `user_inventories`/`user_inventory_items`, invalidates
  `UserInventoryCache`) and renders the result.
- `refresh`: rate-limited once/day, always calls
  `UserInventorySyncService.call(current_steam_id)` (full resync),
  renders the same way.
- Both funnel through a shared private `render_inventory(items)`, which
  **currently** also calls `enqueue_price_warmup(items)` and renders
  price fields (`current_price_cents`, `change_24h_cents`) alongside
  `market_hash_name`/`metadata`.
- `ItemsListUpdateWorker` (this plan's earlier draft referenced it for
  missing-item backfill) **no longer exists** — backfill now happens
  synchronously, inline, inside `UserInventorySyncService`, as part of
  the persistence work from the other plan. Nothing in this plan needs
  to touch that.

**Normal (after this plan)**
- Returns `{ items_count, items: [{ market_hash_name, metadata }] }` for
  both `show` and `refresh` — `current_price_cents`/`change_24h_cents`
  dropped from `render_inventory`'s `as_json` entirely.
- No price-warmup enqueue from `render_inventory` anymore — relocated to
  endpoint 2, since neither `show` nor `refresh` has any price data to
  warm once prices are dropped from their response.
- Returns the entire inventory in one response, no pagination —
  unchanged, deliberately not changed by this plan (see Out of Scope).

**New: truncation visibility**
- If `Steam::Client#fetch_user_inventory`'s response (inside
  `UserInventorySyncService`) signals `more_items` (Steam indicating the
  raw inventory exceeds the requested `count: 2000` and was truncated),
  log a warning including `steam_id` — purely observability, no behavior
  change. Still silent to the user (see Out of Scope), but now visible
  in logs.

**Must remain unchanged**
- Route paths/methods, auth, `UserInventorySyncService`'s cold-start/
  refresh/weekly-sync behavior, `UserInventoryCache`'s single-key
  read-through+invalidate shape, the refresh rate-limit window — this
  plan reuses all of it as-is from `user-inventory-persistence.md`;
  nothing here touches `UserInventory`/`UserInventoryItem`,
  `UserInventorySyncService`, `UserInventorySyncWorker`/`Scheduler`.

### Endpoint 2 — `GET /api/v1/item_prices/dynamics` (no params)

**Normal**
- Identity-scoped only (`current_steam_id` from the bridge token, like
  every other endpoint) — no request body, no query params.
- Resolves the owned `market_hash_name` list via
  `UserInventoryCache.fetch(current_steam_id)` (same call `show`'s warm
  path makes), then fetches fresh prices for those names via
  `ItemPriceCache.fetch_for(names)` — see "Why endpoints 2/3 need no
  params" for why these are two separate calls, not one.
- Returns `{ "<market_hash_name>": { current_price_cents, change_24h_cents, change_24h_percent }, ... }`
  for every owned name that has a priced `Item` row.
- `change_24h_percent` is computed as
  `change_24h_cents / (current_price_cents - change_24h_cents) * 100`
  (i.e. against yesterday's price), rounded to 2 decimals.
- Price-warmup enqueue (`enqueue_price_warmup`/`WARMUP_CAP`/
  `WARMUP_DEDUP_TTL`, capped at 20/request, 90s dedup) moves here from
  `InventoriesController`'s `render_inventory`, operating on the same
  `ItemPriceCache.fetch_for` result.

**Edge cases**
- `UserInventoryCache.fetch(current_steam_id)` returns `nil` (never
  synced yet): returns `{}`, no `ItemPriceCache` call, no sync
  triggered — `show` owns ensuring a sync happens, not this endpoint.
- An owned name with no matching `Item` row at all, or an `Item` row
  with `current_price_cents: nil`: omitted from the response (matches
  `ItemPriceCache.fetch_for`'s existing omission behavior); still
  eligible for warmup enqueue.
- `(current_price_cents - change_24h_cents) == 0`: `change_24h_percent`
  is `0.0`, not `Infinity`/`NaN`.
- Zero owned items: returns `{}`.

### Endpoint 3 — `GET /api/v1/item_prices/trend` (no params)

**Normal**
- Same identity-scoped, no-param shape as endpoint 2. Resolves owned
  names via `UserInventoryCache.fetch(current_steam_id)`, then fetches
  via `ItemTrendCache.fetch_for(names)`.
- Returns `{ "<market_hash_name>": [{ at, price_cents, volume }, ...], ... }`
  — same point shape as the retired `price_histories` (`at`: ISO8601
  string, `price_cents` from `lowest_price_cents`, `volume` from
  `PriceLog#volume`), but **at most ~5 points per item**, spanning the
  **last 7 days** (matching `ItemRow`'s existing sparkline window today).
- Backed by a new `ItemTrendCache` (bulk read-through + invalidation —
  see `caching.md`'s three variants; this one is the bulk variant, same
  as `ItemPriceCache`/`PriceHistoryCache`, not the single-key variant
  `UserInventoryCache` uses). Versioned key
  `["item_trend", 1, market_hash_name]`, 15-minute safety TTL. On a
  cache miss, queries `PriceLog` for the last 7 days per item, then
  downsamples via a cursor-based time-bucketing pass (walk 5
  evenly-spaced timestamps across the window, take the most recent row
  at-or-before each — a much smaller version of the cursor algorithm
  `price-history-long-windows.md` designed but never built for a
  365-day case; not a resurrection of that rejected larger design).

**Edge cases**
- `UserInventoryCache.fetch` returns `nil`: `{}`, same as endpoint 2.
- An owned name with no matching `Item`, or zero `PriceLog` rows in the
  last 7 days: omitted from the response.
- An item with fewer than 5 `PriceLog` rows in the window: returns
  however many distinct points exist (no padding to force exactly 5).
- Zero owned items: `{}`.

### Endpoint 4 — `GET /api/v1/inventory_values`

**Normal**
- Accepts `period` = `7d` | `30d` | `1y` | `all`; default when absent or
  blank is `all` (preserves today's no-param behavior exactly).
- Returns a **bare JSON array** `[{ date, total_value_cents }, ...]`
  (was `{ points: [{ log_date, total_value_cents }] }`).
- The self-seed check (`enqueue_first_value_seed`) is evaluated against
  the user's **full, unfiltered** log set, not the period-filtered one.

**Edge cases**
- `period` present but not one of the four values: `:bad_request` with
  `{ message: "..." }`.
- `period=all` (or absent): identical to today's full-history response,
  content and field-rename aside.

**Must remain unchanged**
- Self-seed trigger condition, dedup TTL/key shape, nightly
  `InventoryValueScheduler` fan-out — untouched by this plan, and
  unaffected by `user-inventory-persistence.md`'s changes elsewhere
  (that plan touched `InventoryValueUpdateWorker`'s internals, not this
  controller's contract).

### Endpoint 5 — `GET /api/v1/item_prices/:market_hash_name/history`

**Normal**
- Accepts `period` = `7d` | `30d` | `1y` | `all`; default when absent is
  `30d`.
- Returns a **bare JSON array** `[{ at, price_cents, volume }, ...]`,
  ordered oldest first — same point shape as endpoint 3 and the retired
  `price_histories` (`price_cents` from `PriceLog#lowest_price_cents`).
- For the default period (`30d`, or absent), reuses
  `PriceHistoryCache.fetch_for([market_hash_name])` — the exact same
  cache/logic `price_histories` used, just called with a one-element
  array. For any other period, bypasses the cache and queries
  `PriceLog` directly with a computed lower bound.
- Always triggered by an explicit user action, always shows a loading
  state while the fetch is in flight — no assumption that data "might
  already be in memory" (see "Why a 5th endpoint").

**Edge cases**
- `market_hash_name` with no matching `Item` row: `200` with `[]`.
- An item with zero `PriceLog` rows: `[]`.
- `period` not one of the four values: `:bad_request` +
  `{ message: "..." }`.
- `interval` param (optional in the original design): **not
  implemented** — accepted but ignored if present.

**Must remain unchanged**
- `PriceHistoryCache`'s cache key version, TTL, and cached shape
  (`{at:, price_cents:, volume:}`) — untouched.

## Scope

### In Scope

- `app_fetcher`: trim price fields + relocate warmup out of
  `InventoriesController`'s shared `render_inventory`; add `more_items`
  logging; new `ItemPricesController` with `#dynamics`/`#trend`/`#history`
  (no-param for the first two); add `period` to endpoint 4; new
  `ItemTrendCache`; delete `PriceHistoriesController` and its route/spec.
- `app_core`: rewire `useDashboardData` and add dedicated hooks for
  prices/trend/portfolio-history/item-history; delete `portfolioSeries.js`
  and `itemSeries.js`; simplify `changePct`; update `RangeToggle`/
  `chartConfig.js` to offer `7d/30d/1y/all` (replacing `24h/7d/30d`).
- Test coverage for all of the above, both apps.

### Out of Scope

- **Anything already implemented by `.claude/plans/user-inventory-persistence.md`**:
  `user_inventories`/`user_inventory_items` schema, `UserInventory`/
  `UserInventoryItem` models, `UserInventorySyncService`,
  `UserInventorySyncWorker`/`Scheduler`, the weekly sync cadence, the
  `refresh` rate-limit window, `UserInventoryCache`'s single-key
  read-through+invalidate shape, `InventoryValueUpdateWorker`'s DB-only
  simplification, the `app/services/` layer / `cross-scenario-service-layer.md`
  ADR. This plan only reads `UserInventoryCache.fetch` as a consumer and
  trims/relocates logic in `render_inventory` — it does not re-decide or
  extend any of the above.
- Any change to `InventoryValueScheduler`, `PriceUpdateWorker`'s
  Steam-fetch/transaction logic, `PriceScheduler`, or their cron
  schedule — this plan only adds a third `.invalidate` call to
  `PriceUpdateWorker`'s existing success branch (for `ItemTrendCache`).
- A `portfolio_snapshots` table or any new nightly-cron-fed cache-preset
  mechanism — explicitly rejected; `InventoryValueLog` is the source of
  truth, queried live.
- Redis as a cache store anywhere in `app_fetcher` — explicitly rejected.
- Resurrecting `.claude/plans/price-history-long-windows.md`'s
  period-bucketed `PriceHistoryCache` design — `ItemTrendCache`'s
  5-point/7-day downsampling is a separate cache class, not an
  extension of `PriceHistoryCache`.
- `interval` param support / server-side bucketing for endpoint 5.
- Real virtualized scrolling (e.g. `react-window`) for `ItemsTile` —
  existing 8-per-page pagination is kept. This no longer matters for
  price/trend-fetching scope (endpoints 2/3 now always cover the whole
  owned inventory, independent of what's rendered/filtered).
- **Paginating endpoint 1's network fetch** — considered and rejected;
  the skeleton payload is cheap regardless of inventory size, and
  paginating it would break today's fully-client-side `applyFilters`/
  `applySort`.
- **An explicit inventory-size cap on endpoint 1's response** beyond
  `Steam::Client#fetch_user_inventory`'s existing `count: 2000` —
  considered and rejected in favor of just logging `more_items`.
- `:steam_id` in any route path, or any new cross-user authorization
  check.
- Renaming `inventories/me` to drop its `/me` suffix.
- Adding `asset_id`, `icon_url`, or `rarity` fields to the inventory
  response — none of these are parsed or stored anywhere in `app_fetcher`
  today; adding them is materially larger, separate work.
- Fixing the pre-existing `NaN`-on-null-price edge case in
  `filters.js`'s `price_desc`/`price_asc` comparators (see Risks).
- Implementing Steam's inventory continuation (`more_items`/
  `last_assetid`) to fetch a truncated inventory in full.
- Synchronous Steam calls inline in `item_prices#dynamics` for unpriced
  names — see "Why bounded retry".
- A WebSocket/SSE consumer for the existing `prices_stream` Redis stream
  — see "Why bounded retry". `prices_stream` itself is untouched.

## Implementation Approach

### Backend

**`InventoriesController`'s shared `render_inventory`.** Currently:

```ruby
def render_inventory(items)
  enqueue_price_warmup(items)
  render json: {
    items_count: items.size,
    items: items.as_json(only: [:market_hash_name, :metadata, :current_price_cents, :change_24h_cents])
  }, status: :ok
end
```

Remove the `enqueue_price_warmup(items)` call and the `WARMUP_CAP`/
`WARMUP_DEDUP_TTL` constants and private method entirely (relocated to
`ItemPricesController#dynamics`). Trim the `as_json` `only:` list to
`[:market_hash_name, :metadata]`. Since both `show` and `refresh` render
through this one method, both lose price fields and warmup in one edit
— no separate change needed per action.

**`Steam::Response::Data::InventoryData` gains `more_items`.** Add
`const :more_items, T::Boolean` alongside the existing `assets`/
`descriptions`, parsed in `from_hash` as `!!hash["more_items"]` (verify
the exact raw shape empirically during implementation, see Assumptions).
Add the warning log inside `UserInventorySyncService.call`, right after
a successful `Steam::Client#fetch_user_inventory` call (that's the one
call site that currently makes this Steam call) —
`Rails.logger.warn("[UserInventorySyncService] steam_id=#{steam_id} inventory truncated (more_items)")`
if `response.data.more_items` — no other behavior change.

**Endpoint 2 (new `Api::V1::ItemPricesController#dynamics`, no params).**

```ruby
sig { void }
def dynamics
  names = (UserInventoryCache.fetch(current_steam_id) || []).map(&:market_hash_name)
  priced_items = ItemPriceCache.fetch_for(names)
  enqueue_price_warmup(priced_items.values)

  render json: priced_items.each_with_object({}) do |(name, item), hash|
    next if item.current_price_cents.nil?
    change = item.change_24h_cents || 0
    base = item.current_price_cents - change
    percent = base.zero? ? 0.0 : (change.to_f / base * 100).round(2)
    hash[name] = { current_price_cents: item.current_price_cents, change_24h_cents: change, change_24h_percent: percent }
  end, status: :ok
end
```

`enqueue_price_warmup`/`WARMUP_CAP`/`WARMUP_DEDUP_TTL` move here
verbatim from `InventoriesController`.

**Endpoint 3 (new `Api::V1::ItemPricesController#trend`, no params).**

```ruby
sig { void }
def trend
  names = (UserInventoryCache.fetch(current_steam_id) || []).map(&:market_hash_name)
  render json: ItemTrendCache.fetch_for(names), status: :ok
end
```

**New `app/caching/item_trend_cache.rb` (`ItemTrendCache`).** Bulk
read-through + invalidation variant (per `caching.md`'s three-variant
taxonomy — same as `ItemPriceCache`/`PriceHistoryCache`, not the
single-key variant `UserInventoryCache` uses, since callers key in with
an arbitrary-length list of names, not one id per call).
`TREND_WINDOW = 7.days`, `TREND_POINTS = 5`. On a miss for a batch of
names: bulk-query `Item.where(market_hash_name: missing_names)`, then
bulk-query `PriceLog.where(item_id: ..., created_at: TREND_WINDOW.ago..).order(:created_at)`,
group by `item_id`. For each item's sorted rows, downsample via a
cursor: compute 5 target timestamps evenly spaced across the window,
advance a single cursor forward through the sorted rows (never
rescanning from the start) picking the most recent row at-or-before
each target, skipping targets with no row yet available. Cache key
`["item_trend", CACHE_KEY_VERSION, market_hash_name]`, 15-minute safety
TTL. `.invalidate(market_hash_name)` — single `Rails.cache.delete`.

**Endpoint 4 (`InventoryValuesController#index`).** Add a private
`PERIODS = { "7d" => 7.days, "30d" => 30.days, "1y" => 365.days, "all" => nil }`
constant. Parse `params[:period]`, default `"all"` if blank, render
`:bad_request` if present but not a key of `PERIODS`. Keep the existing
unfiltered `logs = InventoryValueLog.where(steam_id: current_steam_id).order(:log_date)`
query and its `.empty?` seed check exactly as today; apply the period
window as a second, separate in-memory filter only when building the
rendered array. Render
`logs_in_period.map { |log| { date: log.log_date.iso8601, total_value_cents: log.total_value_cents } }`
as a bare array.

**Endpoint 5 (new `Api::V1::ItemPricesController#history`).** A private
`PERIODS` constant defined locally in this controller too (duplicating
endpoint 4's four-line constant rather than extracting a shared module
for two call sites). Default period `"30d"` if absent. If
`period == "30d"`: call
`PriceHistoryCache.fetch_for([params[:market_hash_name]])` and render
whatever comes back for that key (`[]` if absent). For any other
period: look up `item = Item.find_by(market_hash_name: params[:market_hash_name])`
(nil → render `[]` immediately), compute `since = PERIODS[period]&.ago`,
query `PriceLog.where(item_id: item.id, created_at: since..).order(:created_at)`,
render `{ at: log.created_at.iso8601, price_cents: log.lowest_price_cents, volume: log.volume }`
per row.

**`PriceUpdateWorker`.** Add `ItemTrendCache.invalidate(item.market_hash_name)`
alongside the existing `ItemPriceCache.invalidate`/`PriceHistoryCache.invalidate`
calls in the success branch — three invalidations after a successful
price update, still nothing invalidated on failure.

**Routes.** Add, under the existing `api/v1` namespace:
```ruby
get "item_prices/dynamics", to: "item_prices#dynamics"
get "item_prices/trend", to: "item_prices#trend"
get "item_prices/:market_hash_name/history", to: "item_prices#history"
```
Remove the `post "price_histories", to: "price_histories#index"` line.
The `:market_hash_name` segment sits mid-path (followed by `/history`),
so Rails' default dynamic-segment matcher (`[^/]+`) applies — no custom
constraint needed for names containing `|`, parentheses, or spaces. The
frontend must `encodeURIComponent` the name when building the URL (see
Risks).

**Delete** `app_fetcher/app/controllers/api/v1/price_histories_controller.rb`
and `app_fetcher/spec/requests/api/v1/price_histories_spec.rb` — no
remaining caller once `app_core` is rewired.

### Frontend

**`useDashboardData.js` becomes skeleton-only.** Its one fetch is
`GET /api/v1/inventories/me` (now prices-free); `mapItem` no longer
merges any price-history blob — items carry only
`{marketHashName, weaponType, itemName, condition, stattrak}`.
`portfolio`/`marketVolume` composition is removed from `buildData`
entirely (both now come from their own fetches).

**`useItemPrices(fetcherUrl, bridgeToken, names)` (new hook).** `names`
here is the **full skeleton item-name list** (from `useDashboardData`,
once it resolves) — not sent to the backend as a param (endpoint 2 takes
none), used purely client-side for two things: (1) gating — the effect
only fires once `names` is populated, i.e. after the skeleton fetch
resolves, which matters because `dynamics` relies on
`UserInventoryCache` already having a row for this `steam_id` (guaranteed
true only once the skeleton's own cold-start sync has had a chance to
run); (2) the bounded-retry stop condition (see below) — "are we
covering every owned name yet." Fetches `GET /api/v1/item_prices/dynamics`,
merges the result into item objects (`currentPriceCents`/`changeCents`/
`change24hPercent`) by `market_hash_name`.

**Bounded retry for names still missing a price.** After each fetch
(initial or retry), the hook checks whether the response's key count
covers `names.length`. If not, it schedules the next retry at
`[3, 6, 12, 24, 45]` seconds (cumulative ≈ 90s — deliberately matching
`WARMUP_DEDUP_TTL`), re-fetching the same parameterless `dynamics`
endpoint (not scoped to a specific pending subset — the endpoint always
returns everything currently priced, so a retry just means "ask again,
merge in whatever's newly priced"), merging the newly-expanded result in.
Stops once the response covers every name or all 5 attempts are
exhausted, whichever comes first — an item still unpriced after the last
attempt stays that way until the next reload (the skeleton endpoint is
the only thing that re-triggers a sync; retrying `dynamics` itself never
does). All pending timers are cleared on unmount. This adds no new
backend behavior — `#dynamics` itself doesn't change; only how often the
frontend calls it does.

**`useItemTrend(fetcherUrl, bridgeToken, names)` (new hook).** Same
gating as `useItemPrices` (fires once the skeleton's `names` list is
known), fetches `GET /api/v1/item_prices/trend`, merges
`trendPoints: [{at, priceCents, volume}]` onto each item. No bounded
retry needed here — a missing trend series for a brand-new unpriced item
isn't as time-sensitive as its headline price, and re-fires naturally on
the next reload like any other skeleton-dependent fetch. `ItemRow`'s
`Sparkline` reads `item.trendPoints` directly — no client-side slicing
or windowing needed. `MarketVolumeTile` aggregates `volume` across the
trend-enriched items the same way it aggregated `priceHistory` before
(`bucketByHour` stays; only its input source changes).

**`changePct` (`filters.js`) simplifies.** Replace the `itemSeries`-based
24h delta derivation with a direct read of `item.change24hPercent`
(populated by `useItemPrices`).

**`useItemHistory(fetcherUrl, bridgeToken, marketHashName, period)`
(new hook).** Fetches `GET /api/v1/item_prices/:market_hash_name/history?period=...`
on demand — invoked when an item is selected (`ITEM_ROW_CLICKED`) or its
detail-view range changes, `encodeURIComponent`-escaping the name.
Exposes a `pending`/`ready`/`error` status (mirrors today's
`historyStatus` pattern).

**`usePortfolioHistory(fetcherUrl, bridgeToken, period)` (new hook).**
Fetches `GET /api/v1/inventory_values?period=...`; `PortfolioTile`, in
portfolio mode, passes the returned `[{date, total_value_cents}]`
straight through, mapped to `{at: new Date(date).getTime(), value: total_value_cents}`.

**Dead code removed.** `portfolioSeries.js` and `itemSeries.js` (its
three former call sites — `changePct`, `ItemRow`'s sparkline,
`PortfolioTile`'s item mode — all replaced by direct backend data) are
both deleted, along with `sumAsOfEachHour` in `bucketing.js`
(`bucketByHour` stays, still used by `marketVolume.js`).

**`chartConfig.js`/`RangeToggle` period set changes.** `RANGE_MS`/
`RANGES`/`RANGE_SPAN`: `24h/7d/30d` → `7d/30d/1y/all`.

## Files To Modify

- `.claude/styleguides/fetcher/caching.md` — its "Interaction With Other
  Layers" diagram references `Api::V1::PriceHistoriesController` as a
  caller of `PriceHistoryCache`; update to
  `Api::V1::ItemPricesController#history` once `PriceHistoriesController`
  is deleted. (Separately, this file already documents the three-variant
  taxonomy and `UserInventoryCache`'s single-key shape as of
  `user-inventory-persistence.md` — nothing else here needs touching.)
- `.claude/styleguides/fetcher/internal-api-controllers.md` — its
  Structure section's routing example and "Canonical Implementations"
  list reference `price_histories`/`PriceHistoriesController`/
  `price_histories_spec.rb`; update to `item_prices`/
  `ItemPricesController`/`item_prices_spec.rb`.
- `app_fetcher/config/routes.rb` — add three new `item_prices` routes,
  remove the `price_histories` route.
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb` —
  remove `enqueue_price_warmup`/`WARMUP_CAP`/`WARMUP_DEDUP_TTL` from
  `render_inventory`; trim its `as_json` fields.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — add the
  `more_items` logging line after the Steam call.
- `app_fetcher/lib/steam/response/data/inventory_data.rb` — add
  `more_items: T::Boolean`.
- `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb` —
  add `period` parsing/filtering, change response to a bare array with
  `date` instead of `points: [{log_date}]`.
- `app_fetcher/app/workers/price_update_worker.rb` — add
  `ItemTrendCache.invalidate` alongside the existing two invalidations.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — remove
  warmup-enqueue examples (moved to the new spec below) from both
  `show` and `refresh` contexts; update response shape assertions; add
  the `more_items` logging test (likely moves to a
  `resolve_inventory_spec.rb`/`user_inventory_sync_service_spec.rb`
  context instead, since that's where the Steam call now lives — confirm
  during implementation).
- `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb` — add
  `period` scenarios, update response shape assertions.
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — extend to
  assert `ItemTrendCache` is also invalidated on success.
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js` — reduce
  to the skeleton-only fetch; drop `portfolioSeries`/`marketVolume`
  composition from `buildData`.
- `app_core/app/frontend/dashboard/utils/filters.js` — simplify
  `changePct` to read `item.change24hPercent`.
- `app_core/app/frontend/dashboard/utils/bucketing.js` — remove
  `sumAsOfEachHour` (keep `bucketByHour`).
- `app_core/app/frontend/dashboard/utils/marketVolume.js` — source
  volume from trend-enriched items instead of `item.priceHistory`.
- `app_core/app/frontend/dashboard/chartConfig.js` — `RANGE_MS`/
  `RANGES`/`RANGE_SPAN`: `24h/7d/30d` → `7d/30d/1y/all`.
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx` —
  portfolio mode consumes `usePortfolioHistory`; item mode consumes
  `useItemHistory`, with an explicit loading state.
- `app_core/app/frontend/dashboard/components/ItemRow.jsx` — sparkline
  reads `item.trendPoints` instead of slicing `itemSeries`.
- `app_core/app/frontend/dashboard/components/RangeToggle.jsx` — reads
  the new `RANGES` list.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — wires
  `useItemPrices`/`useItemTrend` (both keyed on the skeleton's resolved
  name list, not on filters)/`usePortfolioHistory`/`useItemHistory`;
  merges their results onto `items` before passing down to
  `ItemsTile`/`MarketVolumeTile`.
- `app_core/app/frontend/dashboard/__tests__/useDashboardData.test.js`,
  `PortfolioTile.test.jsx`, `filters.test.js`, `marketVolume.test.js` —
  updated for the new fetch/data shapes.

## Files To Create

- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` — new
  controller, `#dynamics`, `#trend`, `#history` actions.
- `app_fetcher/app/caching/item_trend_cache.rb` — new `ItemTrendCache`.
- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb` — request specs
  for all three new actions, including the relocated warmup-enqueue
  scenarios.
- `app_fetcher/spec/caching/item_trend_cache_spec.rb` — cache hit/miss/
  downsampling/invalidation coverage for `ItemTrendCache`.
- `app_core/app/frontend/dashboard/hooks/useItemPrices.js`.
- `app_core/app/frontend/dashboard/hooks/useItemTrend.js`.
- `app_core/app/frontend/dashboard/hooks/usePortfolioHistory.js`.
- `app_core/app/frontend/dashboard/hooks/useItemHistory.js`.

## Files To Delete

- `app_fetcher/app/controllers/api/v1/price_histories_controller.rb`.
- `app_fetcher/spec/requests/api/v1/price_histories_spec.rb`.
- `app_core/app/frontend/dashboard/utils/portfolioSeries.js` +
  `__tests__/portfolioSeries.test.js`.
- `app_core/app/frontend/dashboard/utils/itemSeries.js` + its test file.

## Test Plan

**`app_fetcher` request specs**

- `item_prices_spec.rb` (`#dynamics`): auth; no params needed; returns
  price+percent for every owned, priced item; omits unpriced/unknown
  names; `change_24h_percent` computed correctly including the
  zero-denominator edge case; enqueues warmup for unpriced items
  (capped at 20, deduplicated within 90s) — relocated from
  `inventories_spec.rb`; a `steam_id` with no `user_inventories` row
  (`UserInventoryCache.fetch` → `nil`) returns `{}`, no `ItemPriceCache`
  call.
- `item_prices_spec.rb` (`#trend`): auth; returns up to 5 downsampled
  points per owned name over the 7-day window; omits unknown/logless
  names; an item with fewer than 5 logs returns fewer points, not
  padded; no `user_inventories` row → `{}`.
- `item_prices_spec.rb` (`#history`): default period (`30d`/absent)
  reuses `PriceHistoryCache` (assert via a query-count check); explicit
  `7d`/`1y`/`all` bypass the cache and scope correctly; unknown
  `market_hash_name` returns `[]`; unsupported `period` returns
  `:bad_request`; `price_cents` is sourced from `lowest_price_cents`
  (regression-guard, given `median_price_cents` exists on the same
  model and was the wrong field in an earlier version of this plan).
- `item_trend_cache_spec.rb`: cold-cache DB hit + correct downsampled
  values; warm-cache no DB hit; names with no `Item`/no logs omitted;
  `.invalidate` forces a genuine miss; fewer than 5 logs in the window
  returns exactly that many points.
- `inventories_spec.rb`: existing auth/cache-hit examples kept (now
  against `UserInventoryCache.fetch`'s real DB-backed shape, already
  updated by `user-inventory-persistence.md`); response-shape
  assertions updated to confirm price fields are **absent** from both
  `show` and `refresh`; warmup-enqueue examples removed (moved to
  `item_prices_spec.rb`).
- `user_inventory_sync_service_spec.rb` (or wherever the Steam call now
  lives): new example asserting a warning is logged when the Steam
  response has `more_items: true`, and not logged when `false`/absent.
- `inventory_values_spec.rb`: existing examples kept; add `period`
  scenarios (`7d`/`30d`/`1y`/`all`/absent/invalid); confirm the seed
  check still fires based on the *unfiltered* log set; response shape
  assertions updated to the bare-array/`date`-field shape.
- `price_update_worker_spec.rb`: extend the existing invalidation
  assertions to also cover `ItemTrendCache`.

**`app_core` frontend tests**

- `useDashboardData.test.js`: now asserts only the skeleton fetch/shape.
- New: `useItemPrices.test.js`, `useItemTrend.test.js`,
  `usePortfolioHistory.test.js`, `useItemHistory.test.js` — fetch/error-
  state coverage, following the existing mock-`fetch`-at-the-boundary
  pattern. `useItemPrices`/`useItemTrend` specifically cover: the effect
  doesn't fire until `names` is populated (simulating the skeleton not
  having resolved yet); re-fires if `names` changes (e.g. a later
  reload). `useItemPrices.test.js` additionally covers the bounded-retry
  schedule (fake timers): an incomplete first response is retried at
  `[3, 6, 12, 24, 45]`s; stops once the response covers every name;
  stops after the 5th attempt regardless; unmounting clears all pending
  timers (no state update after unmount).
- `filters.test.js`: `changePct` now reads `change24hPercent` directly.
- `marketVolume.test.js`: sources volume from trend-shaped input instead
  of `priceHistory`.
- `PortfolioTile.test.jsx`: portfolio mode renders from
  `usePortfolioHistory`; item mode renders from `useItemHistory`,
  including its loading state; range toggle offers `7d/30d/1y/all`.
- `portfolioSeries.test.js`, `itemSeries.test.js` deleted.

## Implementation Steps

1. `app_fetcher`: add `more_items` to `Steam::Response::Data::InventoryData`;
   add the logging line in `UserInventorySyncService`; test both.
2. `app_fetcher`: trim `InventoriesController`'s shared `render_inventory`
   (remove warmup, trim price fields); update `inventories_spec.rb` for
   both `show` and `refresh`.
3. `app_fetcher`: TDD `ItemPricesController#dynamics` — new controller,
   route, request spec — including relocating the warmup-enqueue tests.
4. `app_fetcher`: TDD `ItemTrendCache` in isolation against
   `item_trend_cache_spec.rb` (cursor-based downsampling is the trickiest
   part — test it thoroughly before wiring the controller).
5. `app_fetcher`: TDD `ItemPricesController#trend` against the new
   cache; extend `item_prices_spec.rb`.
6. `app_fetcher`: TDD `ItemPricesController#history` — default-period
   reuse of `PriceHistoryCache`, direct-query paths for other periods;
   confirm `lowest_price_cents` sourcing.
7. `app_fetcher`: add the third `ItemTrendCache.invalidate` call to
   `PriceUpdateWorker`; extend `price_update_worker_spec.rb`.
8. `app_fetcher`: add `period` support to `InventoryValuesController#index`;
   update `inventory_values_spec.rb`.
9. `app_fetcher`: delete `PriceHistoriesController`, its route, its spec.
10. `app_fetcher`: full suite, `rubocop`, `srb tc` (informational),
    `bin/rails db:test:prepare` if schema-relevant (none expected).
11. `app_core`: TDD `useItemPrices`, `useItemTrend`, `usePortfolioHistory`,
    `useItemHistory` hooks in isolation against their own new test files.
12. `app_core`: update `chartConfig.js`/`RangeToggle` for the new period
    set; update its test coverage.
13. `app_core`: reduce `useDashboardData.js` to skeleton-only; update
    `useDashboardData.test.js`.
14. `app_core`: simplify `filters.js`'s `changePct`; update `marketVolume.js`
    to source from trend data; update both tests.
15. `app_core`: wire `Dashboard.jsx` to call the new hooks (keyed on the
    skeleton's resolved name list), merging results onto `items`; wire
    `PortfolioTile`/`ItemRow` to the new data; delete
    `portfolioSeries.js`/`itemSeries.js` and their tests; delete
    `sumAsOfEachHour` from `bucketing.js`; update `PortfolioTile.test.jsx`.
16. `app_core`: full frontend suite (Vitest).

## Verification

- `app_fetcher`: targeted specs for `item_prices_spec.rb`,
  `item_trend_cache_spec.rb`, `inventories_spec.rb`,
  `inventory_values_spec.rb`, `price_update_worker_spec.rb`, then the
  full suite (regression); `bin/rubocop`; `bundle exec srb tc`
  (informational).
- `app_core`: targeted specs for the new/changed hooks and
  `PortfolioTile`/`filters`/`marketVolume`, then the full frontend suite
  (regression).
- Manual: not planned to be performed live, matching this session's
  established environment-limitation precedent.

## Risks

- **Bounded retry (~90s total) isn't a guarantee** — if Steam is slow,
  rate-limited, or the shared daily `steam_price_rpd` budget is
  exhausted by other traffic, an item can still be unpriced after all 5
  attempts, with no further automatic retry until a reload. Accepted
  explicitly — see "Why bounded retry".
- **`price_desc`/`price_asc` comparators in `filters.js` don't guard
  against `null` `currentPriceCents`** (`b.currentPriceCents - a.currentPriceCents`
  produces `NaN` if either side is `null`) — pre-existing behavior, not
  introduced by this plan.
- **`market_hash_name` in a URL path segment needs `encodeURIComponent`**
  on every frontend call to endpoint 5 — covered by the new hook's
  tests.
- **`InventoryValueLog`'s daily granularity cannot support a `24h`
  range** — dropping `24h` from `RangeToggle` for the portfolio view is
  a real, visible product change.
- **The cursor-based downsampling in `ItemTrendCache` is new,
  non-trivial logic** — needs careful TDD on boundary cases (fewer than
  5 logs, all logs before/after the window, logs exactly on a bucket
  boundary).
- **Silent inventory truncation past ~2000 raw Steam assets is still
  silent to the end user** — only observable in server logs
  (`more_items`), not surfaced in the UI. Accepted explicitly.
- **`inventories_spec.rb`'s hand-written `WebMock` stub is not migrated
  to a VCR cassette as part of this plan** — `vcr` isn't yet a
  dependency in either app; see Assumptions.
- **`useItemPrices`/`useItemTrend` firing before the skeleton's
  cold-start sync has actually persisted a `user_inventories` row** —
  mitigated by gating both hooks' effects on the skeleton's resolved
  `names` list (not firing until `useDashboardData` reaches `'success'`),
  but this is a real sequencing dependency worth being deliberate about,
  not an accident of shared timing. If `Dashboard.jsx`'s wiring ever
  decouples these hooks from that gate, the narrow race this plan
  avoided reopens.

## Assumptions

- Endpoints 2/3/5 require the same `authenticate_bridge_token!` auth as
  every other `Api::V1::` action, even though endpoint 5's/3's
  underlying item-price data isn't itself user-scoped —
  `internal-api-controllers.md`'s MUST rules don't carve out an
  unauthenticated exception.
- `change_24h_percent`'s base is yesterday's price
  (`current_price_cents - change_24h_cents`), matching the pasted
  design's own worked example (`15050` current, `520` change → `3.58%`,
  confirmed: `520 / (15050 - 520) * 100 = 3.58`).
- `"all"` as a portfolio/item-history period means "no lower bound."
- Steam's raw inventory response actually includes a `more_items` field
  in the shape assumed here — standard, widely-documented Steam Web API
  behavior, but not independently re-verified against a live response;
  confirm the exact key/value shape empirically during implementation.
- The exact axis-label scheme for `"all"` in `chartConfig.js`'s
  `generateAxisLabels` is left as an implementation-time detail.
- `ItemTrendCache`'s 5-point/7-day shape matches `ItemRow`'s current
  sparkline window closely enough to not be a visible regression — the
  *resolution* drops, an intentional, visible simplification, not a bug.
- `inventories_spec.rb`'s hand-written `WebMock` stub is not migrated to
  VCR as part of this plan, despite this plan modifying that file and
  `fix_me.md` flagging the migration as due "next time this file is
  touched" — `vcr` isn't yet a dependency in either app, and this plan's
  changes to the file are unrelated to how the Steam call is stubbed
  (which, post `user-inventory-persistence.md`, may have moved to
  `UserInventorySyncService`'s own spec anyway — confirm during
  implementation which file actually owns that stub now).

## Applicable Styleguides

Re-checked after the architecture revision (endpoints 2/3 going
param-less) and after `.claude/plans/user-inventory-persistence.md`
amended several of these documents mid-session.

- `.claude/styleguides/fetcher/caching.md` — now documents **three**
  variants (bulk read-through, single-key read-through, TTL-only).
  `ItemTrendCache` fits the **bulk** variant exactly, same as
  `ItemPriceCache`/`PriceHistoryCache` — a new class with its own
  namespace/versioned key, not a second variant on `PriceHistoryCache`,
  so it doesn't reopen the multi-variant cache-key gap
  `price-history-long-windows.md` left unresolved. `UserInventoryCache`
  (single-key variant) is consumed as-is, not modified.
- `.claude/styleguides/fetcher/internal-api-controllers.md` — constrains
  every new `ItemPricesController` action: `Api::V1::` namespace,
  explicit routes, `current_steam_id`-only identity, `render json: {...},
  status:` shape, `{message:}` error bodies. Endpoints 2/3 are plain
  `GET`s with no body — the earlier `POST`-with-array-body design (and
  this styleguide's role in driving that correction) is now moot, since
  neither endpoint takes any input at all; see "Why endpoints 2/3 need
  no params."
- `.claude/adr/fetcher/cross-scenario-service-layer.md` (new, via
  `user-inventory-persistence.md`) — governs `UserInventorySyncService`,
  which this plan calls into indirectly (via `UserInventoryCache.fetch`)
  but does not modify; the `more_items` logging addition lives inside
  that service, not a new call site needing its own ADR carve-out.
- `.claude/styleguides/fetcher/background-jobs.md` — constrains the new
  `ItemTrendCache.invalidate` call added to `PriceUpdateWorker`'s
  existing success branch.
- `.claude/styleguides/fetcher/architecture-layers.md`,
  `.claude/styleguides/rails-layering.md` — confirm `ItemPricesController`
  fits Scenario 1 (synchronous, in-request) exactly like
  `InventoriesController`/the retired `PriceHistoriesController`; no new
  layer type introduced by this plan (the one new layer, `app/services/`,
  was introduced by the other plan, not this one).
- `.claude/styleguides/fetcher/steam-response-objects.md` — constrains
  the `more_items` addition to `Steam::Response::Data::InventoryData`:
  stays a `const` field parsed defensively in `from_hash`.
- `.claude/styleguides/ruby-sorbet.md` — constrains every new/changed
  Ruby file: `typed: strict`, `sig` on every method, `T.let`-wrapped
  constants (`PERIODS`, `TREND_WINDOW`, `TREND_POINTS`,
  `CACHE_KEY_VERSION`, `SAFETY_NET_TTL`).
- `.claude/styleguides/core/react-dashboard.md` — constrains the new
  hooks' shape (`{data, status, error}`, one hook per data source,
  `utils/` for pure derivation, no Context), the Recharts/Sparkline
  boundary (unchanged), and hook test structure. `useItemPrices`'
  bounded-retry/fake-timer testing shape still has no existing precedent
  — raised during the earlier `styleguides-check` pass and explicitly
  declined as a styleguide addition (treated as an interim mechanism
  ahead of the `prices_stream` WebSocket consumer, not worth codifying
  yet); that decision still stands unchanged by this revision.
- `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  confirms the React island keeps calling `app_fetcher` directly with
  the bridge token; no `app_core` proxy endpoint introduced.
- `.claude/styleguides/rspec-conventions.md` — constrains test level
  placement for every new/changed spec; its WebMock-vs-VCR rule
  surfaced the non-blocking `inventories_spec.rb` decision in
  Assumptions.
- `.claude/styleguides/git-commits.md` — this plan touches both apps;
  its implementation commit(s) use the `[Core+Fetcher]` scope tag. The
  two styleguide files updated for stale references are edited because
  of this task, so per "Task-Scoped Styleguides, ADRs, and Plans",
  bundle that edit into the same implementation commit.

## Completion Criteria

- [x] Desired behavior made explicit (all 5 endpoints, edge/failure
  cases, and how this plan now sits on top of
  `user-inventory-persistence.md`'s already-implemented persistence
  layer).
- [x] Scope explicit (what's rebuilt vs. reused vs. explicitly rejected,
  including everything now owned by the other, already-implemented
  plan).
- [x] Affected files/components identified, both apps.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (`styleguides-check` — see
  Applicable Styleguides above; re-run after the param-less revision and
  after `user-inventory-persistence.md`'s styleguide amendments landed).
- [x] Implemented — see Implementation Summary below.

# Implementation Summary

## Implemented

**`app_fetcher`**

- `Steam::Response::Data::InventoryData` gained `more_items: T::Boolean`
  (`!!hash["more_items"]` in `from_hash`); `UserInventorySyncService` logs
  `[UserInventorySyncService] steam_id=... inventory truncated (more_items)`
  right after a successful Steam call when that flag is set.
- `InventoriesController`'s shared private `render_inventory` no longer
  calls `enqueue_price_warmup` (removed along with `WARMUP_CAP`/
  `WARMUP_DEDUP_TTL`) and trims its `as_json` to `[:market_hash_name,
  :metadata]` — both `show` and `refresh` lost price fields and warmup in
  one edit, since they share this method.
- New `Api::V1::ItemPricesController` (`app/controllers/api/v1/item_prices_controller.rb`):
  - `#dynamics` (`GET /api/v1/item_prices/dynamics`, no params) — resolves
    owned names via `UserInventoryCache.fetch(current_steam_id)`, prices
    them via `ItemPriceCache.fetch_for`, computes `change_24h_percent`,
    owns the relocated warmup enqueue.
  - `#trend` (`GET /api/v1/item_prices/trend`, no params) — same name
    resolution, renders `ItemTrendCache.fetch_for(names)` directly.
  - `#history` (`GET /api/v1/item_prices/:market_hash_name/history`) —
    default period (`30d`) reuses `PriceHistoryCache.fetch_for([name])`;
    `7d`/`1y`/`all` bypass the cache via a direct `PriceLog` query with a
    computed lower bound; unsupported period → `:bad_request`.
- New `app/caching/item_trend_cache.rb` (`ItemTrendCache`) — bulk
  read-through + invalidation (third instance of that variant, alongside
  `ItemPriceCache`/`PriceHistoryCache`): `TREND_WINDOW = 7.days`,
  `TREND_POINTS = 5`, cursor-based downsampling (walks 5 evenly-spaced
  target timestamps, advances a forward-only index into the sorted logs,
  only emits a point when the picked log actually changed — no padded
  duplicates for sparsely-logged items).
- `PriceUpdateWorker` now calls `ItemTrendCache.invalidate` alongside the
  existing two invalidations on a successful price update.
- `InventoryValuesController#index` gained `period` (`7d`/`30d`/`1y`/`all`,
  default `all`), filtering an already-loaded, unfiltered `logs` array in
  memory (the self-seed check still runs against the unfiltered set);
  response is now a bare array with `date` (was `{points: [{log_date}]}`).
- `PriceHistoriesController` and its route/spec deleted — no remaining
  caller.
- `caching.md`/`internal-api-controllers.md` updated to stop citing the
  deleted controller as a canonical example/precedent (see Deviations for
  what was deliberately left untouched).

**`app_core`**

- `useDashboardData.js` reduced to a single skeleton fetch
  (`GET /api/v1/inventories/me`); mapped items carry no price data
  (`currentPriceCents: null`, `changeCents: 0`, `change24hPercent: 0`,
  `trendPoints: []`) until enriched downstream.
- Four new hooks: `useItemPrices` (bounded retry, `[3,6,12,24,45]`s,
  stops once the response covers every name or after 5 attempts),
  `useItemTrend`, `usePortfolioHistory`, `useItemHistory` — all gated on
  the skeleton's resolved name list where relevant (not re-triggering a
  sync themselves).
- `Dashboard.jsx` wires all four hooks, merges prices/trend onto skeleton
  items by `marketHashName`, and resolves `state.selectedItem` against
  the enriched `items` list each render (so a selected item's price stays
  current once `dynamics` resolves).
- `filters.js`'s `changePct` now reads `item.change24hPercent` directly.
- `marketVolume.js` sources volume from `item.trendPoints` instead of
  `item.priceHistory`.
- `ItemRow.jsx`'s sparkline reads `item.trendPoints` directly (no
  client-side windowing); delta badge gated on `currentPriceCents != null
  && !== 0`.
- `PortfolioTile.jsx` takes `portfolioSeries`/`itemHistorySeries`/
  `itemHistoryStatus` instead of a `portfolio` object; item mode no
  longer slices a client-side series and shows a loading state via
  `itemHistoryStatus === 'pending'`.
- `chartConfig.js`/`RangeToggle.jsx`: `RANGE_MS`/`RANGES`/`RANGE_SPAN`
  changed from `24h/7d/30d` to `7d/30d/1y/all`; `generateAxisLabels`
  special-cases `'all'` (only the trailing "today" tick is meaningful,
  no fabricated relative offset for the rest).
- `HeroChart.jsx`: `'all'`'s X-axis domain falls back to
  `['dataMin','dataMax']` instead of `now - RANGE_MS['all']`, since `'all'`
  has no fixed duration.
- Deleted: `portfolioSeries.js`, `itemSeries.js`, `sumAsOfEachHour` (in
  `bucketing.js`; `bucketByHour` stays), and their test files.

## Tests

- `app_fetcher`: `spec/lib/steam/response/data/inventory_data_spec.rb`
  (new, 3 examples), `spec/services/user_inventory_sync_service_spec.rb`
  (extended, +1), `spec/requests/api/v1/inventories_spec.rb` (updated,
  price-field-absence + warmup-removed assertions for both `show` and
  `refresh`), `spec/requests/api/v1/item_prices_spec.rb` (new, 18
  examples covering all three actions), `spec/caching/item_trend_cache_spec.rb`
  (new, 7 examples including boundary cases), `spec/workers/price_update_worker_spec.rb`
  (extended, third-cache assertions), `spec/requests/api/v1/inventory_values_spec.rb`
  (rewritten for the bare-array/`date` shape + 7 `period` scenarios).
  `price_histories_spec.rb` deleted.
- `app_core`: `useItemPrices.test.js` (new, 5 examples incl. fake-timer
  retry-schedule coverage), `useItemTrend.test.js`/`usePortfolioHistory.test.js`/
  `useItemHistory.test.js` (new, 10 examples total), `useDashboardData.test.js`
  (rewritten for the skeleton-only shape), `filters.test.js`/
  `marketVolume.test.js`/`ItemsTile.test.jsx`/`PortfolioTile.test.jsx`
  (fixtures and assertions updated for `change24hPercent`/`trendPoints`/
  the new `PortfolioTile` prop shape). `portfolioSeries.test.js` deleted.

Commands actually executed for every increment (RED confirmed before
every GREEN), and again at the end:

```
docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec [target]"
docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"
docker compose run --rm app_fetcher bash -c "bin/rubocop <touched files> -f simple"
docker compose run --rm app_fetcher bash -c "bundle exec srb tc"
npx vitest run [target]   # app_core/app/frontend
npx vitest run            # app_core/app/frontend, full suite
```

## Verification

- **`app_fetcher` full suite**: 113 examples, 0 failures (up from an
  82-example green baseline).
- **Rubocop** (all new/touched app files, both app and spec): 0 offenses.
- **`srb tc`**: 96 errors, up from the 82-error baseline recorded in
  `user-inventory-persistence.md`. Verified by category, not just count:
  all eight error codes present (5002, 6002, 7002, 7003, 7005, 7017,
  7027, 7048) were already pre-existing categories in that baseline — no
  new category introduced, just more instances on new files. Not part of
  this project's CI.
- **`app_core` full suite**: 57 tests across 12 files, 0 failures (up
  from a 48-test baseline).
- **Manual**: not performed live, matching this session's established
  environment-limitation precedent (no live Steam network access in this
  environment).

## Deviations

- **Styleguide reference cleanup scoped down from what a full sweep would
  touch.** `caching.md` and `internal-api-controllers.md` were updated
  (per the plan's own Files To Modify). A broader grep turned up stale
  `price_histories`/`PriceHistoriesController` mentions in
  `architecture-layers.md` (both apps), `rspec-conventions.md`,
  `react-dashboard.md`, and two ADRs (`rspec-testing-strategy.md`,
  `price-cache-invalidation.md`) — none of which the plan listed as
  Files To Modify. Left untouched rather than expanding scope
  unilaterally; flagged here instead (see Remaining Issues).
- **`UserInventorySyncService`'s spec, not a new standalone one, got the
  `more_items` logging test** — the plan's Test Plan hedged on "likely
  moves to a `resolve_inventory_spec.rb`/`user_inventory_sync_service_spec.rb`
  context... confirm during implementation." Confirmed: the Steam call
  lives in `UserInventorySyncService`, so its existing spec file is where
  the new example belongs.
- **`ItemRow`'s "no delta badge" test fixture changed meaning.** The old
  fixture modeled "priced item, empty price history" (a state that no
  longer exists the same way once price history isn't eagerly batched
  per item). Rewritten to model the actually-reachable equivalent: an
  item `dynamics` hasn't priced yet (`currentPriceCents: null`), which
  also updated the expected rendered price from `$90.00` to `—`
  (`fmtPrice`'s existing falsy-cents handling).
- **`PortfolioTile`'s "known current value with an empty series" test
  deleted, not preserved.** It asserted a client-computed
  `portfolio.currentValueCents` fallback that no longer exists (that
  computation lived in the now-deleted `portfolioSeries.js`). Replaced
  with a test asserting the honest new behavior: an empty series renders
  `$0.00`, not a fabricated sum.
- **`Dashboard.jsx` re-resolves `state.selectedItem` against the
  price/trend-enriched `items` list every render** (`items.find(...)`),
  not specified explicitly in the plan's Implementation Approach —
  needed so a selected item's hero-tile price updates once `dynamics`
  resolves (the reducer's own `state.selectedItem` is set once, at click
  time, from the not-yet-enriched item).

## Post-Implementation Fixes

Found via manual browser verification against a real Steam account (the
"Manual browser verification ... was not performed" item from Remaining
Issues, done in a follow-up session). Three issues surfaced; all three
fixed and covered by tests:

1. **Portfolio value was empty immediately after registration.**
   `GET /api/v1/inventory_values` used to enqueue
   `InventoryValueUpdateWorker` and return `[]` on a user's first-ever
   request, so the hero chart stayed empty until the next nightly cron
   run. Reworked to compute synchronously instead: `InventoryValueLog`
   gained a `record_for!(steam_id)` class method (pure DB read/sum/upsert,
   no external I/O — a plain model method per
   `.claude/styleguides/rails-layering.md`, not a service, unlike
   `UserInventorySyncService`), called directly from
   `InventoryValuesController#index` when no rows exist yet, and from
   `InventoryValueUpdateWorker#perform` (now a one-line delegate) for the
   nightly path — same computation, two callers. No more seed-job
   enqueue/dedup logic in the controller.
2. **No timestamp under the hero-chart tooltip's price.** `ChartTooltip`
   only ever rendered `payload[0].value` (the price), never
   `payload[0].payload.at` (the point's epoch-ms timestamp). Added
   `fmtDateTime` to `utils/format.js` and render it as a second line in
   the tooltip.
3. **Inconsistent empty states on `/item_prices/:name/history`.** An
   item's 7d/30d view could render zero points even though a
   `current_price_cents` was already known, if its only `PriceLog` row
   fell outside the requested window (1y/all always "won" because they
   cover the whole history). `ItemPricesController#history` now appends
   a synthetic "current price, now" point via a new private
   `with_current_price_point` whenever the queried window's last point
   doesn't already match the item's current price — mirrors the deleted
   client-side `itemSeries.js`'s old carry-forward step, now done once
   server-side instead of per-client.
   **Superseded** — see the Code Review Remediation addendum below:
   `with_current_price_point` was removed in a later pass per explicit
   code-review feedback (the root cause turned out to be a broken
   `fetcher_worker`, not a gap worth papering over with a synthetic
   point); a narrow window with no real logs now honestly returns `[]`
   again.

Verification: `item_prices_spec.rb` (20 examples, incl. 2 new covering the
fallback point directly), `inventory_values_spec.rb` (11 examples, rewritten
for the synchronous-seed behavior), new `inventory_value_log_spec.rb` (4
examples), `inventory_value_update_worker_spec.rb` (4 examples, unchanged),
new `format.test.js` coverage for `fmtDateTime` — full `app_fetcher` rspec
(119 examples) and `app_core` vitest (58 tests) suites green, rubocop clean
on all touched files. `srb tc` error count (97) is lower than this plan's
pre-implementation baseline (100, confirmed via `git stash`) — all
pre-existing gem/DSL RBI gaps, none introduced by this plan or its fixes.

## Remaining Issues

- Stale `price_histories`/`PriceHistoriesController` references in
  `architecture-layers.md` (both apps), `rspec-conventions.md`,
  `react-dashboard.md`, `rspec-testing-strategy.md`, and
  `price-cache-invalidation.md` — not fixed, out of this plan's stated
  scope (see Deviations). Worth a small follow-up pass.
- The pre-existing `NaN`-on-null-`currentPriceCents` gap in `filters.js`'s
  `price_desc`/`price_asc` comparators (flagged in this plan's own Risks
  before implementation) remains unfixed — more reachable now that prices
  arrive asynchronously, still not part of this plan's scope.
- No `app_core` UI trigger for `POST /api/v1/inventories/refresh` exists
  yet (confirmed out of scope by `user-inventory-persistence.md`); this
  plan didn't add one either.
- `srb tc`'s pre-existing baseline (gem/DSL RBI gaps) remains unfixed,
  unrelated to this change.
- Manual browser verification of the full login → skeleton → prices →
  trend → portfolio → item-click flow described in
  `.claude/US/dashboard-user-story.md` **was** performed in a follow-up
  session, via a temporary, explicitly user-authorized dev-login route
  (added, used, then fully reverted) — see Post-Implementation Fixes for
  the three issues it surfaced and how each was fixed.

## Code Review Remediation

A later code-review pass (direct user feedback on the already-implemented
code, not a new plan) made three further changes:

1. **`PERIODS` hashes replaced with a shared `PricePeriod` T::Enum**
   (`app_fetcher/app/models/price_period.rb`) — both
   `ItemPricesController` and `InventoryValuesController` had their own
   `T::Hash[String, T.nilable(ActiveSupport::Duration)]` constant for the
   same tag vocabulary (`"7d"`, `"30d"`, ...), duplicated and already
   drifted (only `ItemPricesController` had gained `"24h"`). Replaced
   with one enum (`.duration` method mapping each member to its
   `ActiveSupport::Duration`, `nil` for `All`), parsed via
   `.try_deserialize` and validated per-controller against its own
   `ALLOWED_PERIODS` array — `ItemPricesController` allows all five
   members, `InventoryValuesController` allows four (no `TwentyFourHours`,
   consistent with the frontend's `PORTFOLIO_RANGES`/`ITEM_RANGES` split).
   New precedent, documented in `.claude/styleguides/ruby-sorbet.md`.
2. **`with_current_price_point` removed from `ItemPricesController`.**
   Flagged in review as an unwarranted hack. Root-caused during the same
   session: the actual reason items showed sparse/stale narrow-window
   data wasn't a gap in this endpoint's logic — `fetcher_worker` had been
   crash-looping in this environment for weeks (stale gem bundle +
   missing `docker-compose.yml` env vars, both now fixed, unrelated to
   this plan), so most of the catalog's `PriceLog` data was simply
   three-weeks stale. Once real price data flows again, the fallback's
   job (papering over an empty window) mostly stops being needed; where
   a window genuinely has no logs, the endpoint now honestly returns
   `[]`. `item_prices_spec.rb`'s fallback-specific examples were removed;
   the base 24h/7d/30d/1y/all window-filtering coverage is unaffected
   (none of it depended on the fallback actually firing).
3. **`InventoryValueLog.record_for!` moved into a new
   `InventoryValueRecordingService`** (`app_fetcher/app/services/
   inventory_value_recording_service.rb`), called as
   `InventoryValueRecordingService.new(steam_id).call!` from both
   `InventoryValuesController#index`'s cold-start seed and
   `InventoryValueUpdateWorker#perform`. This is the second instance of
   `.claude/adr/fetcher/cross-scenario-service-layer.md`'s pattern — the
   ADR anticipated exactly this ("gives `app_fetcher` a scoped,
   precedented place for a second genuine cross-scenario case") and has
   been updated to document it, including the one deliberate deviation
   from `UserInventorySyncService`'s shape: an instance method
   (`.new(...).call!`) instead of a class method (`.call`), since no
   Steam I/O is involved and the user preferred that shape for this
   service. `spec/models/inventory_value_log_spec.rb` was deleted;
   `spec/services/inventory_value_recording_service_spec.rb` carries the
   same coverage against the new call shape.

Verification: full `app_fetcher` rspec (126 examples, 0 failures),
rubocop clean on all touched files (one pre-existing, unrelated offense
in `price_log_builder.rb` left untouched), `srb tc` unchanged (97,
pre-existing baseline). Docs updated alongside the code:
`.claude/adr/fetcher/cross-scenario-service-layer.md`,
`.claude/styleguides/fetcher/architecture-layers.md`,
`.claude/styleguides/fetcher/internal-api-controllers.md`,
`.claude/styleguides/ruby-sorbet.md`.
