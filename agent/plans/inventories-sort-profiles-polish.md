---
status: implemented
app: fetcher+core
goal: Polish the Inventories list page — four value/items sort directions, equal-height search control, real nickname/avatar enrichment from app_core, and hiding the card delta when it is flat
created: 2026-10-16
---

# Development Plan

## Goal

Bring `GET /inventories` (the public, unauthenticated inventories
catalog) up to the shape the user asked for in one pass:

1. Replace the Inventories **sort dropdown** with four options — `Value,
   high to low` / `Value, low to high` / `Items, high to low` / `Items,
   low to high` — dropping the two options judged useless (`24h change`,
   `Recently synced`).
2. Make the **disabled search field and the sort button the same
   height** (search stays non-functional by design; nicknames aren't
   searchable in `app_fetcher`).
3. Show the **real Steam nickname/avatar** on an inventory card (list)
   and in the detail page's profile header, sourced from `app_core`'s
   own `users` table via a new `app_core` JSON enrichment endpoint,
   falling back to `steam_id` + a letter-circle avatar when no profile
   is known.
4. **Hide the card's 24h delta badge when the change is flat**
   (`0` / absent) instead of rendering a misleading `▲ 0.0%` — the
   aggregate-delta case the earlier `dashboard-flat-trend` plan
   deliberately left out of scope.

## Expected Behavior

### Sort (Inventories list)

- The sort dropdown offers exactly four options, in this order:
  `Value, high to low` (`value_desc`, default), `Value, low to high`
  (`value_asc`), `Items, high to low` (`items_desc`), `Items, low to
  high` (`items_asc`).
- `24h change` (`change_24h_desc`) and `Recently synced`
  (`recently_synced`) are gone from both the UI and `app_fetcher`'s
  `sort` enum; passing either to the API now returns
  `400 {"message":"Unsupported sort: <value>"}` like any other unknown
  value.
- `value_desc` remains the default on first load.
- Changing the sort still re-fetches page 1 with the new `sort` value.

### Search control

- The search input stays `disabled` with the existing
  "Search by nickname… (coming soon)" placeholder — no behavior change.
- The search input and the sort button render at the **same height**.

### Nickname / avatar enrichment

- A new unauthenticated `app_core` endpoint
  `GET /inventories/profiles?steam_ids[]=<id>&steam_ids[]=<id>` returns
  `{"profiles": {"<steam_id>": {"nickname": <string|null>,
  "avatar_url": <string|null>}, ...}}` for every requested `steam_id`
  that exists in `app_core`'s `users` table. Unknown ids are simply
  absent from the map; an empty/absent `steam_ids` list returns
  `{"profiles": {}}` and touches the database zero times.
- The list island fetches the catalog from `app_fetcher` first, then
  calls this `app_core` endpoint once per loaded page with that page's
  `steam_id`s, and merges the result into the cards:
  - known `nickname` → shown instead of `steam_id`;
  - known `avatar_url` → rendered as the circular avatar image;
  - no profile, or a blank field → today's fallback (`steam_id` as the
    name, letter-circle avatar built from the first character).
- The detail page (`/inventories/:steam_id`) does **not** call the
  endpoint: `app_core` already knows the `steam_id` from the URL, so
  `InventoriesController#show` looks the profile up directly and embeds
  it into `#inventory-detail-root`; the detail island renders the same
  nickname/avatar/fallback logic from that embedded value.
- An enrichment failure (profiles request errors) is **non-fatal**: the
  cards render with the `steam_id`/letter fallback, exactly as today.

### Card delta when flat

- An inventory card whose `change24hPercent` is `0` or absent renders
  **no** `.inv-delta` badge (no `▲`/`▼`).
- A non-zero positive/negative change renders exactly as today
  (`is-up`/`is-down`, `▲`/`▼`, one decimal).

### Must remain unchanged

- `app_fetcher`'s `Options::ItemSortOption` (the *top items* sort on the
  detail page, `price_desc|price_asc|change_24h_desc|name_asc`) — the
  item list keeps its own four options, including `24h change`.
- `app_fetcher`'s public endpoints' response shapes for the catalog and
  detail payloads (no `nickname`/`avatar_url` added to
  `app_fetcher` — profile data stays in `app_core`).
- The catalog/detail caches, pagination, rarity mix/breakdown, and the
  item-row flat-trend/sparkline behavior already implemented.
