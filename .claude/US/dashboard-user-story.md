---
type: user-story
scope: fetcher+core
status: target-state (see Status Snapshot — parts of this are already live, parts are pending `dashboard-api-redesign.md`)
updated: 2026-10-02
---

# The Dashboard User Story

## What this document is

A single, end-to-end narrative of the one user story this whole product
serves: a user logs into Steam, sees their inventory and its value, and
watches prices move. This is not a dev plan — it has no `implement-plan`
lifecycle, no Completion Criteria. It exists so a reader (human or a
future session) can answer "how does this actually work, front to back"
from one document, instead of reconstructing it from several plans'
Expected Behavior sections.

**Keep this in sync.** Whenever an endpoint, cache, or background job
described here changes, update this file in the same change — it should
never describe a flow the code has already moved past.

## Status snapshot

This document describes the **target state** once
`.claude/plans/dashboard-api-redesign.md` is implemented. As of this
writing:

- **Already live**: inventory persistence (`user_inventories`/
  `user_inventory_items`), `UserInventorySyncService`, the weekly sync
  scheduler, `POST /api/v1/inventories/refresh`, `InventoryValueLog`'s
  self-seeding, all price caching (`ItemPriceCache`/`PriceHistoryCache`)
  — see `.claude/plans/user-inventory-persistence.md`,
  `.claude/plans/inventory-value-history.md`,
  `.claude/plans/fetcher-price-caching.md`.
- **Pending implementation** (`.claude/plans/dashboard-api-redesign.md`,
  status `styleguide-checked`): `GET /api/v1/item_prices/dynamics`,
  `GET /api/v1/item_prices/trend`, `GET /api/v1/item_prices/:name/history`,
  `period` support on `inventory_values`, price fields dropped from
  `inventories/me`/`inventories/refresh`, `ItemTrendCache`, and all the
  `app_core` hook/component rewiring described below. `POST
  /api/v1/price_histories` is still the live history endpoint until
  that plan ships; this document describes its replacement.

## The story

**1. Login.** A user authenticates via Steam OpenID in `app_core`
(`SessionsController#callback` → `Steam::LoginUser.call`). An
already-signed-in visitor hitting `root_path` is redirected straight to
`/dashboard` (`HomePagesController`), so there's no extra click between
login and the dashboard on a return visit.

**2. Bridge token issued, page renders.** `DashboardsController#show`
mints a bridge token (`Steam::BridgeToken.encode(steam_id)` — JWT,
2-minute TTL, payload is just `{steam_id, exp, iat}`, no scopes) and
embeds it plus `APP_FETCHER_PUBLIC_URL` as `data-*` attributes on the
dashboard root `div`. From here on, **the browser talks to `app_fetcher`
directly** — no `app_core` proxy exists or is ever added
(`.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md`).
Every request below carries `Authorization: Bearer <bridge token>`.

**3. React mounts, fetches the skeleton.** `useDashboardData` calls
`GET /api/v1/inventories/me`. On the backend:

- `InventoriesController#show` calls `UserInventoryCache.fetch(current_steam_id)`
  — a single-key read-through cache in front of the real
  `user_inventories`/`user_inventory_items` tables (not a TTL guess; see
  Data & Caching Map).
- **Returning user** (cache hit or a live DB row): renders immediately —
  no Steam call.
- **First-ever visit** (no `user_inventories` row at all):
  `UserInventorySyncService.call(steam_id)` runs **synchronously,
  inside this request**: calls Steam, resolves which `market_hash_name`s
  already have an `Item` row vs. which are new, backfills the new ones
  (`Item.upsert_all`), persists `user_inventories`/`user_inventory_items`
  (full replace), invalidates `UserInventoryCache`. By the time the
  response is sent, this user's current inventory is durably saved —
  not just rendered in memory.
- Either way, the response is **prices-free**:
  `{ items_count, items: [{ market_hash_name, metadata }] }`. No
  `current_price_cents`, no warmup side-effect happens here anymore —
  this action's only job is "what does this user own."

React renders the full list immediately — all of it, no pagination (the
metadata-only payload is cheap even at ~500 items; see
`dashboard-api-redesign.md`'s Scope for why pagination here was
considered and rejected). Rows show name/weapon/condition/stattrak, no
prices yet, no sparklines yet.

