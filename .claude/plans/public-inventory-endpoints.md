---
status: implemented
app: fetcher
goal: Add two unauthenticated Api::Public:: endpoints in app_fetcher — a paginated inventories list and a per-inventory detail view with portfolio history and a top-items sub-list
created: 2026-10-11
---

# Development Plan

## Goal

Add `GET /api/public/inventories` (paginated/sortable list of synced
inventories) and `GET /api/public/inventories/:steam_id` (single
inventory detail: portfolio value/history, rarity breakdown, priciest
item, paginated/sortable `top_items`) to `app_fetcher`'s existing
`Api::Public::` namespace, following that namespace's established
conventions (no auth, the list-query-objects layer, TTL-only response
caching).

## Expected Behavior

### `GET /api/public/inventories`

- Succeeds with no `Authorization` header.
- `page`/`per_page`: default `1`/`24`, clamped silently (`page >= 1`,
  `1 <= per_page <= 100`); garbage/negative/zero/non-numeric → nearest
  valid value, never an error.
- `search`: accepted, never errors, **has no filtering effect** — there
  is no nickname (or any other searchable string) stored in
  `app_fetcher` for a `UserInventory` (see Scope/Decisions). This is
  deliberate, not a bug, and must be covered by a test proving it (see
  Test Plan).
- `sort`: default `value_desc`; one of `value_desc|items_desc|
  recently_synced|change_24h_desc`; unrecognized value → `400
  {"message":"Unsupported sort: <value>"}`.
- Response: `meta` (`page`, `per_page`, `total_count`, `total_pages`) +
  `inventories[]`, each: `steam_id`, `total_value_cents`,
  `change_24h_cents`, `change_24h_percent`, `items_count`,
  `rarity_mix_percent` (7 keys: `gold/covert/classified/restricted/
  mil_spec/industrial/consumer`, each a percent of `items_count`),
  `last_synced_at`. No `nickname`/`avatar_url`/`steam_level` (dropped,
  see Decisions).
- `total_count`/ordering reflect **every** `UserInventory` row — there is
  no filter that actually narrows the set in this version.
- An inventory with zero items appears with `items_count: 0`,
  `total_value_cents: 0`, `change_24h_cents: 0`, `change_24h_percent: 0.0`,
  every `rarity_mix_percent` tier `0.0`.

### `GET /api/public/inventories/:steam_id`

- Succeeds with no `Authorization` header.
- No `UserInventory` row for the given `steam_id` → `404 {"message":
  "Inventory not found"}`. A `UserInventory` row that exists but has zero
  items is **not** 404 — it returns a valid, all-zero/empty payload.
- Never triggers a live `Steam::Client` call and never auto-syncs — this
  is the behavioral difference from `Api::V1::InventoriesController#show`,
  which this endpoint must not replicate.
- `range`: default `7d`; one of `24h|7d|30d|1y|all` (same `PricePeriod`
  values); unrecognized value → `400 {"message":"Unsupported range:
  <value>"}`.
- `items_page`/`items_per_page`: default `1`/`12`, same clamp semantics
  as the list endpoint, scoped only to `top_items`.
- `items_sort`: default `price_desc`; one of `price_desc|price_asc|
  change_24h_desc|name_asc`; unrecognized value → `400 {"message":
  "Unsupported items_sort: <value>"}`.