- The topbar's own profile chip (unrelated to this change).

## Scope

### In Scope

1. `app_fetcher`: four-value `Options::InventorySortOption` (+ its unit
   and request-spec coverage).
2. `app_core` frontend: `InventorySortDropdown` options/labels;
   `reducer.js` default unchanged; `InventoriesIndex` test updates.
3. `app_core` frontend + CSS: equal control heights in the inventories
   toolbar.
4. `app_core` backend: `InventoriesController#profiles` JSON action +
   route + a `Inventories::Profiles` action; `#show` embeds the profile
   for its `steam_id`; request-spec coverage.
5. `app_core` frontend: `useInventoryProfiles` hook; `InventoryGrid`/
   `InventoryCard` profile prop + avatar/name rendering; `InventoryDetail`
   profile prop + header rendering; CSS for image/letter avatars.
6. `app_core` frontend: `InventoryCard` flat-delta hiding via the shared
   `trendDirection` helper (+ test).
7. All affected tests on both sides.

### Out of Scope

- Implementing **search** (no nickname is stored in `app_fetcher`; the
  field stays disabled, per the earlier `public-inventory-endpoints`
  decision).
- Adding `nickname`/`avatar_url` to `app_fetcher`'s responses, or any
  `app_core → app_fetcher` profile sync — the decision to keep profile
  data in `app_core` stands.
- Backfilling `nickname`/`avatar_url` for users who logged in before
  `STEAM_WEB_API_KEY` was wired (unchanged; a user is corrected on their
  next login).
- The detail page's item-sort options or the `TopItemsList` sparklines.
- Any change to the `PortfolioHeroTile` delta guard (already hides a
  zero change).
- Reworking the `dashboard-flat-trend` item-row rules; only the
  previously-excluded **card** delta is brought into the flat rule.

## Decisions Carried From Clarification

Settled with Oleg; not to be revisited by `styleguides-check` or
`implement-plan`:

1. **Sort set = four options** `value_desc|value_asc|items_desc|
   items_asc`; `recently_synced` and `change_24h_desc` are removed
   outright (removed from the enum, not just hidden in the UI).
2. **Search stays disabled**; only its height is fixed to match the
   sort button.
3. **Profile source = a new `app_core` JSON endpoint** (chosen over
   "embed only `current_user`" and "embed all `users`"), with the detail
   page enriched directly from the URL's `steam_id`. Because this makes
   a public React island call an `app_core` endpoint (a new pattern),
   `styleguides-check` must amend
   `agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md`
   (and `core/architecture-layers.md`) before implementation.
4. **Card trend = hide the delta badge when flat** (`0`/absent),
   reusing `shared/utils/trend.js`'s `trendDirection` — no
   `InventoryValueLog`-based "single snapshot" logic, no new sparkline.

## Implementation Approach

### `app_fetcher` — the sort enum

`Options::InventorySortOption` keeps `ValueDesc`/`ItemsDesc` and adds
`ValueAsc` (`"value_asc"`) / `ItemsAsc` (`"items_asc"`); `RecentlySynced`
and `ChangeDesc` are deleted. `#apply` gains the two ascending
`order(Arel.sql("total_value_cents ASC"))` /
`order(Arel.sql("items_count ASC"))` branches and drops the two
removed ones — the `case self` / `else T.absurd(self)` shape is
unchanged, so Sorbet still proves exhaustiveness. `InventoryCatalogQuery`
already defaults to `ValueDesc`; `InventoryCatalogCache` keys on
`params[:sort].to_s` generically and needs no change. No serializer or
response-shape change.

### `app_core` — the profiles enrichment endpoint

New route `get "inventories/profiles", to: "inventories#profiles"`,
declared **before** `resources :inventories` so it isn't swallowed by
the `:steam_id` show route.