**4. Prices and sparklines fill in, in parallel, once the skeleton has
resolved.** Two more fetches fire — gated specifically on the skeleton
fetch having reached `'success'`, not merely on mount, because both rely
on `UserInventoryCache` already having a row for this `steam_id` (step 3
guarantees that):

- `GET /api/v1/item_prices/dynamics` — **no params at all**. The
  controller re-derives "what does this user own" the same way `show`
  did (`UserInventoryCache.fetch(current_steam_id)`), then fetches
  **fresh** prices via `ItemPriceCache.fetch_for(names)` — deliberately
  a second cache call, not reused from `UserInventoryCache`'s own `Item`
  snapshot, because that snapshot is only invalidated when inventory
  *composition* changes, not when a price updates; it can be up to 15
  minutes stale on price. Returns
  `{ "<name>": {current_price_cents, change_24h_cents, change_24h_percent} }`
  for every owned, priced item. Unpriced items are omitted from the
  response **and** enqueue a capped, deduplicated warmup
  (`PriceUpdateWorker.perform_async`, max 20/request, 90s dedup).
- `GET /api/v1/item_prices/trend` — same no-param, same-derivation
  shape, but returns a heavily downsampled series (~5 points over the
  last 7 days) per owned item, backed by its own cache
  (`ItemTrendCache`). This feeds `ItemRow`'s sparkline and
  `MarketVolumeTile`'s aggregate volume — a full 30-day series would be
  wasted resolution for a 40×12px decorative line.

