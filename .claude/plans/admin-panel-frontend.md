---
status: implemented
app: fetcher+core
goal: React admin panel frontend for Item/PriceLog/UserInventory/InventoryValueLog, plus the backend additions it needs (pagination, bulk/catalog cache actions, HTML-servable admin session/shell)
created: 2026-10-12
---

# Development Plan

## Goal

Build the AppCore Admin panel's frontend — a new React island in
`app_core` covering `Item`, `PriceLog`, `UserInventory`, and
`InventoryValueLog` — matching the attached design draft's layout and
interactions (sidebar nav, paginated tables, row actions, bulk selection,
inline create panel, expandable nested rows, per-row sparklines). This
requires three categories of prerequisite backend work the existing
`admin-panel-backend-foundation` plan explicitly deferred: real
pagination on the four `Api::Admin::` index endpoints, new bulk/catalog
cache-rebuild endpoints, and an HTML-servable admin login + panel shell
(today only JSON session endpoints exist — there is no page a browser can
actually load).

`AdminUser` and `User` management are explicitly out of scope (see Scope)
— no backend CRUD exists for either yet; per the user's decision, they're
a separate follow-up once that backend exists.

## Expected Behavior

**Normal behavior:**

- An admin visits `/admin/login`, enters email + password, and on success
  lands on `/admin` — the panel shell with topbar (wordmark, admin chip
  showing the logged-in email) and a sidenav grouped as "Каталог и цены"
  (Item, PriceLog) / "Инвентари" (UserInventory, InventoryValueLog).
- Clicking a sidenav link switches the active resource page without a
  full page reload; the URL hash reflects the active page
  (`#item`/`#price-log`/`#user-inventory`/`#inventory-value-log`) so a
  link to a specific resource is shareable/bookmarkable and the browser
  back/forward buttons move between resources, mirroring the design
  draft's own routing mechanism.
- Each resource page loads its first page of data from `app_fetcher`
  directly (bridge-token-authenticated `fetch`, no `app_core` proxy, per
  `architecture-layers.md`) and renders a table with:
  - **Item**: checkbox column, item cell (swatch + `market_hash_name` +
    optional "ST™" tag), category, price, 24h change (colored), row
    actions (edit icon — opens an inline edit form — and a "⋯" dropdown
    with "Обновить цену сейчас" / "Удалить"); toolbar has an
    always-enabled "Пересоздать кэш каталога" button and a
    selection-gated "Пересоздать кэш ▾" dropdown (All / ItemPriceCache /
    ItemTrendCache / PriceHistoryCache) enabled once ≥1 row is checked;
    an inline create panel (name field only, hint that the rest is
    fetched from Steam).
  - **PriceLog**: read-only columns (item, lowest, median, volume,
    recorded-at) plus a per-row delete action. No create/update UI (no
    such routes exist).
  - **UserInventory**: checkbox column, expand toggle, Steam ID, item
    count, total value, last-synced, row actions ("⟲ sync now" + delete);
    expanding a row shows a truncated sub-table of inventory items (name
    + added-at, "… ещё N" for overflow); toolbar has a selection-gated
    "Пересоздать кэш" button (single cache type, no submenu).
  - **InventoryValueLog**: read-only columns (Steam ID, date, value) plus
    a per-row delete action. (A per-row 30-day trend sparkline was
    originally built here — see the "discovered gap" section below and
    "Post-review refactor, round 3" — then removed: it was new analytics
    logic invented solely for this admin page, with no other consumer and
    no product requirement behind it, which doesn't belong in what's
    meant to be a thin management UI.)
  - Every table has real pagination (page buttons, page-size selector,
    "Показано X–Y из Z") backed by the new server-side pagination.
- Row actions, bulk actions, and the create panel call the
  corresponding `Api::Admin::` endpoint and refetch the current page on
  success; a failed request surfaces an inline error without losing the
  rest of the page's state.

**Edge cases:**

- An empty resource (zero rows) renders an empty-state row, not a blank
  table or a crash — no empty-state precedent exists yet in this
  codebase; this plan introduces the first one (simple "Нет записей" row
  spanning the table, matching the existing dark theme).
- A resource with exactly one page (`total_pages <= 1`) still renders the
  pagination bar's "Показано X–Y из Z" summary but disables/hides the
  page-number controls, matching the mockup's AdminUser page.
- Deleting the last row on a page beyond page 1 (so the page becomes
  empty) re-fetches with `page - 1` instead of showing an empty page the
  user has to manually navigate back from.
- Deselecting every checked row disables the bulk toolbar actions and
  clears the "Выбрано: N" count, exactly mirroring the mockup's
  `data-selection-root` behavior (ported to React state instead of
  vanilla DOM toggling).
- `bulk_warm_cache`/`warm_catalog_cache` silently skip ids that don't
  resolve to a record (matching `ItemPriceCache.fetch_for`'s own
  tolerance for unknown names) rather than failing the whole batch.

**Failure behavior:**

- Not logged in (no `session[:admin_user_id]`) and visiting any
  `/admin/*` HTML page → redirected to `/admin/login` (not a JSON 401 —
  see Implementation Approach for why `Admin::BaseController` needs a
  format-aware guard).
- Invalid login credentials → login page re-renders with an inline error,
  per-field values not retained for the password field.
- A bridge-token-authenticated `fetch` to `app_fetcher` that comes back
  `401` (expired bridge token, 8h TTL) → the panel shows a
  "session expired" message and a relogin link, rather than an
  unexplained blank page.
- `create`/`update` validation failures (e.g. blank/duplicate
  `market_hash_name`) render the existing `{ message: "..." }` inline in
  the create/edit panel, not a toast or alert.

**Behavior that must remain unchanged:**

- `Api::V1::*`/`Api::Public::*` and the existing dashboard island are
  untouched — this plan only adds new files/actions to
  `Api::Admin::*` and new React code under a new
  `app_core/app/frontend/admin-panel/` directory, sibling to
  `dashboard/`, not modifying it.
- `AdminUser`/`Admin::BridgeToken`/`Admin::SessionsController`'s existing
  JSON behavior for non-HTML callers is preserved (see Implementation
  Approach — the format-aware changes are additive, not a replacement).

## Scope

### In Scope