The batch lookup and shaping move into a new action
(`Inventories::Profiles.call(steam_ids)`), per the ADR's "anything
beyond a single identity lookup goes through an action" rule — a batch
`User.where(steam_id: …).pluck(:steam_id, :nickname, :avatar_url)` is
more than that one lookup. The action de-duplicates, drops blanks, caps
the input at `100` (the same ceiling the catalog's `per_page` already
uses, so one page's ids always fit), and returns a plain
`Hash[steam_id => {nickname:, avatar_url:}]`.

`InventoriesController#profiles` is a thin JSON action: read
`Array(params[:steam_ids])`, delegate to the action, `render json:`.
`#show` keeps its thin shape and additionally does the one allowed
single lookup — `@profile = User.find_by(steam_id: params[:steam_id])`
(`T.let(…, T.nilable(User))`) — which `show.html.erb` embeds as
`data-nickname`/`data-avatar-url` on `#inventory-detail-root`.

### `app_core` frontend — enrichment + rendering

- **New hook `useInventoryProfiles(steamIds)`** (island-local, alongside
  `useInventoryCatalog`): fetches `/inventories/profiles` (same-origin
  relative URL — no new data attribute needed) with
  `steam_ids[]=…` query params, keyed on the joined id list so a page
  change re-fetches. Returns a plain `steamId → profile` map; any
  failure resolves to `{}` (silent fallback), so it never turns the
  page into an error state. Its `{data, status}` contract follows the
  island convention; the page only consumes the map.
- **`InventoriesIndex`** derives `steamIds` from the loaded page and
  calls the hook (before its loading/error early returns), then passes
  the map down. **`InventoryGrid`** forwards `profile={profiles[steamId]}`
  to each card. **`InventoryCard`** renders the avatar (`<img>` when
  `profile.avatarUrl`, else a letter-circle `<span>` using the *same*
  `inv-avatar` class) and the name (`profile.nickname || steamId`), and
  hides the delta via `trendDirection`.
- **`InventoryDetail`** takes a `profile` prop (from the embedded data
  attributes via `inventory_detail.jsx`) and applies the same
  avatar/name logic to `.profile-head`.
- **CSS** (`inventories.css`): make `.inv-avatar`/`.profile-head-avatar`
  work for both an `<img>` (`object-fit: cover`) and a centred letter;
  set a shared explicit height on `.inv-toolbar .search-field input`
  and `.inv-toolbar .toolbar-btn` so the two controls line up (scoped to
  `.inv-toolbar` so other islands' toolbars are untouched).

## Files To Modify

### `app_fetcher`

- `app_fetcher/app/queries/options/inventory_sort_option.rb` — swap
  `RecentlySynced`/`ChangeDesc` for `ValueAsc`/`ItemsAsc`; add the two
  `ASC` `#apply` branches. Reason: decision 1.
- `app_fetcher/spec/queries/options/inventory_sort_option_spec.rb` —
  replace the `RecentlySynced`/`ChangeDesc` examples with
  `ValueAsc`/`ItemsAsc` ordering examples. Reason: unit coverage for the
  new enum.
- `app_fetcher/spec/requests/api/public/inventories_spec.rb` — add
  ascending-sort coverage and assert the removed values now 400.
  Reason: request-boundary coverage for the changed contract.

### `app_core`

- `app_core/config/routes.rb` — add `get "inventories/profiles"` before
  `resources :inventories`. Reason: the enrichment endpoint.
- `app_core/app/controllers/inventories_controller.rb` — add
  `#profiles` (JSON) and the `#show` `@profile` lookup. Reason:
  decisions 3.
- `app_core/app/views/inventories/show.html.erb` — embed
  `data-nickname`/`data-avatar-url` on `#inventory-detail-root`. Reason:
  detail enrichment without a second request.
- `app_core/app/frontend/entrypoints/inventory_detail.jsx` — read the
  two new data attributes and pass a `profile` prop. Reason: wire the
  embedded profile into the island.
- `app_core/app/frontend/inventories/InventoriesIndex.jsx` — call
  `useInventoryProfiles` and pass the map to the grid. Reason: list
  enrichment.
- `app_core/app/frontend/inventories/components/InventoryGrid.jsx` —
  accept `profiles`, forward `profile` per card. Reason: list
  enrichment.
- `app_core/app/frontend/inventories/components/InventoryCard.jsx` —
  avatar + name from `profile`; hide flat delta via `trendDirection`.
  Reason: decisions 3 + 4.
- `app_core/app/frontend/inventories/InventoryDetail.jsx` — accept
  `profile`, render avatar/name with fallback. Reason: decision 3.
- `app_core/app/frontend/inventories/components/InventorySortDropdown.jsx`
  — four options + labels. Reason: decision 1.
- `app_core/app/frontend/inventories/styles/inventories.css` — avatar
  `<img>`/letter styling; equal-height `.inv-toolbar` controls. Reason:
  decisions 2 + 3.
- Tests: `app_core/app/frontend/inventories/__tests__/InventoryCard.test.jsx`
  (profile + flat delta), `.../InventoriesIndex.test.jsx` (sort label +
  profiles fetch/merge + fetch mock handling the relative profiles URL),
  `.../InventoryDetail.test.jsx` (profile prop rendering; existing
  no-profile cases unchanged), `app_core/spec/requests/inventories_spec.rb`
  (profiles endpoint + show profile attrs).

## Files To Create

- `app_fetcher` — none.
- `app_core/app/actions/inventories/profiles.rb` — `Inventories::Profiles.call(steam_ids)`,
  the capped batch `User` lookup + map shaping. Reason: action layer for
  the batch lookup (ADR rule).
- `app_core/app/frontend/inventories/hooks/useInventoryProfiles.js` —
  the enrichment data-loading hook. Reason: one hook per distinct
  data-loading need.
- `app_core/app/frontend/inventories/__tests__/useInventoryProfiles.test.js`
  — hook test (success map, empty ids, failure → `{}`).

## Test Plan

Follow `rspec-conventions.md` (fetcher layer→level mapping) and
`react-dashboard.md`'s Testing conventions (flat `__tests__/`, `.test.js`
for pure/hook logic, `.test.jsx` for rendering).

**`app_fetcher`**
- `spec/queries/options/inventory_sort_option_spec.rb`: `ValueDesc`
  orders by `total_value_cents DESC`, `ValueAsc` by `ASC`, `ItemsDesc`
  by `items_count DESC`, `ItemsAsc` by `ASC` — each against real
  factory-built inventories with distinct aggregates (same shape as the
  existing examples).
- `spec/requests/api/public/inventories_spec.rb` "sort" context: add
  `sort=value_asc`/`items_asc` ordering assertions; assert
  `sort=change_24h_desc` and `sort=recently_synced` now return
  `400` with `"Unsupported sort: …"`. The existing default/`bogus`
  examples stay.

**`app_core` Ruby**
- `spec/requests/inventories_spec.rb`: new `GET /inventories/profiles`
  examples — returns the map for a known `steam_id`; omits an unknown
  id; returns `{}` for a missing/empty `steam_ids`; caps an oversized
  list; is reachable signed-out. Also extend the `GET /inventories/:steam_id`
  example to assert the embedded `data-nickname`/`data-avatar-url` for a
  `User` that exists for that `steam_id` and blank attributes when none
  does. (`User` factory already provides a nickname/avatar.)
- No action unit spec is required if the request spec exercises the
  action's full behavior; if `rspec-conventions.md`'s path-mirroring rule
  wants one, add `spec/actions/inventories/profiles_spec.rb` covering
  de-dup, blank drop, the 100 cap, and unknown-id omission.

**`app_core` frontend**
- `useInventoryProfiles.test.js`: returns the profile map on success;
  short-circuits (no fetch) for an empty id list; degrades to `{}` on a
  non-OK response; re-fetches when the id list changes.
- `InventoryCard.test.jsx`: nickname + avatar image when a profile is
  passed; `steam_id` + letter circle when it isn't; **no `.inv-delta`**
  for `change24hPercent: 0`; existing up/down and link examples stay.
- `InventoriesIndex.test.jsx`: update the sort-change example to the new
  `Items, high to low` label; make the `fetch` stub answer both the
  `app_fetcher` catalog URL and the relative `/inventories/profiles`
  URL; assert a card shows the merged nickname; keep the
  disabled-search and empty-state examples.
- `InventoryDetail.test.jsx`: existing cases still render with no
  `profile` prop (fallback to `steamId`); add one case passing a
  `profile` and asserting the nickname/`<img>` in `.profile-head`.

## Implementation Steps

1. `app_fetcher`: change `Options::InventorySortOption`; update its unit
   spec (RED for the new `asc` values, GREEN after) and the request
   spec's sort context. Run the `app_fetcher` suite + `srb tc` +
   rubocop.
2. `app_core` frontend: update `InventorySortDropdown` options/labels
   and adjust `InventoriesIndex.test.jsx` accordingly.
3. `app_core` CSS: equal-height `.inv-toolbar` controls.
4. `app_core` backend: add `Inventories::Profiles`, the route, the
   controller `#profiles`/`#show` changes, the `show.html.erb` data
   attributes, and their request-spec coverage (RED → GREEN).
5. `app_core` frontend: add `useInventoryProfiles` (+ test), wire
   `InventoriesIndex`/`InventoryGrid`, update `inventory_detail.jsx` +
   `InventoryDetail` for the `profile` prop.
6. `app_core` frontend: `InventoryCard` profile rendering + flat-delta
   hiding, with the `InventoryCard.test.jsx` cases.
7. `app_core` CSS: avatar image/letter styling for the card and the
   detail header.
8. Run the frontend suite, `npm run lint`, `npm run format` (see
   Verification), then the full `app_core` RSpec suite + `srb tc` +
   rubocop.

## Verification

- `app_fetcher`: `bundle exec rspec` (targeted files, then the full
  suite) + `bundle exec srb tc` + `bin/rubocop`.
- `app_core`: `bundle exec rspec` (targeted files, then the full suite)
  + `bundle exec srb tc` + `bin/rubocop`.
- Frontend: `npm test` (`vitest run`), `npm run lint`, `npm run
  format` (Prettier — new/changed files must pass `format:check`).
  Note `inventories/InventoriesIndex.jsx` is already red in
  `fix_me.md` for `prettier --check`; this change touches that file, so
  it is run through `npm run format` and that `fix_me.md` entry is
  removed once it passes.
- Run the Ruby suites through `docker compose` per
  `ci-and-coverage.md` (with the `docker-compose.ci.yml` override for
  frontend checks), as `bin/ci` does.
- Manual/visual check: the four sort options re-fetch correctly; the
  search input and sort button are identical in height; a card for a
  known `steam_id` shows the nickname/avatar while an unknown one falls
  back; a `0`-change card shows no `▲ 0.0%`.

## Risks

- **New cross-app call to `app_core` from a public island.** This is a
  genuine new pattern (previously the public island read only
  `app_fetcher`). It is app_core-owned data, not an `app_fetcher` proxy,
  but it must be recorded in the ADR/styleguide during
  `styleguides-check` — otherwise it becomes an undocumented second data
  path. Flagged up front so that check isn't a surprise.
- **The profiles endpoint is unauthenticated** and reflects Steam-public
  profile data (nickname/avatar are public on Steam). It's bounded by the
  `100`-id cap and returns only ids the caller already supplied, but is
  still a new publicly-hittable read — worth a look during review if a
  stricter guard is wanted.
- **Test `fetch` stubs must answer two URLs** now (`app_fetcher`'s
  absolute catalog URL and the relative `/inventories/profiles`).
  Existing `mockImplementationOnce` stubs will error on the second call
  unless updated — the main mechanical risk in the frontend tests.
- **CSS height equality is font/padding dependent.** An explicit shared
  `height` on both controls (not padding-matching) is the robust way;
  verify visually, since Vitest can't assert rendered height.
- **Removing enum members is a contract change** for any external caller
  still sending `recently_synced`/`change_24h_desc` — accepted (endpoint
  is a small internal/public beta; the UI was the only known caller).

## Assumptions

- `app_core`'s `users` table already contains a row per tracked
  `steam_id` (the `app_fetcher` inventory is created on that user's first
  dashboard load), so the enrichment map is populated for most list rows;
  ids with no `app_core` row fall back cleanly.
- A `100`-id cap is the right bound (one catalog page is `per_page=24`,
  so it always fits); a larger catalogue page would still enrich its
  first 100 ids.
- The shared control height is `34px` (between the search input's current
  ~36px and the button's ~29px); a tuning value, confirmed visually.
- `/inventories/profiles` relative fetch resolves correctly in the
  production island (same origin as the page); tests can assert the
  relative URL.

## Applicable Styleguides

- `agent/styleguides/fetcher/list-query-objects.md` — `Options::*`
  enum shape (`#apply`, `T.absurd`) for the changed sort enum.
- `agent/styleguides/fetcher/public-api-controllers.md` — the
  `UnsupportedParamError` → 400 shape the removed sort values now follow.
- `agent/styleguides/fetcher/caching.md` — confirm
  `InventoryCatalogCache`'s generic `sort` key needs no change.
- `agent/styleguides/fetcher/architecture-layers.md`,
  `rails-layering.md` — layer placement of the enum change.
- `agent/styleguides/core/architecture-layers.md` — **amended
  this pass (approved)**: new "App_core-Owned Enrichment (Public Pages)"
  carve-out, plus Structure/Controllers/Actions/Dependencies/Interaction/
  Canonical updates, constraining the new public-island → `app_core`-owned
  endpoint pattern.
- `agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  **amended this pass (approved)**: the "Amendment (2026-10-16):
  App_core-Owned Enrichment Endpoints" section clarifies the "no proxy"
  rule covers `app_fetcher` data only and permits the `app_core`-owned
  enrichment endpoint, with constraints.
- `agent/styleguides/core/react-dashboard.md` — **amended this pass
  (approved)**: the flat-trend rule now also covers the inventory card's
  aggregate delta, and State & Data Loading now documents a public
  island's one app_core-owned enrichment hook with a non-fatal fallback.
- `agent/styleguides/ruby-sorbet.md` — every new Ruby file
  (`Inventories::Profiles`, controller action) typed with `sig`s.
- `agent/styleguides/rspec-conventions.md` — spec placement/level for the
  new action/request and hook/component tests.
- `agent/styleguides/git-commits.md` — commit scope/format.

## Completion Criteria

- The four value/items sort directions work end to end; the two removed
  values 400.
- The search input and sort button are the same height.
- Cards and the detail header show the real nickname/avatar when
  `app_core` knows the `steam_id`, and the `steam_id`/letter fallback
  otherwise, with the detail page loading no profiles request.
- A flat card delta renders no badge.
- New/changed Ruby and frontend tests pass; lint/format/srb are clean for
  every touched file; the `InventoriesIndex.jsx` `fix_me.md` entry is
  removed.
- No changes outside the files listed above.

# Implementation Summary

## Implemented

**`app_fetcher` — sorts.** `Options::InventorySortOption` now has exactly
`ValueDesc`/`ValueAsc`/`ItemsDesc`/`ItemsAsc`; `RecentlySynced` and
`ChangeDesc` are deleted, with the two ascending `#apply` branches added
(`total_value_cents ASC` / `items_count ASC`) and the removed ones gone.
`InventoryCatalogQuery`'s default (`ValueDesc`) and `InventoryCatalogCache`
(keys generically on `params[:sort]`) needed no change.

**`app_core` — profile enrichment endpoint.** New route
`GET /inventories/profiles` (declared *before* `resources :inventories`
so `:steam_id` doesn't swallow it), a new action
`Inventories::Profiles.call(steam_ids)` (de-dupes, drops blanks, caps at
`MAX_STEAM_IDS = 100`, batch `User.where(steam_id:).pluck` → `Hash`), and
`InventoriesController#profiles` as a thin JSON action. `#show` gained the
single `@profile = User.find_by(steam_id:)` lookup, embedded into
`#inventory-detail-root` as `data-nickname`/`data-avatar-url`.

**`app_core` — frontend.**
- `InventorySortDropdown` → four options/labels (`Value, high to low`,
  `Value, low to high`, `Items, high to low`, `Items, low to high`).
- New `useInventoryProfiles(steamIds)` hook: same-origin
  `/inventories/profiles?steam_ids[]=…`, keyed on the joined id list,
  maps `avatar_url`→`avatarUrl`, and degrades to `{}` on any failure
  (non-fatal). `InventoriesIndex` calls it and passes the map through
  `InventoryGrid` to `InventoryCard`.
- `InventoryCard` renders `profile.nickname`/`profile.avatarUrl` (falling
  back to `steam_id` + a letter-circle `.inv-avatar`) and hides the
  `.inv-delta` badge via `trendDirection` when flat.
- `InventoryDetail` takes a `profile` prop (from the embedded data
  attributes via `inventory_detail.jsx`) and applies the same
  avatar/name/fallback to `.profile-head`.
- `inventories.css`: `.inv-avatar`/`.profile-head-avatar` now work for
  both `<img>` (`object-fit: cover`) and a centred letter; a new
  `.inv-toolbar`-scoped rule sets an explicit `36px` height on the search
  input and the sort button so they line up (leaving other islands'
  toolbars untouched).

**Docs.** Amended (approved) `agent/styleguides/core/architecture-layers.md`
(new "App_core-Owned Enrichment (Public Pages)" carve-out),
`agent/styleguides/core/react-dashboard.md` (card-delta flat rule +
app_core enrichment hook), and
`agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md`
(new "Amendment (2026-10-16)" section). Removed the now-resolved
`InventoriesIndex.jsx` `prettier --check` entry from
`agent/styleguides/fix_me.md`.

## Tests

Added/changed (RED→GREEN per behavior):

- `app_fetcher/spec/queries/options/inventory_sort_option_spec.rb` —
  `ValueDesc`/`ValueAsc`/`ItemsDesc`/`ItemsAsc` ordering.
- `app_fetcher/spec/queries/inventory_catalog_query_spec.rb` — query-level
  `value_asc`/`items_asc` (replacing the removed `recently_synced`/
  `change_24h_desc` cases).
- `app_fetcher/spec/requests/api/public/inventories_spec.rb` —
  `value_asc`/`items_desc`/`items_asc` ordering; the removed values now
  `400`.
- `app_core/spec/actions/inventories/profiles_spec.rb` (new) — map,
  unknown-id omission, de-dup, blank drop, 100 cap, empty input.
- `app_core/spec/requests/inventories_spec.rb` — `GET /inventories/profiles`
  (known/unknown/empty/cap, no auth) and the show page's embedded
  `data-nickname`/`data-avatar-url` (present/blank).
- `app_core/app/frontend/inventories/__tests__/useInventoryProfiles.test.js`
  (new) — success map, empty-list no-fetch, failure → `{}`, refetch on
  id-change.
- `.../InventoryCard.test.jsx` — flat-delta hiding; profile nickname +
  `<img>`; `steam_id` + letter fallback.
- `.../InventoriesIndex.test.jsx` — both-URL fetch harness, profile merge,
  new `Items, high to low` label.
- `.../InventoryDetail.test.jsx` — profile-prop rendering + no-profile
  fallback.

Commands actually executed:

- `docker compose run --rm -e RAILS_ENV=test app_fetcher bundle exec rspec`
  (targeted files, then the full suite)
- `docker compose run --rm -e RAILS_ENV=test app_core bundle exec rspec`
  (targeted files, then the full suite)
- `docker compose run --rm -e RAILS_ENV=test app_fetcher bundle exec srb tc`
  / `app_core … srb tc`
- `docker compose run --rm -e RAILS_ENV=test app_fetcher bundle exec rubocop …`
  / `app_core … rubocop …`
- `npm test`, `npm run lint`, `npm run format:check`, `npm run format`
  (from `app_core`, local `node_modules`)

## Verification

- `app_fetcher` full suite: **392 examples, 0 failures** (the previously
  noted pre-existing `UserInventoryCache` failure is no longer present in
  this environment).
- `app_core` full suite: **50 examples, 0 failures**.
- `srb tc`: **"No errors!"** for both apps.
- RuboCop on every changed Ruby file: **no offenses** (both apps).
- Frontend: `npm test` **42 files, 255 tests, all passing**;
  `npm run lint` **0 errors** (1 pre-existing `TrackedItems.jsx` warning,
  untouched); `npm run format:check` **"All matched files use Prettier
  code style!"** (the `InventoriesIndex.jsx` `fix_me.md` entry is now
  removed).
- No browser-level manual check (no live Steam-login data in this
  environment); the rendering branches are covered by component tests,
  and the CSS height is a fixed explicit value rather than a
  font-dependent match.

## Deviations

- **`spec/queries/inventory_catalog_query_spec.rb` was updated too** — it
  wasn't listed in the plan's files but had query-level tests for the two
  removed sort values (surfaced by the full-suite run). Same scope,
  required for the suite to stay green.
- **The enrichment hook maps `avatar_url`→`avatarUrl`** (not the plan's
  raw pass-through), matching `useInventoryCatalog`'s snake→camel mapping
  convention for an island's own data shape.
- **Control height is `36px`** rather than the plan's assumed `34px` —
  chosen to keep the search input's current height and grow only the sort
  button.

## Remaining Issues

- The historical plan docs `agent/plans/public-inventory-endpoints.md`
  and `agent/plans/inventories-pages-frontend.md` still describe the old
  four-valued sort set. Left as historical records (per the established
  pattern) rather than rewritten; this plan documents the change.
- External callers still sending `recently_synced`/`change_24h_desc` now
  get `400` — accepted (the UI was the only known caller).