- Response: `steam_id`, `last_synced_at`, `portfolio` (`total_value_cents`,
  `change_cents`, `change_percent`, `range`, `history[]`), `items_count`,
  `avg_item_value_cents`, `priciest_item` (`null` if no priced item
  exists), `rarity_breakdown[]` (`tier`/`count`/`percent`, same 7 tiers),
  `top_items` (`meta` + `entries[]`, same per-item shape as `GET
  /api/public/items`'s `items[]`). No `nickname`/`avatar_url`/
  `steam_level`.
- `portfolio.total_value_cents` is read from the most recent
  `InventoryValueLog` row for this `steam_id` (the same already-computed
  snapshot `history` is built from) — **not** recomputed live — except
  when that `steam_id` has zero log rows at all (never opened in
  `app_core`), in which case it falls back to a live, read-only sum over
  current `Item` prices (same formula `InventoryValueRecordingService`
  uses, just not persisted). See Decisions.
- `portfolio.history`/`change_cents`/`change_percent` are derived purely
  from whatever `InventoryValueLog` rows already exist for this
  `steam_id` within the `range` window — if none exist yet (the owner has
  never opened their `app_core` dashboard), `history` is `[]` and
  `change_cents`/`change_percent` are `0`/`0.0`. This is expected, not a
  bug (see Decisions).

### Unchanged

- `Api::V1::InventoriesController#show`/`#refresh` and their live-sync,
  never-404 behavior are untouched.
- `Api::Public::ItemsController#index` is untouched.

## Scope

### In Scope

- Two new `Api::Public::` controller actions, routes, and their full
  request-spec coverage.
- `InventoryCatalogQuery`/`InventoryCatalogSerializer`/
  `Options::InventorySortOption`/`InventoryCatalogCache` (endpoint 1).
- `InventoryDetailQuery`/`InventoryDetailSerializer`/
  `InventoryDetailCache` (endpoint 2), reusing the existing
  `Options::ItemSortOption`/`Appliers::*`/`PricePeriod`/`ItemTrendCache`.
- `RarityTier`, a new shared `T::Enum` classifying an `Item` into one of
  the 7 contracted tiers — used by both endpoints.
- A small, backward-compatible addition to `Appliers::Pagination` to
  support a caller-supplied default `per_page` (`24` for the list
  endpoint, `12` for `top_items`, vs. the existing hardcoded `25`).
- A new `rescue_from ActiveRecord::RecordNotFound` on
  `Api::Public::ApplicationController` for the 404 case.

### Out of Scope

- `nickname`, `avatar_url`, `steam_level` on any response — explicitly
  dropped (see Decisions). No new cross-app data flow, no new Steam Web
  API client, no new `app_core`→`app_fetcher` sync mechanism.
- Any new portfolio-history snapshot mechanism — `InventoryValueLog`'s
  existing once-daily granularity is used as-is for every `range` value,
  including `24h`.
- Making `search` actually filter anything.
- Rate-limiting for this still-unauthenticated namespace (already called
  out as out of scope in `public-items-catalog-endpoint.md`; `per_page`'s
  cap remains the only defense, same as the existing items endpoint).
- Negative/not-found caching for repeated lookups of a bogus `steam_id`.
- Migrations/schema changes — none are needed; no new columns anywhere.

## Decisions Carried From Research + Clarification

(Settled with Oleg; not to be revisited by `styleguides-check` or
`implement-plan` — see `project_public_inventory_endpoints_decisions`
memory.)

1. No `steam_level` anywhere in either response.
2. No `nickname`/`avatar_url` anywhere in either response — that data
   lives only in `app_core`'s own database and stays there.
3. `search` is accepted but intentionally never applied.
4. `portfolio.history` reuses `InventoryValueLog`'s existing daily
   snapshot unmodified, for every `range` — including sparse/empty
   history for inventories with no logged history yet.
5. Rarity-tier percentages are computed in `app_fetcher`.
6. 404 only when no `UserInventory` row exists at all for the `steam_id`.

### Decisions confirmed with Oleg during this planning pass

- **`Api::Public::` must stay a "plain read" namespace** (per
  `public-api-controllers.md`'s Purpose section: "every endpoint in this
  namespace is a plain read"). This rules out lazily seeding an
  `InventoryValueLog` row from either new endpoint the way
  `Api::V1::InventoryValuesController#index` does for its own
  authenticated caller — this endpoint never writes to it. Per Oleg's
  review (favor the already-computed snapshot over a live recomputation):
  endpoint 2's `portfolio.total_value_cents` reads the most recent
  existing `InventoryValueLog` row for this `steam_id` (the exact same
  source `history` already reads from, so the two can never disagree) —
  a live `Item`-price sum is only computed as a fallback, and only for a
  `steam_id` with zero log rows at all. This avoids the extra `Item` join
  entirely in the common case.
- **Endpoint 1's `total_value_cents`/`change_24h_cents` are computed from
  `Item#current_price_cents`/`Item#change_24h_cents` directly (summed
  across an inventory's items), not from `InventoryValueLog`** — the log
  table isn't guaranteed to exist for every synced inventory (only
  those viewed at least once in `app_core`), so it can't be the list
  endpoint's primary source without silently omitting inventories. This
  mirrors decision 4's spirit (no new snapshot machinery) by reusing data
  that's already written by the existing price-update pipeline.
- **Rarity tier classification** (`RarityTier`): any item whose
  `market_hash_name` starts with `★` (knives and gloves, which Steam
  doesn't tag with a distinct rarity string of their own in a way this
  codebase already parses) classifies as `gold`, regardless of its raw
  `rarity` tag. Everything else maps by its raw Steam `rarity` string:
  `"Consumer Grade"→consumer`, `"Industrial Grade"→industrial`,
  `"Mil-Spec Grade"→mil_spec`, `"Restricted"→restricted`,
  `"Classified"→classified`, `"Covert"→covert`. An item with a `nil` or
  unrecognized raw `rarity` string (and no `★` prefix) contributes to
  `items_count` but is excluded from the rarity percentage calculation
  entirely, per Oleg's review: the percent denominator is the count of
  *classified* items (items that resolved to some tier), not the
  inventory's total `items_count` — so the 7 tier percentages still sum
  to ~100% (modulo rounding) as long as at least one item classified,
  and all are `0.0` if none did. The raw per-tier `count` (in `rarity_
  breakdown`) is unaffected — only the percent's denominator changes.
- **`range` is resolved via `Appliers::SortApplier.call(params[:range],
  enum_class: PricePeriod, default: PricePeriod::SevenDays, param_name:
  "range")`**, even though `PricePeriod` isn't a "sort" option in the
  strict sense — Oleg agrees `range` is close enough in kind (a
  closed-enum selector resolved the same way) that reusing the applier
  as-is is the right call, not a hack. `styleguides-check` should still
  make this generalized reuse explicit in `list-query-objects.md` (today
  it's phrased purely in terms of sort/filter), but the design itself is
  settled.
- **The 404 case is implemented as `UserInventory.find_by!(steam_id:)`
  (bang) inside `InventoryDetailQuery.call`, raising
  `ActiveRecord::RecordNotFound`**, caught by a new `rescue_from` on
  `Api::Public::ApplicationController` rendering `{"message":"Inventory
  not found"}` / `:not_found`. This keeps `InventoryDetailQuery.call`
  from needing a `Result`-style wrapper (consistent with
  `list-query-objects.md`'s existing MUST), at the cost of extending
  `public-api-controllers.md`'s three documented error shapes to a
  fourth — `styleguides-check` must add this shape to that styleguide
  before `implement-plan` proceeds.
- **`avg_item_value_cents`** is defined as `total_value_cents /
  items_count` (integer division, `0` when `items_count` is `0`) — kept
  arithmetically consistent with `total_value_cents` rather than
  separately averaging only priced items.
- **`priciest_item`** excludes items with a `nil` `current_price_cents`
  explicitly (`.where.not(current_price_cents: nil)`) — Postgres sorts
  `NULL` first in a plain `ORDER BY ... DESC`, which would otherwise
  surface an unpriced item as "priciest."
- **`top_items` entries reuse `ItemCatalogSerializer#item_json`'s exact
  per-item shape** (metadata/price/change/`trend_7d` via
  `ItemTrendCache`), but as a second, independent implementation inside
  `InventoryDetailSerializer` rather than an extracted shared helper —
  consistent with this codebase's repeated precedent (`public-api-
  namespace.md`, the deferred base-service abstraction) of not
  generalizing from two call sites. Revisit if a third caller needs the
  same per-item shape.

## Implementation Approach

Both endpoints follow `Api::Public::ItemsController`'s established shape:
response-payload cache check → on miss, a `<Resource>Query.call` → a
`<Resource>Serializer.call` → cache write → `stale?`/render. Both reuse
the existing list-query-objects layer (`Appliers::Pagination`,
`Appliers::SortApplier`, `PricePeriod`, `Options::ItemSortOption`) rather
than inventing parallel mechanics, adding only what's genuinely new:
`Options::InventorySortOption` (endpoint 1's 4 sort values, which have no
existing equivalent) and `RarityTier` (shared rarity classification, used
by both).

**Endpoint 1 (`InventoryCatalogQuery`)** runs two queries total,
regardless of page size:
1. One `UserInventory` query, `GROUP BY user_inventories.id` over a
   `LEFT JOIN user_inventory_items JOIN items`, selecting
   `COUNT(items.id) AS items_count`, `COALESCE(SUM(items.
   current_price_cents), 0) AS total_value_cents`,
   `COALESCE(SUM(items.change_24h_cents), 0) AS change_24h_cents`
   alongside `user_inventories.*` — `Options::InventorySortOption#apply`
   orders by one of these aliases (or `user_inventories.updated_at` for
   `recently_synced`), then `Appliers::Pagination` applies `LIMIT`/
   `OFFSET`. `total_count` is a separate, cheap `UserInventory.count`
   (no filter narrows the set, so no need to re-derive it from the
   aggregated/paginated scope).
2. One `UserInventoryItem` query scoped to just the `user_inventory_id`s
   from the page above, pulling `(user_inventory_id, market_hash_name,
   rarity)` per item, folded in Ruby via `RarityTier.for_item` into
   per-inventory tier counts. Bounded by this page's inventories' item
   counts, not the whole catalog — acceptable for a page of ≤100
   inventories (see Risks for the upper bound).

`LEFT JOIN` (not `INNER JOIN`) matters here — an inventory with zero
items must still appear in the result with `items_count: 0`, not be
silently dropped by the join.

**Endpoint 2 (`InventoryDetailQuery`)** is a single-lookup query with one
embedded paginated/sorted sub-collection, not a flat list — it doesn't
try to force-fit the exact `ItemCatalogQuery::Page` shape:
1. `UserInventory.find_by!(steam_id:)` — raises on no match (404 path).
2. Resolve `range` (via `Appliers::SortApplier` against `PricePeriod`,
   see Decisions) and `items_sort`/`items_page`/`items_per_page` (via
   `Appliers::SortApplier`/`Appliers::Pagination` against
   `Options::ItemSortOption`, default `PriceDesc`).
3. One `items_count` query (`user_inventory.items.count`) — always live;
   `InventoryValueLog` tracks total value, not item count, so this has no
   cached substitute.
4. One `InventoryValueLog.where(steam_id:).order(:log_date)` query (all
   rows, unfiltered by `range`) to find `latest_log = logs.last`.
   `total_value_cents = latest_log&.total_value_cents`, falling back to a
   live `user_inventory.items.sum(:current_price_cents)` (`pluck`/`sum`,
   one query) **only** when `logs` is empty — i.e. only ever one of these
   two queries actually runs per request. `avg_item_value_cents` derives
   from `total_value_cents`/`items_count` in Ruby, whichever source
   produced `total_value_cents`.
5. From the same `logs` loaded in step 4, slice to the `range` window in
   Ruby (`since = range.duration&.ago&.to_date`; `logs_in_range = since ?
   logs.select { |l| l.log_date >= since } : logs`) — no second query.
   `history` maps `logs_in_range` to `{at: log.created_at.iso8601,
   total_value_cents: log.total_value_cents}`. `change_cents`/
   `change_percent` compare `logs_in_range.first`/`.last` (`0`/`0.0` if
   fewer than 2 rows in range).
6. One query for `priciest_item` (`.where.not(current_price_cents: nil)
   .order(current_price_cents: :desc).first`).
7. One query for the full item set's `(market_hash_name, rarity)` pairs,
   folded via `RarityTier.for_item` into `rarity_breakdown`'s
   counts/percents (same fold logic `RarityTier` provides for endpoint
   1 — reused, not reimplemented; percent's denominator is the classified
   count, not `items_count` — see Decisions).
8. One paginated `Item` query (`user_inventory.items`, sorted via
   `items_sort`, limited/offset via `items_page`/`items_per_page`) for
   `top_items`, plus `ItemTrendCache.fetch_for` for their `trend_7d`.

## Files To Modify

- `app_fetcher/config/routes.rb` — add, inside the existing `namespace
  :public do ... end` block: `get "inventories", to:
  "inventories#index"` and `get "inventories/:steam_id", to:
  "inventories#show"`.
- `app_fetcher/app/controllers/api/public/application_controller.rb` —
  add `rescue_from ActiveRecord::RecordNotFound, with:
  :render_not_found`, declared **after** the existing `rescue_from
  StandardError` (ordering rule from `public-api-controllers.md`'s Error
  Handling section: most-specific handler declared last), rendering
  `{ message: "Inventory not found" }` / `:not_found`.
- `app_fetcher/app/queries/appliers/pagination.rb` — add an optional
  `default_per_page: DEFAULT_PER_PAGE` keyword argument to `#initialize`
  (backward-compatible; `ItemCatalogQuery`'s existing call sites keep
  getting `25` unless they opt in). `InventoryCatalogQuery` passes `24`;
  `InventoryDetailQuery`'s `top_items` pagination passes `12`.
- `app_fetcher/spec/queries/appliers/pagination_spec.rb` — add coverage
  for the new `default_per_page:` keyword (default unchanged when
  omitted; a caller-supplied default is honored when `per_page` is
  absent/blank).

## Files To Create

- `app_fetcher/app/models/rarity_tier.rb` — `RarityTier < T::Enum` with
  the 7 tier values and a `self.for_item(item)` classifier (★-prefix →
  `Gold`; else raw `rarity` string lookup; `nil` if unrecognized). Shared
  by both new endpoints. Placed in `app/models/` alongside `PricePeriod`
  (same kind of small, standalone domain `T::Enum`, not tied to any one
  controller's query/options layer).
- `app_fetcher/app/queries/options/inventory_sort_option.rb` —
  `Options::InventorySortOption < T::Enum` (`ValueDesc`, `ItemsDesc`,
  `RecentlySynced`, `ChangeDesc`), each `#apply(scope)` ordering by the
  matching aliased aggregate column or `user_inventories.updated_at`.
- `app_fetcher/app/queries/inventory_catalog_query.rb` —
  `InventoryCatalogQuery.call(params)`, per Implementation Approach.
  Returns a `Page` `T::Struct` (inventory rows with their aggregates,
  per-inventory rarity tier counts, pagination, total count).
- `app_fetcher/app/serializers/inventory_catalog_serializer.rb` —
  `InventoryCatalogSerializer.call(page)`, pure function, builds the
  `meta`/`inventories[]` response hash including `change_24h_percent`
  and `rarity_mix_percent` computation.
- `app_fetcher/app/caching/inventory_catalog_cache.rb` —
  `InventoryCatalogCache` (`.read`/`.write`, TTL-only, versioned key
  normalizing `page`/`per_page`/`sort`; `search` deliberately excluded
  from the key since it has no effect — see Decisions).
- `app_fetcher/app/queries/inventory_detail_query.rb` —
  `InventoryDetailQuery.call(steam_id, params)`, per Implementation
  Approach. Raises `ActiveRecord::RecordNotFound` for an unknown
  `steam_id`. Returns a `Page` `T::Struct` carrying everything the
  serializer needs.
- `app_fetcher/app/serializers/inventory_detail_serializer.rb` —
  `InventoryDetailSerializer.call(page)`, pure function, builds the full
  detail response hash including `rarity_breakdown`, `portfolio`, and
  `top_items` (reimplementing the per-item JSON shape, see Decisions).
- `app_fetcher/app/caching/inventory_detail_cache.rb` —
  `InventoryDetailCache` (`.read`/`.write`, TTL-only, versioned key:
  `["inventory_detail", 1, steam_id, Digest::SHA256.hexdigest(...)]`
  where the digest normalizes `range`/`items_page`/`items_per_page`/
  `items_sort`).
- `app_fetcher/app/controllers/api/public/inventories_controller.rb` —
  `Api::Public::InventoriesController` with `#index`/`#show`, each
  following the cache→query→serializer→cache-write→`stale?` sequence.

### Spec files to create

- `app_fetcher/spec/models/rarity_tier_spec.rb`
- `app_fetcher/spec/queries/options/inventory_sort_option_spec.rb`
- `app_fetcher/spec/queries/inventory_catalog_query_spec.rb`
- `app_fetcher/spec/serializers/inventory_catalog_serializer_spec.rb`
- `app_fetcher/spec/caching/inventory_catalog_cache_spec.rb`
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb`
- `app_fetcher/spec/serializers/inventory_detail_serializer_spec.rb`
- `app_fetcher/spec/caching/inventory_detail_cache_spec.rb`
- `app_fetcher/spec/requests/api/public/inventories_spec.rb`

## Test Plan

Follow `spec/requests/api/public/items_spec.rb`'s structure and
`rspec-conventions.md`'s layer→level mapping throughout (unit specs for
every `app/queries/`, `app/serializers/`, `app/caching/`,
`app/models/` class; one request spec per controller covering the HTTP
boundary only).

**`RarityTier` (unit):** every one of the 6 raw-string mappings; a `★`
market_hash_name overriding a non-gold-looking raw rarity (and one with
no raw rarity at all, to prove the prefix alone is sufficient); `nil`
rarity + no `★` prefix → `nil` tier.

**`Options::InventorySortOption` (unit):** each of the 4 values actually
orders real (factory-built) `UserInventory` rows with distinct
aggregates — not just that the right `case` branch is hit, per
`list-query-objects.md`'s testing rule.

**`InventoryCatalogQuery` (unit, hits the DB for real):** aggregates are
correct for an inventory with multiple items of mixed prices/changes;
zero-item inventory appears with all-zero aggregates (proves the `LEFT
JOIN`); `total_count` reflects every `UserInventory` regardless of page;
rarity tier counts are correct and properly scoped per-inventory (two
inventories with different rarity mixes don't bleed into each other);
`sort`'s default and all 4 values; pagination clamping edge cases
(reusing `Appliers::Pagination`'s own coverage, just confirming it's
wired in).

**`InventoryCatalogSerializer` (unit, zero I/O, unsaved structs only):**
`change_24h_percent` arithmetic (including zero-base-value guard);
`rarity_mix_percent` arithmetic including an inventory with an
unrecognized-rarity item — asserting the percent denominator is the
*classified* item count (percentages across the 7 tiers sum to ~100%,
not less), and all-zero tiers when nothing classified; `last_synced_at`
formatting.

**`InventoryDetailQuery` (unit, hits the DB for real):** raises
`ActiveRecord::RecordNotFound` for an unknown `steam_id`; zero-item
inventory returns valid zero/empty aggregates (not 404); `priciest_item`
excludes `nil`-priced items; `avg_item_value_cents` arithmetic;
`total_value_cents` reads the latest `InventoryValueLog` row when one
exists (and a DB query count assertion proving no `Item`-sum query ran in
that case), falls back to a live `Item` sum only when zero log rows
exist; `range`'s default and all 5 values, including `all` (no date
filter); `history`/`change_cents`/`change_percent` reflect exactly the
`InventoryValueLog` rows in-window, `[]`/`0`/`0.0` when none exist in
range (even if earlier/later rows exist outside it); `items_sort`'s
default and all 4 values applied to `top_items`; `items_page`/
`items_per_page` clamping and pagination `meta`.

**`InventoryDetailSerializer` (unit, zero I/O):** full response shape
assembly from an in-memory `Page` struct, mirroring
`item_catalog_serializer_spec.rb`'s style.

**Both caching classes (unit, real `Rails.cache`):** hit/miss/key-
normalization, per `caching.md`'s testing rules — in particular,
`InventoryCatalogCache` must prove two requests differing only in
`search` hit the *same* cache entry (since `search` is excluded from the
key).

**Request specs (`spec/requests/api/public/inventories_spec.rb`,
boundary-only, mirroring `items_spec.rb`):**
- No-`Authorization`-header success case for both actions.
- List: `search` present vs. absent returns the identical result set
  (the no-op proof named explicitly in Expected Behavior); each `sort`
  value; `sort=bogus` → `400`; page/per_page clamp edge cases; response
  shape contains exactly the contracted keys (no `nickname`/
  `avatar_url`/`steam_level` leaking in); caching via `count_queries`;
  conditional-GET (`ETag`/`:not_modified`).
- Detail: unknown `steam_id` → `404 {"message":"Inventory not found"}`;
  zero-item but existing `UserInventory` → `200` with all-zero fields;
  each `range`/`items_sort` value; `range=bogus`/`items_sort=bogus` →
  `400` with the right param name in the message; `items_page`/
  `items_per_page` clamp edge cases; response shape contains exactly the
  contracted keys; caching; conditional-GET.
- Unhandled-error shape for both actions (mirroring `items_spec.rb`'s
  "internal error" case).

## Implementation Steps

1. Add `RarityTier` + its unit spec — no dependents yet, safe to land
   first and TDD in isolation.
2. Extend `Appliers::Pagination` with `default_per_page:` + update its
   spec — small, backward-compatible, unblocks both new query objects.
3. Add `Options::InventorySortOption` + its unit spec.
4. Add `InventoryCatalogQuery` + its unit spec (depends on 1–3).
5. Add `InventoryCatalogSerializer` + its unit spec.
6. Add `InventoryCatalogCache` + its unit spec.
7. Add `InventoryDetailQuery` + its unit spec (depends on 1–2, reuses
   existing `Options::ItemSortOption`/`PricePeriod`/`Appliers::*`).
8. Add `InventoryDetailSerializer` + its unit spec.
9. Add `InventoryDetailCache` + its unit spec.
10. Add `rescue_from ActiveRecord::RecordNotFound` to
    `Api::Public::ApplicationController`.
11. Add `Api::Public::InventoriesController` (`#index`/`#show`) wiring
    steps 3–10 together, plus the two routes.
12. Write `spec/requests/api/public/inventories_spec.rb` covering the
    full boundary contract (Test Plan's request-spec bullets).
13. Run the full `app_fetcher` spec suite + `srb tc` + `bin/rubocop` (see
    Verification).

## Verification

- `bundle exec rspec` (all new/changed spec files, then the full
  `app_fetcher` suite to catch regressions, in particular anything
  touching `Appliers::Pagination`'s existing callers).
- `bin/srb tc` (Sorbet) — this codebase's layers are `typed: strict`
  throughout; every new file needs a clean `sig` pass, and `fix_me.md`
  shows this project already treats `srb tc` failures as real, not
  noise.
- `bin/rubocop` (rubocop-rails-omakase, per `ruby-sorbet.md`/existing
  convention).
- Manual check (via `curl`/HTTPie against a dev server, since there's no
  browser UI for this endpoint yet): both endpoints against a seeded
  inventory, confirming response shape matches the (amended) contract
  exactly and that no `nickname`/`avatar_url`/`steam_level` key appears
  anywhere.

## Risks

- **Rarity-breakdown query cost scales with the page's total item count**
  (sum of `items_count` across up to `per_page` inventories on one list
  page, or a single inventory's full item count on the detail page) —
  for a 24-inventory page where some inventories hold hundreds of items,
  this is a few-thousand-row pluck, not a handful. Mitigated by the
  response-payload TTL cache (same mitigation `ItemCatalogCache` already
  relies on) but not bounded independently — acceptable for v1, revisit
  if real inventory sizes make this a measured problem.
- **Items with an unrecognized/`nil` raw `rarity` string are excluded
  from the rarity percentage base** (both tier `count` and the
  percentage denominator), so an inventory where every item has
  unrecognized rarity data shows all-zero percentages. Accepted per
  Decisions, but worth revisiting once real data is checked — if Steam
  inventory data turns out to carry rarity gaps more often than expected,
  the all-zero case may look broken in the UI even though it's
  technically correct.
- **`styleguides-check` will very likely require `update-styleguide` on
  `public-api-controllers.md`** (new 404 error shape) before
  `implement-plan` can proceed — flagged explicitly so that stage isn't
  a surprise. It should also extend `list-query-objects.md`'s description
  of `Appliers::SortApplier` to cover closed-enum params in general
  (confirmed acceptable for `range`/`PricePeriod`, not just `Options::*`
  sort enums).
- **`portfolio.total_value_cents`'s fallback path (live `Item` sum, used
  only when a `steam_id` has zero `InventoryValueLog` rows) means a
  freshly-synced-but-never-dashboarded inventory's total is computed
  differently than an already-logged one** — same number in spirit, but
  a different code path with its own test coverage obligation (see Test
  Plan); watch for this branch silently going untested if
  `implement-plan` only exercises the common (already-logged) case.

## Applicable Styleguides

- `.claude/styleguides/fetcher/public-api-controllers.md` — constrains
  the whole namespace/controller shape for both new actions: no auth,
  explicit routes, `{message: "..."}` error bodies, the four query-param
  handling postures (bounded numeric, open string-set, closed-enum,
  boolean), and — after this round's amendment — the `ActiveRecord::
  RecordNotFound` → `rescue_from` → `404 {"message":"Inventory not
  found"}` shape the detail endpoint's `Missing Styleguides` gap needed.
- `.claude/styleguides/fetcher/list-query-objects.md` — constrains
  `InventoryCatalogQuery`/`InventoryCatalogSerializer`/
  `Options::InventorySortOption` (the existing flat-list shape) and, after
  this round's amendment, `InventoryDetailQuery`/
  `InventoryDetailSerializer` (the new detail-with-nested-sub-collection
  shape), the generalized reuse of `Appliers::SortApplier` for `range`/
  `PricePeriod`, and `Appliers::Pagination`'s new `default_per_page:`
  keyword.
- `.claude/styleguides/fetcher/caching.md` — constrains
  `InventoryCatalogCache` (TTL-only, no-natural-identifier hashed key,
  `search` deliberately excluded) and, after this round's amendment,
  `InventoryDetailCache` (TTL-only, the new hybrid natural-id-plus-hash
  key shape).
- `.claude/styleguides/fetcher/architecture-layers.md` — constrains where
  `RarityTier` lives (`app/models/`, alongside `PricePeriod`) and confirms
  query objects/serializers are a Scenario-1-only concern, consistent
  with both new controller actions.
- `.claude/styleguides/rails-layering.md` — constrains the thin-
  controller/orchestration/model dependency direction both new actions
  and their query objects follow.
- `.claude/styleguides/ruby-sorbet.md` — constrains every new file's
  Sorbet discipline (`typed: strict`, `sig` on every method, `T::Enum`
  for `RarityTier`/`Options::InventorySortOption`, `T::Struct` for both
  query objects' return values, explicit generic collection types).
- `.claude/styleguides/rspec-conventions.md` — constrains spec placement/
  level for every new class (unit specs under `spec/queries/`,
  `spec/serializers/`, `spec/caching/`, `spec/models/`; one request spec
  per controller for the HTTP boundary), `FactoryBot` usage, and the
  `aggregate_failures`/`let`/`subject` structuring rules.

## Assumptions

- TTL for both new caches: 2 minutes, matching `ItemCatalogCache`'s
  existing TTL for the same reasoning (read-heavy, no faster-than-that
  freshness requirement) — not explicitly specified by Oleg; revisit if
  a different freshness tolerance is wanted.
- `items_per_page`'s upper clamp bound reuses `Appliers::Pagination`'s
  existing `100` (the contract didn't specify a separate bound for
  `top_items`).
- `change_24h_percent`/rarity percentages: `change_24h_percent` rounds to
  2 decimal places (matching `ItemCatalogSerializer`'s existing
  convention); rarity percentages round to 1 decimal place (matching the
  contract's own examples, all shown to 1 decimal).
- `rarity_mix_percent`/`rarity_breakdown` on a zero-item inventory: every
  tier is `0.0` (not `null`/omitted).

# Implementation Summary

## Implemented

Both endpoints, end to end, exactly as planned:

- `RarityTier` (`app/models/rarity_tier.rb`) — 7-tier `T::Enum`, `★`-prefix
  → `Gold`, else raw-rarity-string lookup, `nil` for unrecognized.
- `Appliers::Pagination` — added the `default_per_page:` keyword
  (backward-compatible; existing `25` default untouched for callers that
  don't pass it). Also fixed a latent gap this change exposed: the old
  `clamp` returned an unclamped `default` on a blank raw value, which
  would have let an out-of-range `default_per_page:` bypass `min`/`max`
  entirely — `clamp` now bounds the default the same way it bounds a raw
  value.
- `Options::InventorySortOption` (`app/queries/options/`) — 4 values
  ordering an aggregated `UserInventory` scope.
- `InventoryCatalogQuery`/`InventoryCatalogSerializer`/
  `InventoryCatalogCache` — the list endpoint, exactly per the plan's
  two-query design (aggregated+paginated `UserInventory` pluck, then one
  scoped rarity-tier pluck for just that page's inventories).
- `InventoryDetailQuery`/`InventoryDetailSerializer`/
  `InventoryDetailCache` — the detail endpoint: `find_by!` for the 404
  path, `InventoryValueLog`'s latest row for `total_value_cents` (live
  `Item`-sum fallback only when no log rows exist), range-windowed
  history/change, `top_items` via the existing `Options::ItemSortOption`/
  `ItemTrendCache`.
- `Api::Public::ApplicationController` — new `rescue_from
  ActiveRecord::RecordNotFound` rendering the 404 shape, declared after
  `rescue_from StandardError` per the ordering rule.
- `Api::Public::InventoriesController` (`#index`/`#show`) + the two new
  routes under `namespace :public`.
- Two Sorbet DSL RBIs (`sorbet/rbi/dsl/user_inventory.rbi`,
  `sorbet/rbi/dsl/inventory_value_log.rbi`), generated via `bundle exec
  tapioca dsl UserInventory InventoryValueLog` — not listed in the
  original plan, but necessary per `ruby-sorbet.md`'s existing DSL-RBI
  rule (same precedent as `Item`'s own RBI): neither model had one yet,
  so Sorbet couldn't resolve their columns/associations at all before
  this change.

## Tests

All per the plan's Test Plan, TDD'd red→green file by file:

- `spec/models/rarity_tier_spec.rb`
- `spec/queries/appliers/pagination_spec.rb` (extended)
- `spec/queries/options/inventory_sort_option_spec.rb`
- `spec/queries/inventory_catalog_query_spec.rb`
- `spec/serializers/inventory_catalog_serializer_spec.rb`
- `spec/caching/inventory_catalog_cache_spec.rb`
- `spec/queries/inventory_detail_query_spec.rb`
- `spec/serializers/inventory_detail_serializer_spec.rb`
- `spec/caching/inventory_detail_cache_spec.rb`
- `spec/requests/api/public/inventories_spec.rb`

Commands actually executed (inside the project's `app_fetcher`
container, via `docker compose run --rm -e RAILS_ENV=test app_fetcher
bundle exec rspec ...`):

- Each new/changed spec file individually, red before the corresponding
  implementation existed, green after.
- `bundle exec rspec` (full `app_fetcher` suite) — twice: once mid-way as
  a regression check, once as the final pass.
- `bundle exec rubocop` — targeted at new/changed files, then the full
  `app_fetcher` tree.
- `bundle exec srb tc` — full run, three times (iterating on the type
  errors described in Deviations below).
- A manual end-to-end check via `bin/rails runner` driving an
  `ActionDispatch::Integration::Session` against the dev database (see
  Deviations for why not a bound dev server).

## Verification

- **Tests**: final full-suite run — `320 examples, 1 failure`. The one
  failure (`spec/caching/user_inventory_cache_spec.rb:18`) is
  pre-existing: confirmed present, identical, and deterministic in a
  baseline run taken *before* any change in this plan, on a file this
  plan never touches (`UserInventoryCache`). Every one of the 89 new
  examples added by this plan passes.
- **Rubocop**: `129 files inspected, 33 offenses detected` — all 33 in
  pre-existing files this plan doesn't touch (e.g. `lib/steam/client.rb`,
  `spec/workers/price_update_worker_spec.rb`); zero offenses in any
  new/modified file (confirmed by a targeted rubocop run against just
  those files: 35 files, 0 offenses).
- **Sorbet (`srb tc`)**: baseline (before this change) was 106 errors;
  final is 120 (+14). Verified every one of the 14 is one of two already-
  understood categories, not a new class of problem:
  - 9 are `Unable to resolve constant RSpec` on the 9 brand-new spec
    files — a pre-existing, codebase-wide noise pattern already present
    identically on every existing spec file (confirmed: e.g.
    `spec/models/item_spec.rb`, untouched by this plan, has the same
    error).
  - 5 are `Method 'apply'/'duration' does not exist on T::Enum` /
    `Expected PricePeriod but found T::Enum`, all stemming from
    `Appliers::SortApplier.call`'s return type being the generic
    `T::Enum` rather than the specific enum class — an explicitly
    documented, accepted gap in `.claude/adr/fetcher/
    list-query-objects-layer.md`'s own "Negative" consequences section
    ("a real, accepted gap in static checking until a second resource's
    `Options::*` classes exist to validate the right bound against").
    `app/queries/item_catalog_query.rb` (pre-existing, untouched)
    reproduces the identical `apply`-on-`T::Enum` error today, confirming
    this is the same known pattern, not a new one. Fixing the underlying
    bound is an unplanned refactor of `Appliers::SortApplier`'s typing,
    out of scope for this plan.
  - Three genuinely new type issues surfaced during implementation *were*
    fixed (not left as gaps) — see Deviations.
- **Manual check**: seeded a real inventory (a `★`-prefixed knife + a
  rifle) in the dev database and drove both endpoints through the real
  routing/controller/cache/query/serializer stack. Response shapes
  matched the (amended) contract exactly, including `gold` tier correctly
  overriding the knife's raw `"Covert"` rarity tag, and 404 for an unknown
  `steam_id` returned `{"message":"Inventory not found"}`. No
  `nickname`/`avatar_url`/`steam_level` key appeared in either response.
  Seeded records were deleted afterward.

## Deviations

- **Two DSL RBIs generated beyond the plan's file list** — see
  Implemented; required for the new `typed: strict` query objects to
  resolve `UserInventory`/`InventoryValueLog` columns/associations at
  all, per `ruby-sorbet.md`'s existing rule and `Item`'s own precedent.
- **`Appliers::Pagination#clamp` also got a one-line fix** beyond adding
  the keyword arg itself: the default value is now bounded the same way
  a raw value is (see Implemented) — a correctness gap the new
  `default_per_page:` parameter exposed, not something safe to leave
  given a caller could now pass an out-of-range default.
- **Three Sorbet type issues fixed during implementation, not in the
  original plan**:
  - `user_inventory.items.sum(:current_price_cents)` (`T.any(Integer,
    Float, BigDecimal)`) → `.to_i`, so `total_value_cents`/
    `avg_item_value_cents` stay `Integer` as declared.
  - `logs_in_range.first`/`.last` inside `change_for` (Sorbet can't infer
    non-nil from a prior `.size < 2` guard) → wrapped in `T.must(...)`,
    the same idiom `srb tc`'s own autocorrect suggested.
  - The ternary building `change_percent` could statically resolve to
    `T.any(Integer, Float)` (via `Float#round`'s own loose signature)
    against a sig requiring a strict `[Integer, Float]` tuple → added an
    explicit `.to_f`.
  None of these change any tested behavior (all specs for
  `InventoryDetailQuery` still pass identically before/after).
- **Manual verification used `ActionDispatch::Integration::Session` via
  `bin/rails runner`, not a bound dev server on port 3001** — that port
  was already occupied by a different, unrelated running environment
  (`blissful-lederberg-...-app_fetcher-1`) not owned by this session;
  stopping it was out of scope/risky. The integration-session approach
  exercises the identical routing/middleware/controller stack a bound
  server would, so this is not a reduction in verification confidence.

## Remaining Issues

- The pre-existing `UserInventoryCache.fetch` spec failure and the
  pre-existing Sorbet gaps noted above (the `item_catalog_query.rb`-style
  generic-`T::Enum` pattern, the unrelated `application_controller.rb`
  `JWT` constant errors, `PriceLog`'s own missing DSL RBI, etc.) are all
  unrelated to this plan and were not fixed, per "modify only files
  required by the plan." Worth a separate pass if Oleg wants `srb tc`
  genuinely green at some point.
- Per the plan's own Risks section: items with no recognized rarity tier
  are excluded from `rarity_mix_percent`/`rarity_breakdown`'s percentage
  base entirely — worth revisiting once real Steam inventory data shows
  how often that actually happens.