- **`app_fetcher`**: pagination on `Api::Admin::ItemsController#index`,
  `PriceLogsController#index`, `UserInventoriesController#index`,
  `InventoryValueLogsController#index`; a bulk `warm_cache` action for
  `Item` (multi-id + cache-target selector) and for `UserInventory`
  (multi-steam_id); a catalog-wide cache warm action for `Item`; a new
  **flat, unscoped `GET /api/admin/price_logs`** index (discovered gap,
  see Implementation Approach's "PriceLog: flat global index" section) —
  the existing nested `GET /api/admin/items/:item_id/price_logs` stays
  exactly as-is, unmodified, for any caller that wants one item's logs;
  a second discovered gap for `UserInventory` (see Implementation
  Approach's "UserInventory: value field + expandable item list"
  section) — `total_value_cents` added to both `index`/`show` (reusing
  the latest `InventoryValueLog` snapshot per steam_id, batched via
  `DISTINCT ON` for the index to avoid N+1), and an `items` array
  (`market_hash_name` + `added_at`) added to `show` only.
- **`app_core`**: an HTML-servable admin login page and panel shell
  (controller + views + routes), a format-aware `Admin::BaseController`
  guard, a new Vite entry + React island (`admin-panel/`) covering Item,
  PriceLog, UserInventory, InventoryValueLog.
- Full RSpec coverage (backend) and Vitest/RTL coverage (frontend) for
  everything new.

### Out of Scope

- `AdminUser`/`User` management screens — no backend CRUD exists for
  either; a separate follow-up plan once that backend lands.
- Sorting/filtering/search on any admin table — the mockup doesn't show
  any (unlike the public catalog), only pagination; not adding filter UI
  or backend filter params speculatively.
- Any change to `Item`'s inline **edit** form fields beyond what
  `Api::Admin::ItemsController#update` already accepts — no new editable
  fields, no image upload, no rich metadata editor.
- Audit logging of admin actions (`current_admin_id` stays unused beyond
  the existing auth check, per `admin-api-controllers.md`'s explicit
  "no per-admin partitioning" note).
- Granular per-admin permissions/roles — unchanged single flat
  `AdminUser` role.
- Real-time updates (websockets/ActionCable/polling) — a table reflects
  the state as of its last fetch/refetch; no live-updating rows.
- Mobile-responsive layout for the admin panel (the mockup includes a
  `@media (max-width: 880px)` collapse, but this is an internal ops tool;
  not a priority — can be revisited later if actually needed).
- A design system/component library shared with the public dashboard —
  the admin panel gets its own CSS file with its own class names, reusing
  only the font assets and color-token philosophy, not literal shared
  components (see Risks).

## Implementation Approach

### Backend: pagination (lighter than the public catalog's query-objects layer)

The public catalog endpoints (`ItemCatalogQuery`/`ItemCatalogSerializer`)
pair pagination with sorting, filtering, caching, and derived price
stats — machinery this admin use case doesn't need, since none of the
four admin tables have sort/filter UI in the mockup. Building the full
`list-query-objects.md` stack (a `*CatalogQuery`, `*CatalogSerializer`,
`T::Enum` sort/filter options, an `Appliers::FilterApplier` pass) for a
plain `Model.order(...).limit(...).offset(...)` would be speculative
machinery for a requirement that doesn't exist yet. Instead, reuse only
`Appliers::Pagination` (already explicitly generic/resource-agnostic)
directly inside each admin controller's `index` action — the smallest
change that gets real `page`/`per_page`/`total_count`/`total_pages`
without inventing unused sort/filter scaffolding. `styleguides-check`
needs to confirm this reading of `list-query-objects.md`'s scope (see
Risks) since nothing currently states explicitly that simple pagination
without sort/filter may skip that layer.

Each index gets an explicit default order (none existed before, since
`.all`/`.where` has no guaranteed order and pagination without one is
unstable across pages):

- `Item#index`: `Item.order(id: :asc)`.
- `PriceLogsController#index`: `item.price_logs.order(created_at: :desc)`
  (newest first, matching the mockup).
- `UserInventoriesController#index`: `UserInventory.order(updated_at: :desc)`
  (most-recently-synced first, matching the mockup).
- `InventoryValueLogsController#index`:
  `InventoryValueLog.where(...).order(log_date: :desc)`.

Response envelope matches the public endpoints' shape minus the
catalog-specific stats:
`{ meta: { page, per_page, total_count, total_pages }, <key>: [...] }`.

### PriceLog: flat global index (discovered gap, added mid-implementation)

The mockup's PriceLog admin page is a **flat, cross-item** table —
rows from many different items interleaved in one globally-paginated
list ("Показано 1–25 из 48 912"), with an "Item" column naming which
item each row belongs to. `Api::Admin::PriceLogsController#index` only
ever supported the nested shape (`/api/admin/items/:item_id/price_logs`,
requiring `item_id`) — there is no endpoint that lists `PriceLog` rows
across all items. This was missed during planning (the original plan
only added pagination to the existing nested action) and surfaced once
the frontend page was actually being built against the real contract.

Resolution (user-approved): add a second, top-level, unnested route and
action, leaving the existing nested one completely unchanged for any
caller that wants one item's logs:

```ruby
get "price_logs", to: "price_logs#global_index"  # top-level, explicit — not `resources`,
                                                   # since this listing has no addressable
                                                   # single record of its own (same reasoning
                                                   # admin-api-crud-routing.md already uses to
                                                   # reserve `resources` for genuine CRUD)

resources :items, only: %i[index show create update destroy] do
  # ... unchanged ...
  resources :price_logs, only: %i[index destroy]  # nested, unchanged
end
```

`Api::Admin::PriceLogsController` gains a second action, not a branch
inside the existing one — Rails routes `GET /api/admin/price_logs` to
`#global_index` and `GET /api/admin/items/:item_id/price_logs` to the
existing `#index`, unchanged. Given one controller now serves two
genuinely different queries (one scoped, one global), the cleanest shape
is two distinct actions rather than one action with conditional scoping
logic:

- `#index` (nested route, unchanged): `item.price_logs.order(created_at: :desc)...`
- `#global_index` (new top-level route): `PriceLog.includes(:item).order(created_at: :desc).limit(...).offset(...)`,
  `.includes(:item)` specifically to avoid N+1 when rendering each row's
  item name — this is the one place in `Api::Admin::` that needs an
  association preload, since every other admin list renders fields from
  its own single table.

Response shape mirrors the other three index actions: `{ meta: {...},
price_logs: [...] }`, with each row's JSON gaining a `market_hash_name`
field (via the preloaded `item`) that the nested shape's response never
needed (callers already know which item they asked for).

### UserInventory: value field + expandable item list (discovered gap, added mid-implementation)

Two more fields the mockup's `UserInventory` page needs don't exist in
`user_inventory_json` at all: a per-row value ("Стоимость") and, on
expand, the actual list of items in that inventory (name + added date).
Both were missed for the same reason as the `PriceLog` gap — the original
plan only added pagination/bulk-cache to this controller, not new fields.

**Value** (user-approved resolution): reuse the latest
`InventoryValueLog` snapshot per `steam_id` — no new aggregation, no live
price summing. Requires a `UserInventory` ↔ `InventoryValueLog`
association (currently linked only by a loose `steam_id` string, no AR
association either direction):

```ruby
# app/models/user_inventory.rb
has_many :inventory_value_logs, foreign_key: :steam_id, primary_key: :steam_id
```

