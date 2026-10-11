---
status: implemented
app: fetcher
goal: Add a public, unauthenticated, paginated/filterable items-catalog endpoint in app_fetcher, backed by a new TTL-only cache and HTTP cache headers, plus the category metadata it depends on
created: 2026-10-11
---

## Applicable Styleguides

- **`.claude/styleguides/fetcher/public-api-controllers.md`** (new,
  backed by `.claude/adr/fetcher/public-api-namespace.md`) — governs the
  entire `Api::Public::` namespace this plan introduces: its own
  `Api::Public::ApplicationController` with an independently-declared
  `rescue_from StandardError` (duplicated from, not shared with,
  `Api::V1::ApplicationController` — the ADR's explicit decision, with a
  named revisit trigger at a third namespace), and all four query-param
  handling rules the plan's Expected Behavior section relies on: clamp
  (don't reject) bounded numerics (`page`/`per_page`), reject-on-
  unrecognized only for the closed `sort` enum, never-error for the
  open-string-set `category[]`/`rarity[]` filters, and the `"true"`-only
  opt-in semantics for `stattrak`. Also the source of the `per_page` cap
  being framed explicitly as a stopgap pending real rate-limiting, not a
  substitute for it.
- **`.claude/styleguides/fetcher/caching.md`** (amended) — governs
  `ItemCatalogCache` as the first real implementation of the TTL-only
  variant, including the newly-added composite-key rule (normalize
  array/string inputs, then `Digest::SHA256.hexdigest` into the `id`
  component of the standard versioned-array key shape) that this plan's
  cache-key construction directly follows. Also governs the TTL being a
  deliberate, freshly-reasoned class constant (not copied from another
  class's safety-net value) and the Testing section's "assert against
  real `Rails.cache` state, never mock" rule for `item_catalog_cache_spec.rb`.
- **`.claude/styleguides/fetcher/internal-api-controllers.md`** (amended
  with a cross-reference to the new file above) — the source of the MUST
  NOT rule this plan deliberately avoids triggering (no
  `skip_before_action` opt-out on `Api::V1::` for the new public
  endpoint); also the response-shape conventions (`render json: { ... },
  status: :symbol`; `{ message: "..." }` error bodies; one-collaborator-
  per-action) that `public-api-controllers.md` explicitly carries over
  by reference rather than restating.
- **`.claude/styleguides/fetcher/architecture-layers.md`** — its own
  "When to Use" carve-out ("code that only reads already-persisted data
  for a response... a plain AR query with no parsing/building involved")
  is why this plan's filter/sort/paginate logic lives directly in
  `Api::Public::ItemsController#catalog` via `Item` scopes, not behind a
  new `app/services/` class — that layer's own qualifying criterion
  (needed identically by two or more Scenarios) doesn't apply here, this
  feature has exactly one caller.
- **`.claude/styleguides/rails-layering.md`** — the cross-app Controller
  → Model dependency direction the plan's new `Item` scopes
  (`by_categories`, `by_rarities`, `stattrak_only`, `matching_search`,
  `sorted_by`) follow, matching the existing `scope :marketable` /
  `scope :stale_or_unpriced` pattern rather than ad hoc `where` calls
  inlined in the controller.
- **`.claude/styleguides/fetcher/steam-response-objects.md`** — governs
  `InventoryData#item_attributes_by_name`'s new `category` extraction
  (defensive hash access, DTO owns reshaping its own raw Steam fields),
  identical in shape to the existing `rarity` extraction this plan
  mirrors.
- **`.claude/styleguides/ruby-sorbet.md`** — governs typing on every new
  and modified file: `sig`/`T.let`/`T.nilable`/`T::Boolean` on
  `Api::Public::ApplicationController`/`ItemsController`,
  `ItemCatalogCache`, the new `Item` scopes, and the `category:`
  additions to `InventoryData`/`ItemParser`.
- **`.claude/styleguides/rspec-conventions.md`** — governs test level
  and structure for every new/extended spec (`type: :request` under the
  new `spec/requests/api/public/`, unit specs under `spec/caching/`,
  `FactoryBot` over fixtures, `aggregate_failures`).
- **`.claude/styleguides/git-commits.md`** — governs commit message
  format once `implement-plan` lands this work.

# Development Plan

## Goal

Expose a new, unauthenticated `GET /api/public/items/catalog` endpoint in
`app_fetcher` that returns a paginated, filterable, sortable list of
marketable items (with price, 24h change, and a 7-day trend per item),
for a future `app_core` page open to both Steam-logged-in and anonymous
visitors. Backend only — the `app_core` page/React UI that will consume
this is a separate, later task.

This requires, as a prerequisite within this same task, capturing a
`category` field (e.g. "Rifles", "Knives") on `Item#metadata` — a field
the frontend contract requires for filtering/display that does not exist
anywhere in the ingestion pipeline today.

## Expected Behavior

- **Normal:** `GET /api/public/items/catalog` with no params returns page
  1 of up to 24 `Item.marketable` rows, sorted by `change_24h_desc`
  (default), with the exact response shape below. No `Authorization`
  header is required or checked — this is a genuinely public endpoint, by
  explicit design (see `.claude/styleguides/fetcher/internal-api-controllers.md`'s
  own carve-out: "a genuinely public endpoint is a decision to make and
  document explicitly").
- **Response shape:**
  ```json
  {
    "meta": {
      "page": 1, "per_page": 24, "total_count": 1284, "total_pages": 54,
      "gaining_count": 612, "losing_count": 401,
      "last_synced_at": "2026-10-11T14:22:00Z"
    },
    "items": [{
      "market_hash_name": "AK-47 | Redline (Field-Tested)",
      "metadata": {
        "weapon_type": "AK-47", "item_name": "Redline", "category": "Rifles",
        "condition": "Field-Tested", "stattrak": false,
        "icon_url": "https://...", "rarity": "Classified"
      },
      "current_price_cents": 4218, "change_24h_cents": 130, "change_24h_percent": 3.2,
      "trend_7d": [{ "at": "2026-10-05T00:00:00Z", "price_cents": 4050 }, ...]
    }]
  }
  ```
  `items[].metadata` is built explicitly from the 7 named keys above —
  never a raw dump of `item.metadata`, which also carries
  `marketable`/`tradable`/`souvenir` that aren't part of this contract.
  `trend_7d` entries carry only `at`/`price_cents` — `ItemTrendCache`'s
  `TrendPoint` also carries a `volume` field that is dropped when
  shaping this response.
- **Filtering (query params, all optional, combinable):**
  - `page` (int, default 1) — coerced via `.to_i`, clamped to a minimum
    of 1 (a garbage/negative/non-numeric value becomes 1, not an error).
  - `per_page` (int, default 24) — coerced the same way, clamped to
    `1..100` (a `per_page=5000` request silently gets capped at 100, not
    rejected — this app's only defense against one request returning the
    whole catalog, since rate-limiting is explicitly out of scope for
    this task).
  - `search` (string) — case-insensitive substring match against
    `metadata->>'item_name'` only (not `market_hash_name`,
    `weapon_type`, or `condition`). Empty/absent → no filter.
  - `category[]` (string array) — exact match against
    `metadata->>'category'`, ORed across the given values. An unknown
    category name simply matches nothing (no error) — this is an open
    string set, not a closed enum.
  - `rarity[]` (string array) — same shape as `category[]`, against
    `metadata->>'rarity'`.
  - `stattrak` (bool, `"true"`/absent-everything-else) — when `"true"`,
    only items with `metadata @> {"stattrak": true}`; any other value or
    absent means no filter (both StatTrak and non-StatTrak included).
  - `sort` (enum: `change_24h_desc` default | `price_desc` | `price_asc`
    | `name_asc`) — an unrecognized value renders `:bad_request` with
    `{ message: "Unsupported sort: <value>" }`, mirroring
    `ItemPricesController#history`'s existing `period` validation
    pattern exactly (this is a closed enum, unlike `category`/`rarity`).
    `name_asc` sorts by `metadata->>'item_name'`, not `market_hash_name`.
- **`meta.gaining_count`/`meta.losing_count`** are scoped to the
  currently-applied filters (how many of the *filtered* set have
  `change_24h_cents > 0` / `< 0`), not global catalog totals — per the
  user's explicit decision. Computed as conditional aggregates
  (`COUNT(*) FILTER (WHERE change_24h_cents > 0)`, et al.) over the same
  `WHERE` clause as the paginated rows, not a separate unfiltered query.
- **`meta.last_synced_at`** is `Item.marketable.maximum(:updated_at)` —
  the most recent update across all marketable items, not scoped to the
  current filters and not a new tracked concept (no new "last full sync"
  entity is introduced).
- **`items[].trend_7d`** reuses `ItemTrendCache.fetch_for(names)`
  (`app_fetcher/app/caching/item_trend_cache.rb`) bulk read-through,
  called with the current page's `market_hash_name`s once the page is
  determined — not reimplemented. An item with no trend data (brand new,
  no price logs yet) gets `trend_7d: []`, matching `ItemTrendCache`'s
  existing miss behavior.
- **Caching (two independent layers, see Implementation Approach for
  why both and why this isn't redundant):**
  - A new `app_fetcher/app/caching/item_catalog_cache.rb`
    (`ItemCatalogCache`) — the TTL-only variant from
    `.claude/styleguides/fetcher/caching.md` (first real implementation
    of it), caching the whole computed page result (items + meta) keyed
    by the normalized filter params. A repeat request with identical
    params within the TTL window hits no DB query at all.
  - HTTP conditional-GET headers (`stale?(etag:, public: true)`) so a
    response is cacheable by a browser or (once one exists) a CDN —
    inert today since this infra has no CDN/reverse-proxy (confirmed:
    no nginx/CDN service in `docker-compose.yml`), but free to add now
    and the only piece a future CDN needs.
- **Failure behavior:** malformed `page`/`per_page`/`stattrak`/
  `category[]`/`rarity[]` never raises or 400s — see the coercion/clamp
  rules above. Only an unrecognized `sort` value 400s. Any unhandled
  infra-level error (lost DB connection, etc.) needs its own
  `rescue_from StandardError` on the new namespace's base controller —
  see Files To Create; it cannot inherit `app_fetcher`'s existing
  `ApplicationController`, which also carries the bridge-token
  `before_action` this endpoint must not have.
- **Unchanged:** every existing `Api::V1::` endpoint, its bridge-token
  auth, and `ItemPriceCache`/`PriceHistoryCache`/`ItemTrendCache`'s
  existing behavior and invalidation (this task adds a sibling cache
  class, touches none of the three existing ones). `UserInventorySyncService`'s
  existing behavior for `marketable`/`tradable`/`rarity` is unchanged —
  this task only adds a fourth field (`category`) resolved the same way.

## Scope

### In Scope

- New `Api::Public::` namespace in `app_fetcher`: route, a namespace
  base controller (no bridge-token auth, but the same
  `rescue_from StandardError` error shape as `Api::V1::`), and
  `Api::Public::ItemsController#catalog`.
- New `ItemCatalogCache` (TTL-only caching variant), plus new `Item`
  query scopes for the filter/sort dimensions the controller composes.
- HTTP conditional-GET support (`stale?`, `public: true`) on the new
  action.
- Capturing `category` (from Steam's `"Type"`-category tag, already
  present in the raw inventory response and already discarded today)
  into `Item#metadata`, following the exact precedent of
  `.claude/plans/steam-marketability-rarity-metadata.md`
  (`InventoryData` → `ItemParser` → `Item.store_accessor` →
  `UserInventorySyncService`).
- Resetting the local `app_fetcher` dev DB once the `Item`/metadata
  shape is final (same precedent, same reasoning: nothing is deployed,
  so no backfill script is needed — confirmed explicitly by the user for
  this task, not silently inherited from the precedent).
- Tests for all of the above, at every touched layer.

### Out of Scope

- Any `app_core`/frontend/React change — a separate, later task. This
  plan produces a backend contract only.
- Rate limiting (per-IP or otherwise) on the new public endpoint —
  explicitly deferred by the user to a separate future task. Noted as a
  known gap, not silently worked around (the `per_page` clamp is a
  minimal, unrelated defense against one-request-returns-everything, not
  a substitute for real rate limiting).
- Standing up any CDN/reverse-proxy — purely infrastructural, done at
  deploy time per the user's explicit plan, with zero code changes
  needed beyond this task's HTTP cache headers.
- A real CDN smoke test — nothing to point one at yet.
- A DB migration/backfill script for `category` on pre-existing `Item`
  rows — moot given the dev DB reset (see In Scope).
- Any new DB index for `category`/`rarity`/`search` filtering — current
  data volume (~1,284 items per the frontend contract's own example) is
  small enough for a sequential scan; flagged in Risks as a known future
  scaling concern, not solved speculatively here.
- Capturing any other Steam tag category beyond `"Type"` (e.g.
  `Quality`, `ItemSet`, `StickerCapsule`) — not requested.
- Extracting a shared `Api::BaseController` between `Api::V1::
  ApplicationController` and the new public namespace's base controller
  — see Implementation Approach for why this plan duplicates the ~10
  shared lines instead.

## Implementation Approach

**Namespace and base controller.** `app_fetcher/config/routes.rb` gets a
new `namespace :api do; namespace :public do ... end; end` block,
sibling to the existing `namespace :v1 do`, mapping to
`app/controllers/api/public/`. `Api::V1::`'s existing
`ApplicationController` (`app_fetcher/app/controllers/application_controller.rb`)
applies `before_action :authenticate_bridge_token!` globally and cannot
be reused or inherited from for a genuinely public endpoint — per
`.claude/styleguides/fetcher/internal-api-controllers.md`'s own MUST
NOT rule, there is no "opt out per controller" mechanism, by design. A
new `Api::Public::ApplicationController < ActionController::API` is
added with its own `rescue_from StandardError` + the same
`render_internal_server_error` shape (`{ message: "Internal error" }` /
`:internal_server_error`, logged via `Rails.logger.error`) — duplicating
roughly ten lines rather than extracting a shared `Api::BaseController`
both namespaces inherit from. This plan takes that position
deliberately, not by default: the project has already stated a general
preference against extracting shared abstractions before there's enough
real repetition to show what the right shape is (see the base-service/
`Result`-class deferral for `app/services/`, held back until that layer
has more than its current two classes) — the same reasoning applies
here with only two controller namespaces. `styleguides-check` should
confirm or revisit this call, since it's the one piece of this plan that
touches `internal-api-controllers.md`'s documented structure.

**Where the catalog query logic lives.** `app_fetcher`'s
`architecture-layers.md` explicitly carves out "code that only reads
already-persisted data for a response ... a plain AR query with no
parsing/building involved" as not needing the parser/builder/worker
split, citing exactly this kind of read-only listing controller as the
precedent. Separately, the `app/services/` layer
(`.claude/adr/fetcher/cross-scenario-service-layer.md`) exists
specifically for logic needed identically by *two or more Scenarios* (a
controller and a worker, concretely) — this feature has exactly one
caller (one controller action), so introducing a service class here
would misuse that layer's own qualifying criterion, not satisfy it. The
filter/sort/paginate/count query therefore lives directly in
`Api::Public::ItemsController#catalog`, composed from new `Item` scopes
(mirroring `Item`'s existing `scope :marketable`), the same shape
`Api::V1::ItemPricesController#history` already uses for its own
multi-step, branching, single-Scenario query logic.

**Why both the new cache class and HTTP headers (not just one).** Three
independent layers, each solving a different problem, matching the
mental model the user already converged on earlier in this task's
design discussion: `ItemCatalogCache` (Solid Cache/Redis, origin-side)
protects this app's own DB from repeated identical work once a request
reaches Rails — the only thing that matters today, since no CDN exists
yet and rate-limiting is out of scope. `stale?`/`public: true` is the
HTTP contract with any downstream cache (browser today; CDN once one is
deployed) — cheap to add now, inert until something reads it. Neither
layer substitutes for the other: the origin cache protects the DB
regardless of whether a CDN ever exists; the HTTP headers do nothing
for the DB today but cost ten minutes and make the eventual CDN step
genuinely zero-code.

**Why `ItemCatalogCache` is a new, TTL-only class, not a reuse of
`ItemPriceCache`.** `ItemPriceCache.fetch_for` is a bulk lookup over an
*already-known* list of `market_hash_name`s — it answers "give me the
price of these specific items," not "which items are on page 2 of this
filtered, sorted view." The thing that needs caching here is the result
of the filter/sort/paginate/count query itself, keyed by the filter
params, not by item identity. `Item` already carries
`current_price_cents`/`change_24h_cents` as plain columns, so no
per-item price cache needs to be consulted at all for the base listing.
Per `.claude/styleguides/fetcher/caching.md`'s "When to Use", the
read-through + explicit-invalidation variants require a single,
codebase-controlled writer to call `.invalidate` the moment it writes —
there is no such single writer for "this specific filter/sort/page
combination," since any item's price update could affect any number of
cached pages across the full combinatorial filter space; invalidating
all of them on every price tick is impractical. TTL-only is the
documented variant for exactly this situation and currently has no real
implementation in the codebase — this is its first.

**`ItemCatalogCache`'s interface**, matching the TTL-only shape
(`.read(id)`/`.write(id, value)`, no `.invalidate`): the controller
normalizes the six filter/sort params into a plain hash (sorted arrays,
downcased strings), and `ItemCatalogCache` itself builds the versioned
key (`["items_catalog", CACHE_KEY_VERSION, Digest::SHA256.hexdigest(normalized_filters.to_json)]`),
matching every other class's `[<namespace>, <version>, id]` shape. TTL
is a class constant used internally by `.write`, not caller-supplied —
same shape as `SAFETY_NET_TTL` on the existing classes, just serving as
the *primary* freshness mechanism here rather than a safety net (per
caching.md's own distinction for this variant). Picked at 2 minutes,
reasoned fresh rather than copied from the other classes' 15-minute
safety-net value: short enough that the catalog doesn't look
meaningfully stale against the upstream hourly-at-most per-item price
refresh cadence, long enough to absorb a burst of concurrent anonymous
page loads — the actual threat profile for an unauthenticated,
not-yet-rate-limited endpoint.

On a cache miss, the controller computes the page directly: `Item.marketable`
chained through the new scopes, one query for the paginated rows and one
conditional-aggregate query for `total_count`/`gaining_count`/`losing_count`
(two query executions, not one — acceptable; `ItemPricesController#history`
already branches between two different query shapes depending on `period`
without being pushed into a service), then `ItemTrendCache.fetch_for`
for the page's trend data, assembles the final hash, and calls
`ItemCatalogCache.write`.

**Category capture.** Follows `.claude/plans/steam-marketability-rarity-metadata.md`'s
precedent exactly, extending the same combined method rather than adding
a parallel one: `InventoryData#item_attributes_by_name` gains a
`category` key (the `tags` entry where `category == "Type"`, via its
`localized_tag_name` — same lookup shape as the existing
`rarity_tag`/`RARITY_TAG_CATEGORY` helper, added as a sibling
`TYPE_TAG_CATEGORY` constant/helper, not a generalized "tag lookup by
category name" abstraction for just two call sites). `ItemParser.parse`
gains a `category:` keyword param (default `nil`, same shape as
`rarity:`), included in both branches' `metadata:` hash literals.
`Item`'s `store_accessor` list gains `:category`. `UserInventorySyncService`
passes `category:` into `ItemParser.parse` alongside the existing three
fields, from the same `item_attributes_by_name` lookup already resolved
there — no new lookup call.

## Files To Modify

- **`app_fetcher/config/routes.rb`** — add
  `namespace :api do; namespace :public do; get "items/catalog", to: "items#catalog"; end; end`,
  sibling to the existing `namespace :v1 do` block. Reason: explicit
  route declaration, matching this app's existing convention (no bare
  `resources`).
- **`app_fetcher/lib/steam/response/data/inventory_data.rb`** — add a
  `TYPE_TAG_CATEGORY = T.let("Type".freeze, String)` constant and a
  private `category_tag(desc)` helper (same shape as `rarity_tag`);
  `ItemAttributes` type alias gains `category: T.nilable(String)`;
  `item_attributes_by_name` includes `category: category_tag(desc)` in
  its returned hash. Reason: the DTO owns reshaping its own raw Steam
  fields (`steam-response-objects.md`); mirrors the existing `rarity`
  extraction exactly.
- **`app_fetcher/app/parsers/item_parser.rb`** — `ItemDto`'s `metadata`
  type alias gains `category: T.nilable(String)`; `.parse` gains a
  `category: nil` keyword param, included in both branches' `metadata:`
  hash literals. Reason: matches the established
  `marketable`/`tradable`/`rarity` precedent exactly — passed into
  `.parse` directly, not merged onto its result afterward.
- **`app_fetcher/app/models/item.rb`** — add `:category` to the existing
  `store_accessor :metadata, ...` line; add new scopes:
  `by_categories(categories)`, `by_rarities(rarities)`, `stattrak_only`,
  `matching_search(term)`, and a `sorted_by(sort)` class method/scope
  composing the four `sort` enum values (`change_24h_desc` default,
  `price_desc`, `price_asc`, `name_asc` via `metadata->>'item_name'`).
  Each scope is a no-op (returns `self`/unfiltered) when its argument is
  blank, so the controller can unconditionally chain all of them.
  Reason: filtering/sorting criteria belongs on the model as composable
  scopes, matching the existing `scope :marketable` /
  `scope :stale_or_unpriced` pattern — not ad hoc `where` calls inlined
  in the controller.
- **`app_fetcher/app/services/user_inventory_sync_service.rb`** —
  alongside the existing `marketable:`/`tradable:`/`rarity:` lookup and
  pass-through, add `category:` from the same
  `item_attributes_by_name` entry into the same `ItemParser.parse` call.
  Reason: this is already the one place combining resolved Steam-response
  data with parsed data before persisting; no new lookup, just one more
  field riding the existing one.
- **`app_fetcher/spec/lib/steam/response/data/inventory_data_spec.rb`**,
  **`app_fetcher/spec/parsers/item_parser_spec.rb`**,
  **`app_fetcher/spec/services/user_inventory_sync_service_spec.rb`**,
  **`app_fetcher/spec/requests/api/v1/inventories_spec.rb`** — extended
  with `category` cases, mirroring each file's existing
  `marketable`/`tradable`/`rarity` cases (see Test Plan).
- **`app_fetcher/spec/factories/items.rb`** — add `category` to the
  factory's `metadata` hash (or a trait), so new catalog-endpoint specs
  can build items with a known category without hand-writing
  `metadata:` literals everywhere.

## Files To Create

- **`app_fetcher/app/controllers/api/public/application_controller.rb`**
  — `Api::Public::ApplicationController < ActionController::API`, with
  `rescue_from StandardError, with: :render_internal_server_error` and
  the same private handler shape as `app_fetcher`'s top-level
  `ApplicationController` (log via `Rails.logger.error`, render
  `{ message: "Internal error" }` / `:internal_server_error`). No
  `before_action :authenticate_bridge_token!`. Reason: namespace-scoped
  base controller, the standard Rails shape for giving one namespace a
  different auth posture than another, without touching `Api::V1::`'s
  existing base at all.
- **`app_fetcher/app/controllers/api/public/items_controller.rb`** —
  `Api::Public::ItemsController < Api::Public::ApplicationController`,
  one action, `#catalog`: normalizes/clamps params, builds the
  `ItemCatalogCache` lookup, computes the page on a miss via the new
  `Item` scopes + `ItemTrendCache.fetch_for`, shapes the response
  (explicit `metadata`/`trend_7d` key lists, not raw dumps), calls
  `stale?(etag:, public: true)`, renders `json: { meta:, items: }`,
  `status: :ok` on success, `{ message: "Unsupported sort: ..." }` /
  `:bad_request` for an invalid `sort`. Reason: the endpoint's one
  collaborator-facing entry point.
- **`app_fetcher/app/caching/item_catalog_cache.rb`** —
  `ItemCatalogCache`, the TTL-only variant: `.read(normalized_filters)`
  / `.write(normalized_filters, value)`, versioned key
  (`["items_catalog", CACHE_KEY_VERSION, <digest>]`), class-level `TTL`
  constant (2 minutes). No `.invalidate` — see Implementation Approach
  for why this variant has none. Reason: first real TTL-only
  implementation of the variant `caching.md` already documents but has
  never had a concrete class for.
- **`app_fetcher/spec/requests/api/public/items_spec.rb`** — new
  request-spec file (new directory, `spec/requests/api/public/`,
  sibling to the existing `spec/requests/api/v1/`).
- **`app_fetcher/spec/caching/item_catalog_cache_spec.rb`** — new unit
  spec, sibling to the existing `spec/caching/*_cache_spec.rb` files.
- **`app_fetcher/spec/requests/api/public/` directory** — implied by
  the spec file above; no other files in it yet.

## Test Plan

- **`inventory_data_spec.rb`** (extend): a description with a `"Type"`-
  category tag resolves `category` in `item_attributes_by_name`'s
  output; a description with no such tag (or no `tags` key at all)
  resolves `category: nil`; a `tags` array where the `Type` tag isn't
  first still resolves correctly (guards position-assumption bugs, same
  style as the existing `rarity` tests).
- **`item_parser_spec.rb`** (extend): passing `category:` includes it
  unchanged in returned `metadata`; omitting it defaults to `nil`.
- **`user_inventory_sync_service_spec.rb`** (extend): a synced item with
  a `Type` tag persists `metadata["category"]` on the backfilled `Item`;
  one with no `Type` tag persists `nil`.
- **`inventories_spec.rb`** (extend): `GET /api/v1/inventories/me`'s
  JSON response passes `category` through end-to-end — proves no
  regression to the existing authenticated endpoint from this prep work.
- **`item_catalog_cache_spec.rb`** (new, unit, `spec/caching/`, no
  `type:` metadata, per `rspec-conventions.md`): `.write` then `.read`
  with the same normalized filters round-trips the cached value; two
  different normalized-filter hashes produce different cache entries
  (no collision); `.read` on a key never written returns `nil`; a
  written value expires after the TTL (time-travel via
  `travel_to`/`Timecop`-equivalent already used elsewhere in this suite,
  or a frozen-time assertion against `Rails.cache.exist?`) — asserted
  against real `Rails.cache` state, never a mock, per `caching.md`'s
  Testing section.
- **`items_spec.rb`** (new, request spec, `type: :request`,
  `spec/requests/api/public/`):
  - No `Authorization` header at all still returns `:success` (the
    defining behavior of this endpoint — the inverse of every
    `Api::V1::` spec's "without a bridge token → :unauthorized" case).
  - Default params (no query string): returns up to 24 marketable items,
    `meta.page == 1`, `meta.per_page == 24`, sorted by `change_24h_desc`.
  - `category[]`, `rarity[]`, `stattrak`, `search` each filter correctly,
    individually and combined.
  - `sort=price_desc`/`price_asc`/`name_asc` each order correctly;
    `sort=bogus` returns `:bad_request` with a `message`.
  - `page`/`per_page` edge cases: `page=0`, `page=-1`, non-numeric
    `page=abc` all behave as `page=1`; `per_page=9999` clamps to 100;
    requesting a page past `total_pages` returns an empty `items` array
    with correct `meta` (not an error).
  - A non-marketable `Item` (factory trait) never appears in results,
    regardless of filters.
  - `meta.gaining_count`/`losing_count` reflect the *filtered* set, not
    the full catalog (a dedicated scenario with a mix of filtered-in
    gaining/losing/flat items and filtered-out ones of each kind, per
    the user's explicit scoping decision).
  - `meta.last_synced_at` matches `Item.marketable.maximum(:updated_at)`.
  - `items[].trend_7d` matches what `ItemTrendCache.fetch_for` would
    return for that item, reshaped to `{at, price_cents}` only (no
    `volume` key leaking through).
  - `items[].metadata` contains exactly the 7 contracted keys — no
    `marketable`/`tradable`/`souvenir` leak.
  - A second identical request within the cache TTL hits no `Item`/
    `PriceLog` query (via `count_queries`, the existing
    `spec/support/sql_query_counter_helper.rb` helper) — proves
    `ItemCatalogCache` is actually consulted, not just written.
  - Response includes `ETag`/`Cache-Control: public` headers; a repeat
    request with a matching `If-None-Match` returns `:not_modified`.
  - An unhandled `StandardError` inside the action (stubbed the same way
    `fetcher-base-controller-rescue-from.md` stubbed
    `current_steam_id`) renders `{ message: "Internal error" }` /
    `:internal_server_error` — proves `Api::Public::ApplicationController`'s
    own `rescue_from` actually works, independent of `Api::V1::`'s.

## Implementation Steps

1. Extend `InventoryData`/`ItemParser`/`Item`/`UserInventorySyncService`
   for `category`, TDD (spec first at each layer), following
   `steam-marketability-rarity-metadata.md`'s precedent order: DTO →
   parser → model → service.
2. Extend `spec/factories/items.rb` with a `category` value.
3. Add the four new `Item` query scopes (`by_categories`, `by_rarities`,
   `stattrak_only`, `matching_search`) and the `sorted_by` sort
   composition, each with its own unit coverage (or covered indirectly
   through the request spec — decide per `rspec-conventions.md`'s
   existing model-spec conventions once writing this step).
4. Add `ItemCatalogCache` (TTL-only), TDD against real `Rails.cache`
   state.
5. Add the `Api::Public::` namespace: route, `Api::Public::
   ApplicationController`, `Api::Public::ItemsController#catalog`,
   wiring together steps 3–4. Write `items_spec.rb` scenario-by-scenario
   alongside the controller, TDD.
6. Reset the local `app_fetcher` dev DB (`db:drop db:create db:migrate`,
   then `db:schema:load:cache` per the known `cache_schema.rb` side
   effect documented in `steam-marketability-rarity-metadata.md`'s
   Verification notes) once the `Item`/metadata shape is final —
   confirm immediately before running, per that same precedent's own
   practice of re-confirming rather than silently inheriting approval.
7. Run the full `app_fetcher` suite plus `srb tc`/`rubocop`, diffed
   against the pre-change baseline the same way the two precedent plans
   did, to separate genuinely new issues from pre-existing ones already
   in `fix_me.md`.

## Verification

- `bundle exec rspec spec/lib/steam/response/data/inventory_data_spec.rb spec/parsers/item_parser_spec.rb spec/services/user_inventory_sync_service_spec.rb spec/requests/api/v1/inventories_spec.rb spec/caching/item_catalog_cache_spec.rb spec/requests/api/public/items_spec.rb`,
  then the full `app_fetcher` suite for regressions.
- `srb tc` — diff error count/list against the pre-change baseline
  (`git stash` the touched files, re-run, compare), same process as
  both precedent plans.
- `bin/rubocop` on every touched/created file.
- No `app_core`/browser verification — no frontend change in this
  task's scope; the request spec's end-to-end JSON/header assertions
  are the verification surface for this endpoint.

## Risks

- **No new DB index for `category`/`rarity` equality or `item_name`
  substring search.** At ~1,284 items (the frontend contract's own
  example `total_count`), a sequential scan with the existing GIN index
  on the whole `metadata` column is expected to be fine; this becomes a
  real concern only if the catalog grows substantially, and is
  deliberately not solved speculatively here.
- **`ItemCatalogCache`'s TTL (2 minutes) is a judgment call, not a
  measured one** — picked by reasoning about the upstream hourly price-
  refresh cadence and the anonymous-burst threat profile, not from a
  load test. Easy to retune (one constant) if it proves wrong in either
  direction once this is actually live.
- **Two query executions per cache miss** (paginated rows +
  conditional-aggregate counts), not one — judged acceptable (matches
  `ItemPricesController#history`'s existing two-query-paths-depending-
  on-period shape) rather than forced into a single query via a window
  function, which would meaningfully complicate the `Item` scopes for a
  marginal gain at this data volume.
- **Duplicating `rescue_from`/`render_internal_server_error` into a new
  `Api::Public::ApplicationController` instead of extracting a shared
  base** is this plan's one explicitly debatable call — flagged for
  `styleguides-check` to confirm or override, since it's the piece that
  most directly touches `internal-api-controllers.md`'s documented
  single-namespace shape.
- **`category` will be `nil` for any `Item` surviving past the dev DB
  reset without a fresh sync** — not a concern for this task (nothing is
  deployed, the reset happens as part of this same plan), but the same
  caveat `steam-marketability-rarity-metadata.md` already flagged for
  `marketable`/`tradable`/`rarity` now applies identically to a fourth
  field once real data accumulates post-deploy.
- **`fix_me.md`** already lists an unrelated pre-existing Sorbet issue
  in `item_prices_controller.rb` and an un-narrowed-`response.data`
  pattern in `user_inventory_sync_service.rb` (about to gain a fifth
  call site with `category`'s lookup riding the same
  `item_attributes_by_name` result) — neither is introduced or widened
  in a new way by this change beyond what the precedent plan already
  anticipated ("now four call sites" → "now effectively the same four,
  `category` adds no new lookup call").

## Assumptions

- Steam's raw inventory response's `tags` array uses `category: "Type"`
  consistently for the weapon/item-class tag across all item kinds this
  catalog will show (knives, gloves, cases, etc.), not just the weapon-
  skin/sticker samples `steam-marketability-rarity-metadata.md`
  originally observed — carried forward as the same class of assumption
  that plan already made for `"Rarity"`, not independently re-verified
  here against a wider live sample.
- A dev-DB reset is acceptable again for this task, on the same grounds
  already confirmed for the identical situation in
  `steam-marketability-rarity-metadata.md` — re-confirmed by the user
  earlier in this task's design discussion ("анологично с rarity просто
  чистим бд"), not assumed silently.
- `fresh_when`/`stale?`'s `public: true` option producing a genuinely
  CDN-shareable `Cache-Control` header (rather than needing additional
  configuration) is correct for a plain `ActionController::API` action
  with no session/cookie writes on this path — consistent with this
  endpoint having no `Set-Cookie` or per-user state to accidentally leak
  into a shared cache.

## Completion Criteria

- Desired behavior explicit (Expected Behavior).
- Scope explicit (Scope).
- Affected files/components identified (Files To Modify / Files To
  Create).
- Test strategy defined (Test Plan).
- Implementation steps ordered (Implementation Steps).
- Verification defined (Verification).
- Plan written to `.claude/plans/public-items-catalog-endpoint.md`.

---

# Implementation Summary

## Implemented

- **Category capture** (`app_fetcher/lib/steam/response/data/inventory_data.rb`,
  `app_fetcher/app/parsers/item_parser.rb`, `app_fetcher/app/models/item.rb`,
  `app_fetcher/app/services/user_inventory_sync_service.rb`): added
  `TYPE_TAG_CATEGORY`/`category_tag` to `InventoryData` (mirroring
  `RARITY_TAG_CATEGORY`/`rarity_tag`), a `category:` keyword param on
  `ItemParser.parse`, `:category` on `Item`'s `store_accessor`, and
  threaded `category:` through `UserInventorySyncService` from the same
  `item_attributes_by_name` lookup already resolved there — no new call
  site, exactly as planned.
- **`Item` query scopes** (`app_fetcher/app/models/item.rb`):
  `by_categories`, `by_rarities`, `stattrak_only`, `matching_search`,
  `sorted_by` — each a no-op when its argument is blank, composable by
  the controller.
- **`ItemCatalogCache`** (`app_fetcher/app/caching/item_catalog_cache.rb`):
  the TTL-only variant's first real implementation. `.read(normalized_filters)`
  / `.write(normalized_filters, value)`, versioned key
  `["items_catalog", 1, Digest::SHA256.hexdigest(...)]`, 2-minute TTL
  constant, no `.invalidate`.
- **`Api::Public::` namespace** (`app_fetcher/config/routes.rb`,
  `app_fetcher/app/controllers/api/public/application_controller.rb`,
  `app_fetcher/app/controllers/api/public/items_controller.rb`):
  `GET /api/public/items/catalog`, no bridge-token auth, its own
  independently-declared `rescue_from StandardError`. `#catalog`
  normalizes/clamps params, reads/writes `ItemCatalogCache`, computes the
  page via `Item` scopes + `ItemTrendCache.fetch_for` on a miss, shapes
  the response to the exact contracted keys, and uses `stale?(etag:,
  public: true)` for conditional-GET/CDN-ready headers.
- **Sorbet DSL RBI**: regenerated `app_fetcher/sorbet/rbi/dsl/item.rbi`
  via `bin/tapioca dsl Item` after adding the new scopes/store_accessor
  key — required for `srb tc` to recognize them on `Item`/`Item::PrivateRelation`.
- **Local `app_fetcher` dev DB reset** (`db:drop db:create db:migrate`,
  then `db:schema:load:cache` after restoring the known
  `cache_schema.rb` side effect via `git checkout`) — confirmed with the
  user immediately before running, per the plan's own flagged practice.

## Tests

- `spec/lib/steam/response/data/inventory_data_spec.rb` — extended all
  four existing `#item_attributes_by_name` contexts with `category`
  assertions, plus a new "Type tag not first" position-guard context.
- `spec/parsers/item_parser_spec.rb` — extended the
  marketable/tradable/rarity examples to cover `category:` pass-through
  and its `nil` default.
- `spec/models/item_spec.rb` — new `describe` blocks for `by_categories`,
  `by_rarities`, `stattrak_only`, `matching_search`, `sorted_by` (17 new
  examples).
- `spec/services/user_inventory_sync_service_spec.rb` — extended the
  marketable/tradable/rarity contexts to also assert `category`.
- `spec/requests/api/v1/inventories_spec.rb` — extended the cold-start
  unknown-item context to assert `category` passes through end-to-end.
- `spec/factories/items.rb` — added `category: "Rifles"` to the default
  factory metadata.
- `spec/caching/item_catalog_cache_spec.rb` — new unit spec: round-trip,
  no-collision-between-different-filters, miss-returns-nil, and TTL
  expiry (via `travel_to`), all against real `Rails.cache` state.
- `spec/requests/api/public/items_spec.rb` — new request spec, 24
  examples: no-auth-header success, default pagination/sort, metadata
  shape (exactly 7 keys, no leak), `trend_7d` reshaping, `category[]`/
  `rarity[]`/`stattrak`/`search` filtering (individually and combined),
  all four `sort` values plus invalid-sort rejection, `page`/`per_page`
  clamping edge cases, non-marketable exclusion, filter-scoped
  `gaining_count`/`losing_count`, `last_synced_at`, cache-hit query-count
  assertion, ETag/`Cache-Control: public`/304 conditional-GET, and the
  namespace's own independent `rescue_from`.

TDD was followed with explicit RED confirmation at each isolated layer
(`InventoryData`, `ItemParser`, `UserInventorySyncService`, `Item`
scopes, `ItemCatalogCache`) before implementing. The final integration
layer (`Api::Public::ItemsController#catalog` + its 24-scenario request
spec) was built as one coherent unit rather than interleaved
assertion-by-assertion, given how tightly the scenarios depend on the
same action — confirmed working end-to-end on the first full run against
real DB/cache state, with no vacuous assertions (see Deviations).

Commands executed:

- `docker compose run --rm app_fetcher bundle exec rspec <targeted files>`,
  then the full suite, repeated after each TDD step.
- `docker compose run --rm app_fetcher bundle exec srb tc` — baseline via
  `git stash -u` against unmodified `main`, then after.
- `docker compose run --rm app_fetcher bin/rubocop <16 touched/created files>`.
- `docker compose run --rm app_fetcher bin/tapioca dsl Item`.
- `docker compose run --rm app_fetcher bin/rails db:drop db:create db:migrate`,
  then `db:schema:load:cache` (after `git checkout -- app_fetcher/db/cache_schema.rb`).

## Verification

- **Full `app_fetcher` RSpec suite**: 194 examples, 1 failure
  (`spec/caching/user_inventory_cache_spec.rb:18`) — confirmed
  pre-existing and unrelated via the `git stash -u` baseline (identical
  failure on unmodified `main`); already a known, unresolved issue
  predating this change.
- **`srb tc`**: baseline (clean `main`, via `git stash -u`) = 91 errors.
  After this change = 93. Diffed line-by-line: the only differences are
  (a) `item_parser.rb`'s pre-existing `item_name`-nilable-shape error
  (`fix_me.md`-documented), shifted by 4 lines, not newly introduced;
  (b) two new "Unable to resolve constant `RSpec`" lines, one per new
  spec file — the same harmless, codebase-wide Sorbet/RSpec-DSL
  limitation every existing spec file already has, not a real type
  error. Zero new errors against actual production code. The two
  `Item`-DSL errors encountered mid-implementation
  (`by_categories`/`category` "does not exist") were resolved by
  regenerating `sorbet/rbi/dsl/item.rbi` via `bin/tapioca dsl Item`, not
  carried into the final diff.
- **`bin/rubocop`**: 16 files inspected, no offenses.
- **Manual/API-level**: no browser verification — no `app_core`/frontend
  change in this task's scope (confirmed via the request spec's
  end-to-end JSON/header assertions instead).
- **Dev DB reset**: `db:drop db:create db:migrate` run against
  `app_fetcher`'s development database, confirmed with the user
  immediately before running; `cache_schema.rb` side effect caught via
  `git status` and corrected via `git checkout` + `db:schema:load:cache`
  (same fix as the `steam-marketability-rarity-metadata.md` precedent).

## Deviations

- **`category[]`/`rarity[]` are NOT case-folded for the cache key,
  despite `caching.md`'s amended rule saying to "case-fold any string
  input."** These two filters are exact, case-sensitive matches against
  `metadata->>'category'`/`metadata->>'rarity'` per the plan's own
  Expected Behavior — case-folding them for the cache key while querying
  with the original case (or vice versa) would either break matching
  correctness or silently collide two *different* queries (e.g.
  `category=Rifles` matching real data vs. `category=rifles` matching
  nothing) into the same cache entry — a real cache-poisoning bug, not a
  cosmetic one. Only `search` is downcased (safe and correct, since its
  underlying match is already case-insensitive `ILIKE` regardless of
  input case — folding it only improves cache-hit-rate, never changes
  matching results). Array params (`category`/`rarity`) are still
  *sorted* for order-independence, per the rest of the amended rule.
  This narrows the general styleguide wording to the cases where
  case-folding is actually safe; worth a small follow-up note on
  `caching.md` if a future composite-key cache class hits the same
  question, but not re-opened as a full `update-styleguide` pass for a
  single clarifying sentence.
- **Sorbet DSL RBI regeneration (`bin/tapioca dsl Item`) was not called
  out explicitly in the plan's Files To Modify**, since the plan was
  written before hitting the two resulting `srb tc` errors. Added as a
  necessary companion step once discovered — not a scope change, just an
  implementation mechanic the plan's own precedent
  (`steam-marketability-rarity-metadata.md`) didn't need to repeat
  (it extended existing methods rather than adding new scopes/accessors
  from scratch).
- **`items[].metadata` includes `category` even for a pre-existing
  `Item` whose `category` is `nil`** (renders as `"category": null`) —
  not explicitly specified either way in the plan; judged consistent
  with every other nilable metadata field (`weapon_type`, `condition`,
  `rarity`) already rendering as `null` when absent, not omitted from
  the JSON object.

## Remaining Issues

- `spec/caching/user_inventory_cache_spec.rb:18` remains failing on
  `main`, pre-existing and unrelated — already a known open item from
  `steam-marketability-rarity-metadata.md`, still unresolved; out of
  scope for this task.
- No new DB index for `category`/`rarity` equality or `item_name`
  substring search, per the plan's own Risks — revisit if the catalog's
  data volume grows substantially.
- Rate limiting on `Api::Public::` remains unimplemented, explicitly
  deferred by the user to a separate future task.
- The `app_core` frontend/React page that will consume this endpoint is
  a separate, later task, as scoped.