**A brand-new user's unpriced items get a second chance without
polling forever.** `useItemPrices` checks whether its response covers
every owned name; if not, it retries — `[3, 6, 12, 24, 45]` seconds,
summing to ~90s, deliberately matching `PriceUpdateWorker`'s own warmup
dedup window (the system's own estimate of "how long a warmup should
take"). Each retry just re-calls the same parameterless endpoint and
merges whatever's newly priced. After 5 attempts, or once everything's
covered — whichever first — it stops. An item still unpriced after that
stays that way until the next reload; nothing pushes updates proactively
(see "Why bounded retry" in `dashboard-api-redesign.md` for why a
WebSocket push was considered and deliberately deferred, not built now).

**5. The portfolio chart.** `usePortfolioHistory` calls
`GET /api/v1/inventory_values?period=30d` (the tile's default range).
Backend reads `InventoryValueLog` — one row per day per `steam_id`. A
genuinely new user (zero rows) gets an empty array back, and the
controller self-seeds: enqueues `InventoryValueUpdateWorker` (deduped
90s), which sums today's owned items' `current_price_cents` and writes
the first row. The chart is empty on the very first load and fills in
from the next reload (or the next night's scheduled run) — this is a
second, independent self-seed trigger from the skeleton's own cold-start
sync (see Risks in `user-inventory-persistence.md` for the known gap
between the two). Returning users just get their history, filtered to
the requested period (`7d`/`30d`/`1y`/`all` — note there's no `24h`
option; `InventoryValueLog` is daily-granularity by design).

**6. Clicking an item.** The hero chart switches to item-detail mode and
shows a loading state — no attempt to reuse the sparkline's 5-point
`trend` data for the detail view, even if the user is looking at the
same default period, since that'd make the fetch-or-not behavior of
"click an item" invisibly depend on which range was last selected
elsewhere. `useItemHistory` fetches
`GET /api/v1/item_prices/:market_hash_name/history?period=30d` (default;
`market_hash_name` URL-encoded — it contains `|`, parentheses, spaces).
For the default period this reuses the same `PriceHistoryCache` that
used to back `price_histories`; other periods query `PriceLog` directly.
Switching range re-fetches with a fresh loading state.

**7. What keeps all of this fresh in the background, independent of who's
looking.**

- `PriceScheduler` (hourly): finds every `Item` with a stale or missing
  price, enqueues `PriceUpdateWorker` per item.
- `PriceUpdateWorker`: calls Steam, writes a `PriceLog` row, updates
  `Item#current_price_cents`/`change_24h_cents`, publishes to the
  `prices_stream` Redis stream (write-ahead infrastructure for a future
  push-based consumer — currently unconsumed, deliberately), and
  invalidates **three** caches on success: `ItemPriceCache`,
  `PriceHistoryCache`, `ItemTrendCache`. Nothing invalidates on a failed
  Steam call.
- `UserInventorySyncScheduler` (daily trigger, but gated so it only acts
  roughly weekly per user): finds `user_inventories` rows older than 7
  days, enqueues `UserInventorySyncWorker` → the same
  `UserInventorySyncService.call` the cold-start path uses. A user's
  *inventory composition* (not price) is at most a week stale unless
  they hit the manual refresh button or revisit after a trade.
- `InventoryValueScheduler` (daily): fans out `InventoryValueUpdateWorker`
  to every `steam_id` that already has at least one `InventoryValueLog`
  row — pure DB read/sum/upsert, no Steam call (price freshness already
  comes from `PriceScheduler` independently).

**8. Manual refresh.** `POST /api/v1/inventories/refresh` (rate-limited,
once/day per `steam_id`) re-runs `UserInventorySyncService.call`
immediately — the user's lever against the weekly sync's staleness
window. Ships on the backend; no `app_core` UI button exists yet (an
explicit, separate future task).

## Endpoint Reference

| Endpoint | Auth | Params | Backend data source | Response shape |
|---|---|---|---|---|
| `GET /api/v1/inventories/me` | bridge token | none | `UserInventoryCache.fetch` → `UserInventorySyncService` on miss | `{items_count, items: [{market_hash_name, metadata}]}` |
| `POST /api/v1/inventories/refresh` | bridge token | none | `UserInventorySyncService.call` (rate-limited 1/day) | same as `show` |
| `GET /api/v1/item_prices/dynamics` | bridge token | none | `UserInventoryCache.fetch` → `ItemPriceCache.fetch_for` | `{name: {current_price_cents, change_24h_cents, change_24h_percent}}` |
| `GET /api/v1/item_prices/trend` | bridge token | none | `UserInventoryCache.fetch` → `ItemTrendCache.fetch_for` | `{name: [{at, price_cents, volume}]}` (≤5 pts, 7d) |
| `GET /api/v1/item_prices/:market_hash_name/history` | bridge token | `period` (`7d`\|`30d`\|`1y`\|`all`, default `30d`) | `PriceHistoryCache` (default) or direct `PriceLog` query | `[{at, price_cents, volume}]` |
| `GET /api/v1/inventory_values` | bridge token | `period` (`7d`\|`30d`\|`1y`\|`all`, default `all`) | `InventoryValueLog` (self-seeding) | `[{date, total_value_cents}]` |

## Data & Caching Map

| Data | Source of truth | Cache | Invalidated by |
|---|---|---|---|
| What a user owns | `user_inventories`/`user_inventory_items` (Postgres, FK to `items`) | `UserInventoryCache` (single-key read-through, 15 min safety TTL) | `UserInventorySyncService` (cold start, refresh, weekly sync) |
| An item's current price | `items.current_price_cents`/`change_24h_cents` | `ItemPriceCache` (bulk read-through, 15 min safety TTL) | `PriceUpdateWorker` (point invalidation, on success) |
| An item's 30-day history | `price_logs` | `PriceHistoryCache` (bulk read-through, 15 min safety TTL) | `PriceUpdateWorker` |
| An item's 7-day/5-point trend | `price_logs` (downsampled) | `ItemTrendCache` (bulk read-through, 15 min safety TTL) | `PriceUpdateWorker` |
| Daily portfolio value | `inventory_value_logs` | — (read live, one row/day) | n/a (self-seeded, nightly-updated) |

**The one correctness rule worth remembering**: `UserInventoryCache`
answers "what does this user own," never "what is it worth right now" —
anything rendering a price always goes through `ItemPriceCache`/
`PriceHistoryCache`/`ItemTrendCache`, even when `UserInventoryCache`'s
own cached `Item` rows technically carry price columns too.

## Sequencing Guarantee Worth Protecting

`dynamics`/`trend` assume a `user_inventories` row already exists for
the caller — they never trigger a sync themselves. This holds only
because the frontend gates both hooks on the skeleton fetch (`GET
/api/v1/inventories/me`) having already resolved. If that gate is ever
removed or bypassed, a brand-new user's very first `dynamics`/`trend`
call could race the skeleton's own cold-start sync and silently return
empty. Keep this ordering explicit in `Dashboard.jsx`, not implicit in
fetch timing.