- `show` (single record): `user_inventory.inventory_value_logs.order(log_date: :desc).first&.total_value_cents`.
- `index` (many records per page): the same per-row lookup done 25+ times
  would N+1; batch it with a single `DISTINCT ON` query (Postgres-specific,
  already the project's DB) keyed by `steam_id`, then look up each row's
  value from that batch result — the same "avoid N+1 across a paginated
  admin list" concern `PriceLogsController#global_index`'s `.includes`
  already established, just a different technique since this is
  "latest-per-group," not a simple preload:
  ```ruby
  latest_values = InventoryValueLog
    .where(steam_id: user_inventories.map(&:steam_id))
    .select("DISTINCT ON (steam_id) *")
    .order(:steam_id, log_date: :desc)
    .index_by(&:steam_id)
  ```
  A `steam_id` with no `InventoryValueLog` row yet (never synced) gets
  `total_value_cents: nil` — not a `0`, and not an error; the frontend
  renders `nil` the same way it already renders any other absent price
  (`fmtPrice`'s existing em-dash fallback, no new UI case needed).

**Item list** (user-approved resolution): extend `show`'s response only
(not `index` — sending every user's full item list on every list page
would be wasteful; the mockup itself only reveals this on a per-row
expand, a separate request):

```ruby
user_inventory.user_inventory_items.includes(:item).order(created_at: :desc).map do |uii|
  { market_hash_name: uii.item.market_hash_name, added_at: uii.created_at.iso8601 }
end
```

`show`'s JSON becomes `{ steam_id, items_count, total_value_cents,
created_at, updated_at, items: [...] }`; `index`'s stays `{ steam_id,
items_count, total_value_cents, created_at, updated_at }` (no `items`
key at all, not an empty array — the frontend's expand action always
fetches `show` for the full detail, per Frontend section below).

### Backend: bulk & catalog-wide cache actions

No bulk-action precedent exists anywhere in this codebase — this plan
establishes the first one, as explicit new routes rather than overloading
the existing member routes:

```ruby
resources :items, only: %i[index show create update destroy] do
  collection do
    post :bulk_warm_cache
    post :warm_catalog_cache
  end
  member do
    post :refresh_price
    post :warm_cache
  end
  resources :price_logs, only: %i[index destroy]
end

resources :user_inventories, only: %i[index show destroy], param: :steam_id do
  collection do
    post :bulk_warm_cache
  end
  member do
    post :sync
    post :warm_cache
  end
  resources :inventory_value_logs, only: %i[index destroy]
end
```

`Api::Admin::ItemsController#bulk_warm_cache`: body
`{ item_ids: [...], cache_target: "all" | "item_price" | "item_trend" | "price_history" }`.
Looks up `Item.where(id: item_ids)`, collects `market_hash_name`s, and
calls the matching `fetch_for` method(s) in bulk (never a per-item loop —
`fetch_for` already accepts an array, so this is a direct, idiomatic
extension of the existing single-item `warm_cache` action, not new
caching logic). `cache_target` is a closed set — define
`Options::CacheTarget` as a small `T::Enum`
(`All`/`ItemPrice`/`ItemTrend`/`PriceHistory`), consistent with
`ruby-sorbet.md`'s guidance for closed-set string tags, without pulling
in `list-query-objects.md`'s `FilterApplier`/catalog-specific option
classes (this isn't a catalog filter). Response:
`{ warmed_item_ids: [...], message: "Cache warmed for N item(s)" }`.

`Api::Admin::UserInventoriesController#bulk_warm_cache`: body
`{ steam_ids: [...] }`. `UserInventoryCache` is the single-key variant
(no bulk `fetch_for` equivalent exists, per `caching.md`), so this loops
`UserInventoryCache.fetch(steam_id)` per id — this is the one place a
per-id loop is correct, not a violation of the bulk-variant MUST rule,
since `UserInventoryCache` was never that variant. Response:
`{ warmed_steam_ids: [...], message: "Cache warmed for N inventory(ies)" }`.

**No new `.invalidate` caller is introduced anywhere** — both bulk
actions call only `.fetch_for`/`.fetch` (read-through warm, "populate if
missing"), exactly mirroring the already-accepted single-item `warm_cache`
semantics from the backend-foundation plan. `caching.md`'s MUST rule
("only the writer named in Dependencies calls `.invalidate`") is
unaffected because no invalidation is added. This means, same as the
existing single-item action, a bulk "rebuild" on an already-warm cache is
a no-op, not a forced refresh — the mockup's Russian copy ("Пересоздать
кэш", literally "recreate cache") is kept as-is for UI consistency with
the design draft, but the actual effect is "ensure warm," matching
existing precedent rather than the literal translation. Flagged in Risks.

**`warm_catalog_cache`** (Item collection route, no body): `ItemCatalogCache`
is TTL-only, keyed by a hash of arbitrary filter/sort/pagination params —
there is no enumerable "every combination" to rebuild, and `caching.md`
explicitly prohibits bulk/wildcard cache deletes. Rather than inventing a
new unbounded-rebuild mechanism (out of proportion for this task, and
nothing else in this codebase pre-warms an unbounded key space either —
every other warm action targets a bounded, specific, known set of keys),
this action pre-warms the single highest-traffic cache entry: the
unfiltered, default-sorted, first page — by literally reusing the public
catalog's own pipeline (`ItemCatalogQuery.call` with the controller's own
near-empty `params` + `ItemCatalogSerializer.call`), then
`ItemCatalogCache.write` with those same default params. This is a
genuine "write" call (not `.invalidate` — `ItemCatalogCache` doesn't even
expose one), so it introduces no new restricted caller. Response:
`{ message: "Catalog cache warmed" }`.

### InventoryValueLog: flat global index + per-row trend (discovered gap, added mid-implementation)

Same root cause as the `PriceLog` gap: `Api::Admin::InventoryValueLogsController#index`
is nested under one `steam_id`
(`/api/admin/user_inventories/:user_inventory_steam_id/inventory_value_logs`)
and never returns `steam_id` in its row JSON (the caller already knows
it). The mockup's page is a flat, cross-user table — rows from many
different steam_ids, globally paginated — the identical shape `PriceLog`
needed. User-approved resolution: the identical fix, same pattern,
same reasoning:

```ruby
get "inventory_value_logs", to: "inventory_value_logs#global_index"  # top-level, explicit
```

`#global_index`: `InventoryValueLog.order(log_date: :desc).limit(...).offset(...)`,
each row gaining a `steam_id` field the nested variant's rows don't need.
No `.includes`/association preload here (unlike `PriceLog`'s
`market_hash_name`) — `steam_id` is already a plain column on
`InventoryValueLog` itself, not a field reached through an association.

**Per-row 30-day trend sparkline** (user-approved resolution): batch-
downsample per steam_id, reusing `ItemTrendCache#downsample`'s existing
algorithm (`app_fetcher/app/caching/item_trend_cache.rb`) adapted to this
resource's own fields (`log_date`/`total_value_cents` in place of
`created_at`/`lowest_price_cents`; no `volume` field to carry). One bulk
query per page, not one per row:

```ruby
logs_by_steam_id = InventoryValueLog
  .where(steam_id: page_steam_ids, log_date: 30.days.ago..)
  .order(:steam_id, :log_date)
  .group_by(&:steam_id)
trends = logs_by_steam_id.transform_values { |logs| downsample(logs) }
```

This is **not** a new `app/caching/` class — `caching.md`'s three
variants exist for data read repeatedly by many different callers
needing explicit invalidation; this is a single admin list's own
response-shaping concern, computed fresh per request, with no cache
layer of its own (the same "plain controller logic, no new cache
variant" posture every other admin index already has). The downsample
method is a private controller method, not extracted to a shared
location — `ItemTrendCache`'s own version stays exactly as it is,
unmodified; this is a second, independent implementation of the same
downsampling idea applied to different source data, not a shared
dependency between the two. If a third resource ever needs the same
windowed-downsample shape, extracting a common `Appliers::`-style helper
at that point would be the natural next step — not pre-emptively from
two.

### Delete routes for flat/global list pages (discovered gap, added mid-implementation)

`PriceLogsPage`/`InventoryValueLogsPage` were both built calling a flat
`DELETE /api/admin/price_logs/:id` / `DELETE /api/admin/inventory_value_logs/:id`
— mirroring the flat `GET` route each page's list reads from. Neither
flat `DELETE` route actually exists: `destroy` for both resources is only
ever routed nested (`/items/:item_id/price_logs/:id`,
`/user_inventories/:steam_id/inventory_value_logs/:id`), and the flat
routes added for the two gaps above were explicitly `GET`-only
(`global_index`). This was missed because Vitest mocks `fetch` entirely —
a test asserting "the delete call targets this URL" never validates that
URL resolves to a real Rails route — and surfaced only during Step 11's
live manual browser verification (`DELETE .../inventory_value_logs/1` →
real `404`).

Resolution (user-approved: switch the frontend to the real nested
route, not add a new flat `destroy` action):

- `PriceLogsController#global_price_log_json` gains `item_id` alongside
  the existing `market_hash_name` — the same category of addition already
  established above ("an extra field the nested variant's rows don't
  need"), no new styleguide text required for the backend side.
  `InventoryValueLog`'s flat rows already carry `steam_id`, which *is*
  that resource's nested parent key — no backend change needed there.
- `PriceLogsPage.jsx`'s delete handler calls
  `DELETE /api/admin/items/${log.item_id}/price_logs/${log.id}`;
  `InventoryValueLogsPage.jsx`'s calls
  `DELETE /api/admin/user_inventories/${log.steam_id}/inventory_value_logs/${log.id}`.
  Both existing nested `#destroy` actions are otherwise untouched.
- `react-dashboard.md` gained a new "Mutations Against Nested Backend
  Routes" rule (this was a genuinely new, previously-undocumented
  convention, not an instance of an existing one) generalizing this fix:
  a flat-list page's row mutation must target the real nested route using
  a parent key carried in that row's own JSON, never assume a flat
  mutation route mirrors a flat read route.

### Backend: making the admin stack HTML-servable

Today `Admin::SessionsController`/`Admin::BaseController` are JSON-only —
there is no page a human admin can actually open in a browser (the
backend-foundation plan's own Assumptions flagged this: "may need
revisiting once the UI task defines the real login flow"). This plan
defines it:

- `Admin::SessionsController#new` (new action): renders a plain HTML
  login form (`email`, `password`, submits to `admin_session_path`).
- `Admin::SessionsController#create`: becomes format-aware.
  `respond_to do |format|` — `format.json` keeps today's exact behavior
  (head/JSON, unchanged, so any existing JSON caller is unaffected);
  `format.html` redirects to the admin panel root on success, re-renders
  `new` with a flash error on failure. Same split for `#destroy`
  (`format.html` redirects to `admin_login_path`).
- `Admin::BaseController#require_admin!` becomes format-aware: an
  unauthenticated JSON request keeps today's `401 { message: "Unauthorized" }`
  (used by nothing today, but preserved for parity with
  `admin-authentication.md`'s existing documented behavior); an
  unauthenticated HTML request redirects to `admin_login_path` instead.
  This is the one behavior change to already-shipped code this plan
  makes, and it's additive (format-conditional), not a removal.
- `Admin::PanelController#show` (new controller): the single HTML view
  that hosts the React island, gated by `Admin::BaseController`. Mirrors
  `DashboardsController#show`'s pattern exactly — mints an
  `Admin::BridgeToken.encode(current_admin_user.id)`, passes it plus
  `APP_FETCHER_PUBLIC_URL` to the view as data attributes on the mount
  node.
- Routes: `namespace :admin do resource :session, only: %i[new create destroy]; get "/", to: "panel#show", as: :panel end`
  (root of `/admin` is the panel; `/admin/session/new` is the login
  form — `admin_login_path` reads better as a named alias for
  `new_admin_session_path`, add it if friction shows up during
  implementation, not pre-emptively).

`admin-authentication.md` will need updating (via `styleguides-check`) to
document the format-aware behavior — today it only describes JSON
responses.

### Frontend: navigation mechanism

Unlike the dashboard (a single mounted page), the mockup is a
**multi-resource** admin UI with sidebar nav across 4 resource pages.
Three options were weighed:

1. **Hash-based routing within one island** (chosen): one Rails route,
   one Vite entry, one mounted React root; `location.hash` (`#item`,
   `#price-log`, ...) drives which resource page renders, exactly
   mirroring the design draft's own mechanism. Introduces **no new
   router library** — preserves the existing "no client-side router"
   precedent (`react-router` is not added), just a small
   `useHashRoute()` hook (~15 lines) translating the mockup's vanilla-JS
   hash listener into a React hook. Deep-linkable/bookmarkable
   (`/admin#price-log`), survives browser back/forward, and keeps
   toolbar/selection state intact across the island's lifetime (a plain
   page reload between resources would lose it).
2. Four separate Vite entries + four real Rails routes/controllers/views
   — rejected: four new routes/controllers/views for what the mockup
   treats as one coherent app, a full page reload (and full
   re-auth/re-render of the shared shell) on every resource switch, and
   duplicated bridge-token/layout wiring four times over.
3. Single island, no hash, pure internal React state (like
   `Dashboard.jsx`'s single-page `mode` state) — rejected: no
   deep-linking/bookmarking, a real practical loss for an ops tool where
   admins routinely link a specific resource view when reporting
   something.

This generalizes `react-dashboard.md`'s "no router" precedent rather than
contradicting it — flagged for `styleguides-check` to make explicit,
since that file was written with only a single mounted page in mind.

### Frontend: structure

```text
app_core/app/frontend/admin-panel/
  AdminPanel.jsx              — root: owns useHashRoute(), renders topbar
                                + sidenav + the active resource page
  useHashRoute.js             — tiny hook: reads/writes location.hash,
                                re-renders on 'hashchange'
  adminApi.js                 — thin fetch wrapper (bridge-token header,
                                JSON body/parse, shared error shape) —
                                used by every page's hooks/handlers; the
                                one place that knows the fetcher base URL
                                and auth header, avoiding 4x duplicated
                                boilerplate across resource pages
  pages/
    ItemsPage.jsx              — owns its own useReducer (table/pagination/
                                 selection/create-panel/row-menu state),
                                 per react-dashboard.md's "one reducer per
                                 page" convention — generalized here to
                                 mean "one reducer per resource page
                                 within the admin island," not literally
                                 one for the whole multi-page panel
    itemsReducer.js
    PriceLogsPage.jsx
    priceLogsReducer.js
    UserInventoriesPage.jsx
    userInventoriesReducer.js
    InventoryValueLogsPage.jsx
    inventoryValueLogsReducer.js
  hooks/
    useAdminList.js            — one shared data-loading hook parametrized
                                 by resource path + page/per_page, used by
                                 all four pages (the fetch/pagination
                                 shape is identical across all four
                                 resources — this is the "4x duplication"
                                 case `react-dashboard.md`'s "pure
                                 derivation in utils/" principle extends
                                 to hooks)
  components/
    Table.jsx, Pagination.jsx, BulkToolbar.jsx, RowActionsMenu.jsx,
    CreatePanel.jsx, ExpandableRow.jsx, Sparkline.jsx, Swatch.jsx
  utils/
    format.js                  — cents→currency, date formatting (mirrors
                                 dashboard's own format.js conventions;
                                 not shared/imported across islands, since
                                 react-dashboard.md's structure keeps
                                 dashboard/ self-contained — duplicating
                                 this one small file is cheaper than
                                 introducing a shared frontend/ package
                                 boundary for a handful of formatters)
  styles/
    admin-panel.css             — plain CSS + variables, mockup's dark
                                 palette/tokens, reusing the existing
                                 font files already in
                                 dashboard/fonts/ (no new font assets)
  __tests__/
    (flat, mirroring dashboard/__tests__/ structure)
```

- `Sparkline.jsx`: hand-rolled inline SVG per `sparkline-vs-recharts.md`
  (repeated per-row, no axes/tooltip) — not Recharts, not a new instance
  of the dashboard's own `Sparkline.jsx` (different data shape: value log
  points vs. price points), but the same pattern/reasoning.
- `useAdminList.js` returns `{ data, meta, status, error, refetch }`,
  reusing `react-dashboard.md`'s `status: 'loading'|'success'|'error'`
  convention; no retry-schedule complexity (unlike
  `useItemPrices`/`useItemTrend`, which retry because they're racing a
  Steam-backed cache warm) — these are plain DB-backed reads with no
  comparable staleness window.
- Mutations (create/update/delete/refresh_price/sync/warm_cache/bulk
  actions) go through `adminApi.js`'s thin wrappers, called from each
  page's event handlers, which then call the page's own `refetch()` —
  no optimistic updates, no client-side cache invalidation layer.

### Frontend: mounting & auth

Identical pattern to `DashboardsController`/`dashboard.jsx`: the Vite
entry (`entrypoints/admin-panel.jsx`) finds `#admin-panel-root`, reads
`data-bridge-token`/`data-fetcher-url`, calls
`createRoot(...).render(<AdminPanel .../>)`. No Stimulus controller, no
`app_core` proxy — every `fetch` in `adminApi.js` goes straight to
`APP_FETCHER_PUBLIC_URL`, per `architecture-layers.md`.

### Styling

Plain CSS + CSS custom properties (no Tailwind/CSS-in-JS/component
library), matching `react-dashboard.md`'s existing convention and the
design draft's own token set (`--bg:#0c111b`, `--surface:#141a28`,
`--accent:#8368ff`, `--up:#3fb878`, `--down:#f0546b`,
`--stattrak:#e07b39`, `Big Shoulders Display`/`IBM Plex Sans`/`IBM Plex
Mono`). A separate `admin-panel.css` rather than extending
`dashboard.css` — the two islands are mounted on different pages and
never rendered together, and the admin panel's dark theme differs
enough from the dashboard's own light-leaning palette (confirm by
inspecting `dashboard.css`'s `:root` during implementation) that forcing
one shared stylesheet would mean heavy conditional overrides rather than
reuse.

## Files To Modify

**`app_fetcher`:**

- `app_fetcher/config/routes.rb` — add `collection` blocks
  (`bulk_warm_cache`, `warm_catalog_cache` for items;
  `bulk_warm_cache` for user_inventories); add two new top-level explicit
  routes, `get "price_logs", to: "price_logs#global_index"` and `get
  "inventory_value_logs", to: "inventory_value_logs#global_index"`,
  siblings to `resources :items`/`resources :user_inventories` (the
  nested `price_logs`/`inventory_value_logs` routes under `items`/
  `user_inventories` stay unchanged).
- `app_fetcher/app/controllers/api/admin/items_controller.rb` — add
  pagination to `index` (`Appliers::Pagination`, explicit `order`), add
  `bulk_warm_cache`/`warm_catalog_cache` actions.
- `app_fetcher/app/controllers/api/admin/price_logs_controller.rb` — add
  pagination to the existing nested `index`; add a new `global_index`
  action (`PriceLog.includes(:item)...`) for the new top-level route.
- `app_fetcher/app/controllers/api/admin/user_inventories_controller.rb`
  — add pagination to `index`, add `bulk_warm_cache` action, add
  `total_value_cents` to both `index`/`show` (batched `DISTINCT ON` for
  `index`, single lookup for `show`), add an `items` array to `show`
  only.
- `app_fetcher/app/models/user_inventory.rb` — add `has_many
  :inventory_value_logs, foreign_key: :steam_id, primary_key: :steam_id`.
- `app_fetcher/app/controllers/api/admin/inventory_value_logs_controller.rb`
  — add pagination to the existing nested `index`; add a new
  `global_index` action (`steam_id` field + batched 30-day trend
  downsample) for the new top-level route.

**`app_core`:**

- `app_core/config/routes.rb` — expand the `namespace :admin` block
  (`resource :session, only: %i[new create destroy]`, `get "/" => "panel#show"`).
- `app_core/app/controllers/admin/sessions_controller.rb` — add `#new`,
  make `#create`/`#destroy` format-aware (`respond_to`).
- `app_core/app/controllers/admin/base_controller.rb` —
  `require_admin!` becomes format-aware (redirect for HTML, unchanged
  JSON for JSON).
- `app_core/vite.config.ts` — no structural change expected (entries
  auto-detected); add the admin-panel test setup file to
  `test.setupFiles` if it isn't just reusing the dashboard's.
- `app_core/package.json` — no new dependencies expected (React/Vite
  already present; no router/chart-library addition).

## Files To Create

**`app_fetcher`:**

- `app_fetcher/app/queries/options/cache_target.rb` — `Options::CacheTarget`
  `T::Enum` (`All`/`ItemPrice`/`ItemTrend`/`PriceHistory`).
- `app_fetcher/spec/requests/api/admin/items_spec.rb`,
  `user_inventories_spec.rb` — extend with pagination +
  `bulk_warm_cache`/`warm_catalog_cache` examples (existing files, listed
  here for the new coverage, not new files).
- `app_fetcher/spec/requests/api/admin/price_logs_spec.rb`,
  `inventory_value_logs_spec.rb` — extend with pagination examples.

**`app_core`:**

- `app_core/app/controllers/admin/panel_controller.rb` — serves the
  admin shell/mount point.
- `app_core/app/views/admin/sessions/new.html.erb` — login form.
- `app_core/app/views/admin/panel/show.html.erb` — shell markup (topbar,
  sidenav, mount node), mirrors `dashboards/show.html.erb`'s structure.
- `app_core/app/frontend/entrypoints/admin-panel.jsx` — Vite entry.
- `app_core/app/frontend/admin-panel/AdminPanel.jsx`,
  `useHashRoute.js`, `adminApi.js`.
- `app_core/app/frontend/admin-panel/pages/{Items,PriceLogs,UserInventories,InventoryValueLogs}Page.jsx`
  + matching `*Reducer.js` files.
- `app_core/app/frontend/admin-panel/hooks/useAdminList.js`.
- `app_core/app/frontend/admin-panel/components/{Table,Pagination,BulkToolbar,RowActionsMenu,CreatePanel,ExpandableRow,Sparkline,Swatch}.jsx`.
- `app_core/app/frontend/admin-panel/utils/format.js`.
- `app_core/app/frontend/admin-panel/styles/admin-panel.css`.
- `app_core/app/frontend/admin-panel/__tests__/*` — mirroring the
  dashboard's flat-test-directory convention (reducer tests, hook test
  via `vi.stubGlobal('fetch', ...)`, composite page tests driving a real
  reducer per `component-tests-real-reducer.md`).
- `app_core/spec/requests/admin/sessions_spec.rb` — extend with HTML-path
  examples (login page renders, redirect on success/failure).
- `app_core/spec/requests/admin/panel_spec.rb` — new: unauthenticated
  redirect, authenticated renders shell with bridge token present.

## Test Plan

**Backend (`app_fetcher`, request specs, `type: :request`):**

- Pagination: default `page`/`per_page` (25), explicit values, clamping
  of out-of-range/garbage values (reusing `Appliers::Pagination`'s
  existing clamp behavior — assert it's wired in, not re-testing the
  class itself), `meta.total_count`/`total_pages` correctness, stable
  ordering across pages (no duplicate/skipped rows when paging through a
  seeded set).
- `bulk_warm_cache` (Items): warms the requested cache(s) only (assert
  real `Rails.cache` state per `caching.md`'s testing rule, not mocks),
  unknown ids silently skipped, invalid `cache_target` rejected
  (`422`/`{ message: "..." }`), per-player-bridge-token-rejected proof
  case (per `admin-api-controllers.md`'s MUST rule).
- `bulk_warm_cache` (UserInventory): same shape, single cache target.
- `global_index` (PriceLog): returns logs across multiple items in one
  page, includes each row's `market_hash_name`, asserts no N+1 (e.g. via
  a query-count assertion or `bullet`/manual `SELECT` count check),
  existing nested `index`'s own spec file untouched/still passing
  (regression proof the nested route's behavior didn't change).
- `warm_catalog_cache`: asserts `ItemCatalogCache.read(default_params)`
  is populated after the call.
- `UserInventoriesController#index`/`#show` with the new
  `total_value_cents`: a steam_id with an `InventoryValueLog` row returns
  its latest value; a steam_id with none returns `nil` (not `0`, not an
  error); `index` across multiple steam_ids asserts no N+1 from the
  `DISTINCT ON` batch (same query-count-assertion style as `PriceLog`'s
  `global_index`). `#show`'s new `items` array: correct
  `market_hash_name`/`added_at` pairs, ordered newest-added-first,
  absent from `index`'s own response shape (assert the key simply isn't
  there, not just unchecked).
- `global_index` (InventoryValueLog): returns rows across multiple
  steam_ids in one page, each with its own `steam_id`; existing nested
  spec file untouched/still passing. Trend downsample: a steam_id with
  30+ days of history produces a bounded-length point series (not one
  point per log row); a steam_id with only 1-2 days of history still
  produces a sensible short series, not an error or a crash; asserts no
  N+1 across multiple steam_ids on one page (one bulk query, not one
  per steam_id) via the same query-count-assertion style already used
  for `PriceLog`/`UserInventory`.

**Backend (`app_core`, request specs):**

- `admin/sessions_spec.rb`: `GET /admin/session/new` renders the form;
  `POST` with valid HTML-format credentials redirects to the panel;
  invalid credentials re-renders the form with an error; `format.json`
  behavior unchanged (regression-proof the existing 6 examples still
  pass as-is).
- `admin/panel_spec.rb`: unauthenticated `GET /admin` redirects to
  login; authenticated request renders 200 with the mount node and a
  non-blank `data-bridge-token`.

**Frontend (Vitest + RTL, `app_core/app/frontend/admin-panel/__tests__/`):**

- `useHashRoute.test.js` — hash read/parse, `hashchange` triggers
  re-render, unknown/empty hash falls back to a default resource.
- `*Reducer.test.js` (one per resource page) — selection
  toggle/select-all, pagination action, create-panel open/close, every
  action type.
- `useAdminList.test.js` — loading/success/error states via
  `vi.stubGlobal('fetch', ...)`, pagination param pass-through.
- Composite page tests (`ItemsPage.test.jsx`, etc.) — mount a harness
  with the real page reducer (per `component-tests-real-reducer.md`),
  drive via `@testing-library/user-event`: row selection → bulk toolbar
  enables; create-panel submit → calls the right endpoint; delete →
  refetch fires.
- `Sparkline.test.jsx` — renders the expected stroke color for an
  up/down trend (mirrors the dashboard's own `Sparkline` test
  expectations, if any exist — confirm during implementation).

## Implementation Steps

1. `app_fetcher`: add `Options::CacheTarget`, pagination to all four
   admin `index` actions (smallest independent change, no route changes
   needed), write/extend request specs, run `bundle exec srb tc`.
2. `app_fetcher`: add `bulk_warm_cache` (Items), `bulk_warm_cache`
   (UserInventory), `warm_catalog_cache` (Items) — routes, controller
   actions, request specs (including the per-player-token-rejected proof
   case for each new action).
3. `app_core`: make `Admin::BaseController#require_admin!` and
   `Admin::SessionsController#create`/`#destroy` format-aware; add
   `Admin::SessionsController#new` + login view; extend
   `admin/sessions_spec.rb`.
4. `app_core`: add `Admin::PanelController#show` + view + route; add
   `admin/panel_spec.rb`.
5. `app_core`: scaffold the Vite entry + `AdminPanel.jsx` +
   `useHashRoute.js` + the topbar/sidenav shell (no resource pages yet) —
   verify the island mounts and nav switches an empty placeholder per
   page.
6. `app_core`: build `adminApi.js` + `useAdminList.js`, then
   `ItemsPage.jsx` end-to-end (table, pagination, create panel, row
   actions, bulk toolbar + cache dropdown) — the fullest-featured page,
   proving the pattern before replicating it.
7. `app_core`: `PriceLogsPage.jsx` (simplest — read + delete only).
8. `app_core`: `UserInventoriesPage.jsx` (expandable nested rows + bulk
   toolbar, single cache target).
9. `app_core`: `InventoryValueLogsPage.jsx` (sparkline component).
10. Full test suites (`bundle exec rspec` both apps, `npm test` in
    `app_core`), `bundle exec srb tc` (`app_fetcher`), Rubocop both apps.
11. Manual verification in a running `docker-compose` stack: log in,
    exercise every resource page's full interaction set (see
    Verification).

## Verification

- `bundle exec rspec` (full suite) in `app_fetcher` and `app_core`.
- `bundle exec srb tc` in `app_fetcher`.
- Rubocop in both apps.
- `npm test` (Vitest) in `app_core`.
- Manual browser walkthrough: login → panel shell loads → each of the 4
  resource pages: pagination controls work, row actions succeed, bulk
  selection + cache action succeeds, Item's create panel creates a
  record, UserInventory's row expands/collapses, InventoryValueLog's
  sparklines render with correct up/down coloring.

## Risks

- **Bulk "rebuild cache" is actually "ensure warm," not a forced
  refresh** — consistent with the existing single-item `warm_cache`
  precedent and `caching.md`'s invalidate-ownership rule, but a literal
  reading of the mockup's Russian copy ("Пересоздать", "recreate")
  implies a forced rebuild. Accepted as a deliberate continuation of
  existing precedent, not a new decision — but worth the user's explicit
  sign-off before implementation, since it's a visible, if subtle, UX gap
  between label and effect.
- **`warm_catalog_cache` only pre-warms one (default/unfiltered) cache
  entry**, not "the catalog cache" as a whole (which has no enumerable
  "whole" to rebuild). If admins expect this button to affect filtered
  views too, it won't — flagged here rather than silently narrowing scope
  in the UI copy.
- **`list-query-objects.md` scope reading** — this plan assumes plain
  pagination without sort/filter doesn't require the full query-objects
  layer; if `styleguides-check` reads that styleguide more strictly, the
  admin index actions may need to move to that heavier structure instead
  (larger diff than currently planned).
- **`react-dashboard.md`'s "one reducer, not one per tile" rule** was
  written for a single-page island; this plan's reading ("one reducer per
  resource page, four pages total") needs `styleguides-check` sign-off
  as a generalization, not a violation.
- **No shared component library between `dashboard/` and `admin-panel/`**
  — some duplication (format helpers, sparkline pattern) is accepted
  deliberately per `react-dashboard.md`'s existing per-island structure;
  if a third island ever appears, this should be revisited.
- **Pagination stability under concurrent writes** — paging through
  ~184k `InventoryValueLog` rows while new rows are inserted
  (`InventoryValueScheduler` runs daily) could shift row positions
  between page loads (classic offset-pagination drift). Accepted for now
  (same limitation the public catalog's own offset pagination already
  has); not solving with keyset pagination in this pass.
- **PriceLog's flat global index was missing from the original plan** —
  discovered only once the frontend page was built against the real API
  contract (the original plan assumed the existing nested endpoint was
  sufficient; it isn't, since the mockup's page is a flat cross-item
  table). Resolved mid-implementation with the user's explicit sign-off
  (new top-level `GET /api/admin/price_logs` action, nested route
  unchanged) — flagged here so the gap and its resolution are both on the
  record, not just fixed silently.
- **UserInventory's value field and item list were also missing** — same
  root cause as the `PriceLog` gap (original plan only added pagination/
  bulk-cache, never new fields), discovered when building
  `UserInventoriesPage`. Resolved mid-implementation with the user's
  explicit sign-off: `total_value_cents` reuses the latest
  `InventoryValueLog` snapshot (may be stale by up to a day — same
  staleness the `InventoryValueLog` page itself already has, not a new
  problem this introduces); a steam_id never synced to a value log shows
  no value (`nil`), not `$0.00`, which could read as "confirmed worthless"
  if misrendered — the frontend must treat `nil` and `0` differently.
- **InventoryValueLog needed the same flat-global-index fix as PriceLog,
  plus a per-row trend the backend had no concept of at all** —
  discovered when building `InventoryValueLogsPage`. Resolved
  mid-implementation with the user's explicit sign-off: same
  flat-route pattern as `PriceLog`; the 30-day sparkline reuses
  `ItemTrendCache`'s downsample algorithm adapted to this resource's
  fields, computed fresh per request (not cached) and batched per page
  to avoid N+1. A steam_id with very little history (e.g. synced only
  once or twice) produces a short point series rather than an error —
  the frontend's sparkline component must render gracefully down to a
  single point or even zero points, not assume a full 9-point series.
- **`PriceLogsPage`/`InventoryValueLogsPage` both called a flat delete
  route that was never actually routed on the backend** — only caught
  during Step 11's live manual browser verification, since Vitest's
  mocked `fetch` never validates a call against real Rails routes.
  Resolved with the user's explicit sign-off: switch both pages to the
  real nested `destroy` routes (adding `item_id` to `PriceLog`'s flat
  rows; `InventoryValueLog`'s already carry the `steam_id` its nested
  route needs), and generalize the fix into a new `react-dashboard.md`
  rule ("Mutations Against Nested Backend Routes") so a future flat-list
  page doesn't repeat the same mistake.

## Assumptions

- `admin_login_path`/`admin_panel_path` naming is a starting proposal,
  not binding — finalize exact route helper names during implementation
  if friction shows up.
- No design precedent exists for the "session expired mid-session"
  banner — this plan assumes a simple inline message + relogin link is
  sufficient; revisit if product feedback wants something richer.
- The mockup's `@media (max-width: 880px)` responsive collapse is
  explicitly out of scope (see Scope) — assumed acceptable since this is
  an internal ops tool typically used on desktop.

## Completion Criteria

- Desired behavior explicit (see Expected Behavior).
- Scope explicit (see Scope).
- Affected/new files identified (see Files To Modify/Create).
- Test strategy defined (see Test Plan).
- Implementation steps ordered (see Implementation Steps).
- Verification defined (see Verification).
- Plan written to `.claude/plans/admin-panel-frontend.md`.

## Applicable Styleguides

All four gaps originally found here were resolved via `update-styleguide`
(amendments approved 2026-10-12); this section reflects the final,
checked set.

**Shared:**

- `.claude/styleguides/rails-layering.md` — the one-directional
  Controller→Action/Query→Model dependency flow, constraining both the
  new `app_fetcher` pagination/bulk code and the new `app_core` admin
  controllers.
- `.claude/styleguides/ruby-sorbet.md` — `# typed: strict`, `extend
  T::Sig`, a `sig` on every method, `T::Enum` for the new
  `Options::CacheTarget` — constrains every new/changed file in both
  apps.
- `.claude/styleguides/rspec-conventions.md` — spec-level mapping
  (request specs for controllers, unit specs for `Options::CacheTarget`),
  `FactoryBot` over fixtures — constrains the entire Test Plan.
- `.claude/styleguides/git-commits.md` — commit message format for
  `implement-plan`'s commits.

**`app_fetcher`:**

- `.claude/styleguides/fetcher/admin-api-controllers.md` — now governs,
  in addition to the four controllers' existing CRUD shape: the
  pagination envelope/default-ordering requirement for `index` actions
  (Implementation Steps 1), the `collection`-route convention,
  request/response shape, and `cache_target` enum validation for
  `bulk_warm_cache`/`warm_catalog_cache` (Implementation Step 2), and
  (added mid-implementation, Step 7) the nested-resource-may-also-expose-
  a-flat-global-index pattern plus its `.includes` N+1-avoidance rule,
  covering `PriceLogsController#global_index`; and (added mid-
  implementation, Step 8) the generalized batch-lookup N+1 rule
  (`.includes` vs. `DISTINCT ON`, same underlying concern), `show`
  legitimately returning a richer shape than `index`, and the nil-vs-zero
  rule for an optional derived field, covering
  `UserInventoriesController`'s `total_value_cents`/`items`. Re-confirmed
  sufficient as-is (no further amendment) for Step 9's
  `InventoryValueLogsController#global_index` — the already-generalized
  flat-global-index rule and batch-lookup N+1 rule both already cover it
  without needing resource-specific wording.
- `.claude/styleguides/fetcher/caching.md` — governs `bulk_warm_cache`/
  `warm_catalog_cache`'s cache-layer calls; confirmed no new
  `.invalidate` caller is introduced (both actions only read-through-warm).
- `.claude/styleguides/fetcher/list-query-objects.md` — confirmed
  sufficient as-is: its own "When to Use" already excludes a one-off
  pagination-only need from requiring the full query-objects stack,
  which is what licenses this plan's lighter `Appliers::Pagination`-only
  approach (Implementation Approach's "Backend: pagination" section).
- `.claude/adr/fetcher/admin-api-crud-routing.md` — the `resources`/
  `collection`/`member` routing shape this plan extends; now explicitly
  covers collection routes for actions with no single natural `:id`.

**`app_core`:**

- `.claude/styleguides/core/admin-authentication.md` — governs the
  format-aware `create`/`destroy`/`require_admin!` behavior, the new
  `#new` login action/view, and `Admin::PanelController`'s place in this
  stack (Implementation Steps 3-4).
- `.claude/styleguides/core/architecture-layers.md` — the admin stack's
  layer map and the direct-fetcher-read rule (now stated for both
  islands) that `Admin::PanelController` and `adminApi.js` follow
  (Implementation Steps 4-6).
- `.claude/styleguides/core/react-dashboard.md` — the component/testing
  conventions this plan's `admin-panel/` island follows, plus the
  multi-page directory structure (`pages/`, per-page reducers,
  `useHashRoute.js`, `adminApi.js`, `useAdminList.js`) now documented as
  this file's multi-page variant (Implementation Steps 5-9); and (added
  mid-implementation, Step 11) its new "Mutations Against Nested Backend
  Routes" rule, covering `PriceLogsPage`/`InventoryValueLogsPage`'s
  corrected delete handlers.
- `.claude/adr/core/sparkline-vs-recharts.md` — governs the
  `InventoryValueLog` sparkline implementation choice (hand-rolled SVG,
  not Recharts).
- `.claude/adr/core/component-tests-real-reducer.md` — governs the
  composite page tests' structure (real reducer, not mocked callbacks).
- `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  the already-accepted reasoning `architecture-layers.md`'s generalized
  no-proxy rule is grounded in; not re-litigated by this plan.

## Implementation Summary

All 11 steps completed. Backend (`app_fetcher`): pagination on all four
`Api::Admin::` index actions; bulk/catalog cache-warm actions
(`Options::CacheTarget`); flat global-index actions for `PriceLog` and
`InventoryValueLog` (with per-row `item_id`/`steam_id` and a batched
30-day trend downsample for the latter); `UserInventory` gained
`total_value_cents` (batched `DISTINCT ON`) and `show`'s `items` array;
`UserInventory ↔ InventoryValueLog` association added. Frontend
(`app_core`): format-aware admin session controllers + HTML login/panel
shell; a hash-routed multi-page React island
(`app_core/app/frontend/admin-panel/`) with one reducer per resource page,
a shared `useAdminList` hook, a shared `adminApi.js`, and all four
resource pages (`Item` full CRUD + bulk cache, `PriceLog` read + delete,
`UserInventory` expandable rows + sync/delete, `InventoryValueLog` with
hand-rolled sparklines).

Full test suites green throughout: `app_fetcher` 389 examples / 1 known
pre-existing failure (`UserInventoryCache` spec, unrelated to this work),
`app_core` 32 RSpec + 140 Vitest examples, zero new Sorbet errors in any
touched file (both apps), Rubocop clean on every touched Ruby file.

Four gaps were discovered mid-implementation, each resolved via the
documented stop → ask-the-user → update-plan → re-check-styleguides →
resume cycle (see each resource's "discovered gap" subsection above and
Risks): `PriceLog`'s missing flat global index, `UserInventory`'s missing
value/item-list fields, `InventoryValueLog`'s missing flat global index +
trend, and — caught only during this step's live manual browser
verification, not by any automated test — a real CORS gap
(`app_fetcher/config/initializers/cors.rb` only allowed
`/api/v1/*`, never `/api/admin/*`, so the admin panel could never
actually call its own API from a browser in any environment) and a
flat-delete-route bug in both `PriceLogsPage` and `InventoryValueLogsPage`
(both called a flat `DELETE` route that was never routed on the backend;
fixed by switching to the real nested `destroy` routes, and generalized
into `react-dashboard.md`'s new "Mutations Against Nested Backend Routes"
rule). The CORS gap predates this plan entirely (introduced when the
`Api::Admin::` namespace was first added) and was fixed directly rather
than logged to `fix_me.md`, since it blocks the feature from working at
all, in any environment — not a style deviation.

Manually verified in a running `docker-compose` stack: login,
all four resource pages load real data, pagination, `UserInventory` row
expand/collapse, `InventoryValueLog` sparklines, and delete actions on
both previously-broken pages (`PriceLog`, `InventoryValueLog`) all
confirmed working end-to-end via real (non-mocked) HTTP requests, with
zero browser console errors throughout.

### Post-review refactor (2026-10-14)

Code review of `InventoryValueLogsController`/`PriceLogsController`
surfaced four real duplication/scope issues, all fixed with no change to
external behavior (full test suites green before/after):

- `#index`/`#global_index` merged into a single `#index` per controller,
  branching on whether the nested parent param is present — the two
  bodies were ~90% identical; the earlier "two distinct actions" call
  (see each resource's "discovered gap" section above) didn't hold up
  once both existed side by side. `config/routes.rb`'s flat routes now
  point at `#index` instead of `#global_index`.
- `meta`'s per-action construction extracted to a shared
  `Api::Admin::ApplicationController#pagination_meta` helper, used by all
  four controllers' `index` actions.
- `meta.page`/`meta.per_page` dropped from every admin index response —
  pure echo of request params the caller already has; `total_count`/
  `total_pages` (the only genuinely server-derived fields) are kept. All
  four frontend pages switched their `<Pagination>` props from
  `meta.page`/`meta.per_page` to their own reducer's `state.page`/
  `state.perPage`.
- The windowed-downsample algorithm, previously hand-copied from
  `ItemTrendCache#downsample` into `InventoryValueLogsController` with a
  comment explicitly declining to share it, extracted into
  `Appliers::WindowedDownsample` — used by both call sites now. The
  "wait for a third use" reasoning didn't hold up against the cost of
  duplicating a genuinely fiddly cursor-walk algorithm between two call
  sites.

`admin-api-controllers.md` updated to reflect all four changes (the
merged-`#index` rule now explicitly reverses the earlier "never branch"
MUST, with the history kept visible rather than silently rewritten).

### Post-review refactor, round 2 (2026-10-14)

Further code review of the same controllers:

- `Options::CacheTarget` removed entirely — `Items#bulk_warm_cache` no
  longer takes a `cache_target` selector; it always warms all three
  sibling caches (`ItemPriceCache`/`PriceHistoryCache`/`ItemTrendCache`)
  for the requested item batch, the same "one logical collaborator"
  grouping the single-item `warm_cache` action already used. Removed the
  enum class, its spec, and the frontend's cache-target dropdown
  (`ItemsPage`'s "Пересоздать кэш ▾" collapsed to a single "Пересоздать
  кэш" button, matching `UserInventoriesPage`'s already-simpler
  single-target button).
- Response-shape building moved out of all four admin controllers' private
  `*_json` methods into dedicated serializers
  (`AdminItemSerializer`/`AdminPriceLogSerializer`/
  `AdminUserInventorySerializer`/`AdminInventoryValueLogSerializer` in
  `app/serializers/`), matching the house convention the public-API
  serializers already established (`ItemCatalogSerializer` et al.) —
  `.index`/`.show` class methods, controllers still own `meta`-building
  and batched DB lookups (those are query concerns), serializers own only
  row-shaping, including the nested-vs-flat dual-shape branch
  (`PriceLog`/`InventoryValueLog`) via a `nested:` flag instead of a
  controller-side ternary between two private builder methods.

`admin-api-controllers.md` updated for both changes (the response-builder
MUST rule now points at the serializer convention; `cache_target`
references removed except where narrating this change's own history).

### Post-review refactor, round 3 (2026-10-14): InventoryValueLog trend removed

Code review also questioned the per-row 30-day trend sparkline (see
"InventoryValueLog: flat global index + per-row trend" above): it was
genuinely new analytics logic — a windowed-downsample time-series
computation over `InventoryValueLog` — that didn't exist anywhere in the
domain before this plan, invented solely to satisfy the admin mockup's
"Тренд (30д)" column. Unlike `ItemTrendCache`'s own downsample (adapted
as a *reference*, not a shared dependency, for the original
implementation), this had no pre-existing product requirement and no
other consumer — its only reason to exist was one decorative column on
one admin page.

Decision: remove it entirely. An admin panel's job is managing existing
records, not growing new analytics features that live only there. If
inventory-value trend data turns out to be genuinely useful later, it
should be built as a real product feature (its own cache class, actually
reused by something user-facing) that the admin panel can then display —
not invented backwards from an admin mockup's decorative column.

Removed:

- `InventoryValueLogsController`'s `TREND_WINDOW_DAYS`/`TREND_POINTS`
  constants, `trends_by_steam_id`/`downsample` methods, and the
  `trends:` parameter passed into the serializer.
- `AdminInventoryValueLogSerializer`'s `trend`/`global_log_json`-with-trend
  handling — the flat row shape is now just `{id, log_date,
  total_value_cents, steam_id}`, no `trend` key at all.
- `app_core/app/frontend/admin-panel/components/Sparkline.jsx` and its
  test — this admin-panel component had exactly one caller
  (`InventoryValueLogsPage`), so once that caller stopped needing a
  sparkline, the component was dead code, not kept "for later."
  `InventoryValueLogsPage`'s "Тренд (30д)" column removed from both the
  table and the Expected Behavior section above.
- The shared `Appliers::WindowedDownsample` class introduced in round 1
  (and the two-separate-classes variant briefly proposed as a middle
  ground) — with the admin-only consumer gone, there's no second call
  site left to share the algorithm with. `ItemTrendCache#downsample`
  reverted to its original, pre-this-plan, fully self-contained private
  method — this plan never needed to touch it in the first place; the
  only reason it was touched at all was to share code with a feature
  that's now gone.

`react-dashboard.md`'s Charting section had gained a paragraph describing
the admin panel's `Sparkline.jsx` as a second instance of the
hand-rolled-SVG pattern — removed along with the component, since the
pattern no longer has a second example in this codebase (still fully
documented via the dashboard's own `Sparkline.jsx`).

### Post-review refactor, round 4 (2026-10-14): serializers namespaced under `Admin::`

The four `Admin<Resource>Serializer` classes from round 2 (flat classes,
name-prefixed) moved into a real `Admin::` module —
`app/serializers/admin/{item,price_log,user_inventory,inventory_value_log}_serializer.rb`,
classes `Admin::ItemSerializer` etc. — matching how the controllers
themselves are namespaced (`Api::Admin::`), rather than faking a
namespace with a string prefix on a flat class name.

Every call site references the fully-qualified `::Admin::<X>Serializer`
(leading `::`), never a bare `Admin::<X>Serializer` — all four
controllers live lexically inside `Api::Admin::`, and Ruby resolves a
bare `Admin` constant reference there to the surrounding `Api::Admin`
module itself before it reaches the top-level `Admin` module these
serializers actually live in, which would raise a `NameError`. This is
the same class of constant-shadowing trap `Options::CacheTarget` hit
against `ActionController::ParamsWrapper::Options` earlier in this
namespace's history (see the "PriceLog: flat global index" discovery
above) — `admin-api-controllers.md` now documents it as a standing rule,
not just a one-off fix, since any bare reference to a same-named
top-level module from inside a matching nested namespace reproduces it.

### Post-review refactor, round 5 (2026-10-14): nested index removed, `Pagination#apply` added

Two more review findings, both backend-only:

- **The nested `index` for `PriceLog`/`InventoryValueLog` was dead code.**
  Reviewing `nested = params[:...].present?` in
  `InventoryValueLogsController#index` surfaced the question of why a
  nested route existed at all for a resource whose only real caller reads
  the flat list. Checked: the admin frontend never calls
  `GET /api/admin/items/:item_id/price_logs` or
  `GET /api/admin/user_inventories/:steam_id/inventory_value_logs` —
  only the flat index and the nested `destroy`. Both nested routes'
  `only: %i[index destroy]` became `only: %i[destroy]`; both
  controllers' `nested`-branching `#index` collapsed back to a single
  unconditional flat query; both serializers lost their `nested:` flag
  and now always render the one (flat) row shape. This predates the
  current session's work (the nested `index` was part of the original
  "backend foundation" commit) but was never actually exercised by
  anything this plan built — removed once a real reviewer asked "why does
  this exist."
- **`Appliers::Pagination` gained `#apply(scope)`**
  (`scope.limit(per_page).offset(offset)`), replacing the
  `.limit(pagination.per_page).offset(pagination.offset)` chain repeated
  at every pagination call site — all four admin `index` actions, plus
  the three existing public `*CatalogQuery`/`InventoryDetailQuery`
  classes (same `Appliers::Pagination`, same repeated chain, fixed for
  consistency even though those files predate this plan). One exception
  kept the manual chain: `InventoryCatalogQuery`'s `.pluck(*AGGREGATE_COLUMNS.map { ... })`
  — Sorbet's `pluck` signature checks a splat's size statically, and
  `apply`'s precisely `ActiveRecord::Relation`-typed return made that
  check newly apply to this one call site in a way it didn't against the
  previously-untyped chain. Documented inline rather than silently
  working around it.

`admin-api-controllers.md` updated for both: the Structure section no
longer describes a nested/flat branch (just the one flat index), Rules
gained a MUST against reintroducing an unused nested `index`, and
`Pagination#apply` is now the documented way to apply pagination to a
scope.
