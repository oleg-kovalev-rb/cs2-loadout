---
status: implemented
app: fetcher+core
goal: Ingest each item's Steam icon URL and render it in the dashboard's item rows
created: 2026-10-05
---

# Development Plan

## Goal

Carry each Steam item's icon through the existing ingestion pipeline (`app_fetcher`), expose it over the internal API, and render it in `app_core`'s React dashboard `ItemRow`.

## Expected Behavior

- Normal: when `UserInventorySyncService` backfills a new `Item` from a Steam inventory sync, the item's icon URL (sourced from the same `descriptions` entry already used for `market_hash_name`) is stored alongside the other parsed metadata and returned by `GET /api/v1/inventories/me` inside `metadata.icon_url`. The dashboard renders a small icon next to the item's name in `ItemRow`.
- Edge case — icon missing from Steam's response: `metadata.icon_url` is `nil`; `ItemRow` renders without an `<img>` (no broken-image icon, no layout break).
- Edge case — pre-existing `Item` rows created before this change: their `metadata.icon_url` is simply absent (same as any other missing jsonb key) until the item is re-synced; no backfill migration is performed (see Scope — the local DB reset makes this moot for this task).
- Unchanged: every other field already on `Item#metadata` (`weapon_type`, `item_name`, `condition`, `stattrak`, `souvenir`), the parsing logic that derives them, and the overall `InventoriesController#show`/`#refresh` → `UserInventorySyncService` → `Item.upsert_all` flow.

## Scope

### In Scope

- `Steam::Response::Data::InventoryData`: a new derived method that reshapes its own `descriptions` into a `market_hash_name → icon_url` lookup.
- `Item`: a new `icon_url` key in `metadata`, via `store_accessor`.
- `UserInventorySyncService`: merge the icon lookup into each newly-parsed item's `metadata` before `upsert_all`.
- `app_core`'s `useDashboardData.mapItem` and `ItemRow`: map and render `iconUrl`.
- Tests for all of the above.
- Resetting the local `app_fetcher` dev DB (`db:drop db:create db:migrate`) after the `Item`/metadata shape is finalized, so existing unsynced rows don't linger with a stale shape — explicitly confirmed acceptable by the project owner since nothing is deployed.

### Out of Scope

- `ItemParser` (text-only parsing of `market_hash_name`) — untouched; icon data never comes from that string.
- Any new `ItemBuilder` class — not needed, no new layer introduced.
- Fixing the stale `Steam::` namespace references in `agent/styleguides/fetcher/*.md`, `fix_me.md`, and `agent/plans/*.md` (found during research — commit `2a41f20` already dropped the namespace in code, docs were never updated). Flagged for `styleguides-check`, not fixed here.
- Deciding, as part of this plan, whether to migrate `inventories_spec.rb` off hand-written `WebMock` onto VCR — this file is already flagged in `fix_me.md` as deviating from `rspec-conventions.md`'s "request specs use a VCR cassette" rule, with the note "migrate the next time either file is otherwise touched." This plan does touch it, so that evaluation belongs to `implement-plan` (per `CLAUDE.md`'s fix_me.md process: fix inline and remove the entry only if the fix is small and within the styleguide already being followed for this change), not a decision pre-made here.
- A dedicated `IconUrlData`/sub-DTO class — one small derived method on the existing `InventoryData` DTO is enough; introducing a new class for one lookup method would be speculative.
- Backfilling icon URLs for any `Item` row that survives past this task (moot: DB reset handles it this time, but if a future similar case arises without a DB reset available, that's a separate, later decision).

## Implementation Approach

The icon URL is sibling data to `market_hash_name` inside each Steam `descriptions` entry — it is not derived *from* `market_hash_name` text, so it does not belong in `ItemParser` (which only transforms the name string). Instead:

1. `InventoryData` (the DTO that already owns reshaping its own raw `descriptions` field, per `market_hash_names`) gets one more derived method, `icon_urls_by_name`, returning `T::Hash[String, T.nilable(String)]` keyed by `market_hash_name`. This keeps the DTO's existing responsibility ("derived read methods that only reshape the DTO's own fields live on the DTO itself" — `steam-response-objects.md`) and requires no change to `ItemParser`'s signature or `architecture-layers.md`'s parser contract.
2. `UserInventorySyncService#call` resolves this lookup once per sync (`response.data.icon_urls_by_name`) and merges `icon_url` into each missing item's `metadata` hash, after `ItemParser.parse` but before `Item.upsert_all`. This is a small addition to the orchestration the service already does (resolve known vs. missing, parse, persist) — it already owns exactly this kind of "combine two pieces of resolved data before upsert" step, so no new layer or class is needed.
3. `Item#metadata` gains `icon_url` as a sixth `store_accessor` key, matching how every existing metadata field is exposed. No schema migration — `metadata` is already `jsonb`.
4. `Api::V1::InventoriesController#render_inventory` needs **no change** — `as_json(only: [:market_hash_name, :metadata])` already serializes the full `metadata` hash, so `icon_url` flows through automatically once it's on the model.
5. `app_core`'s `useDashboardData.mapItem` adds `iconUrl: metadata.icon_url` to its mapped shape (same pattern as every other field already mapped there).
6. `ItemRow` renders `item.iconUrl` as an `<img>` immediately before the `.mover-name` span, conditionally (`{item.iconUrl && <img .../>}`) so a missing icon renders nothing rather than a broken-image glyph. A new BEM-ish CSS class (e.g. `.mover-icon`) is added to `dashboard.css` alongside the existing `.mover-*` classes, sized consistent with the row's existing visual rhythm (small square icon, e.g. 32×32).

This is the smallest change that satisfies the requirement: one new DTO method, one new `store_accessor` key, a small merge step in an existing service, and additive-only changes in `app_core` — no new files, no new architectural layer, no controller change.

## Files To Modify

- `app_fetcher/lib/steam/response/data/inventory_data.rb` — add `icon_urls_by_name` (`sig { returns(T::Hash[String, T.nilable(String)]) }`), built the same defensive way as `market_hash_names` (`desc["market_hash_name"]`, `desc["icon_url"]`, skipping entries with no name). Reason: the DTO owns reshaping its own raw fields; this is the Steam-knowledge boundary.
- `app_fetcher/app/models/item.rb` — add `:icon_url` to the existing `store_accessor :metadata, ...` line. Reason: matches the established pattern for every other item attribute; no migration needed.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — after computing `missing_attrs`, resolve `icon_by_name = response.data.icon_urls_by_name` and set `attrs[:metadata][:icon_url] = icon_by_name[attrs[:market_hash_name]]` for each of `missing_attrs` before the `Item.upsert_all` call. Reason: this is the one place that already combines parsed data with the Steam response before persisting; keeps `ItemParser` untouched.
- `app_fetcher/app/parsers/item_parser.rb` — update `ItemDto`'s `metadata` type alias to include `icon_url: T.nilable(String)` so Sorbet's static shape for the hash the service builds stays accurate (the key is added by the service, not by `.parse`, but the type alias describes the full shape `Item.upsert_all` receives). Reason: keep the Sorbet type alias truthful; no behavior change to `.parse` itself.
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js` — add `iconUrl: metadata.icon_url` inside `mapItem`'s returned object. Reason: same mapping pattern as every other field.
- `app_core/app/frontend/dashboard/components/ItemRow.jsx` — add a conditional `<img className="mover-icon" src={item.iconUrl} alt="" />` before the `.mover-id` span's name/tags content. Reason: the only place item rows are rendered; `alt=""` since the adjacent text already names the item (avoids redundant screen-reader announcement).
- `app_core/app/frontend/dashboard/styles/dashboard.css` — add a `.mover-icon` rule (fixed small square size, matches row height) near the existing `.mover-*`/`.avatar*` rules. Reason: new visual element needs sizing; follows the file's existing BEM-ish naming.

## Files To Create

None. Every change fits an existing file/layer — no new parser, builder, service, component, or utility is warranted for one additional field.

## Test Plan

- `app_fetcher/spec/lib/steam/response/data/inventory_data_spec.rb` — add a `describe "#icon_urls_by_name"` block: returns the expected `{name => icon_url}` map for multiple descriptions; a description missing `icon_url` maps to `nil`; a description missing `market_hash_name` is skipped (mirrors the defensive style already used for `.from_hash`/`market_hash_names`).
- `app_fetcher/spec/services/user_inventory_sync_service_spec.rb` — extend the existing "mix of known and unknown names" case (or add a sibling case) so the stubbed Steam response's `descriptions` include an `icon_url`, and assert the backfilled `Item`'s `metadata["icon_url"]` matches it; add a case where `icon_url` is absent from the description and assert the item is still created with `metadata["icon_url"]` nil (not an error). Any new test data goes through `FactoryBot`, per `rspec-conventions.md`.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — extend one existing stubbed response to include `icon_url` in its `descriptions` entry and assert the JSON response's `items[0]["metadata"]["icon_url"]` matches. Build any new test data via `FactoryBot` (`create(:item, ...)`), not by adding reliance on the legacy `items.yml` fixture rows this file also still uses. Whether to migrate this file's `WebMock` stub to a VCR cassette per `fix_me.md`'s "next touched" instruction is `implement-plan`'s call, not predetermined here (see Risks).
- `app_core/app/frontend/dashboard/__tests__/useDashboardData.test.js` — add `icon_url` to `INVENTORY_BODY`'s metadata and assert `mapItem`'s output includes the matching `iconUrl`.
- `app_core/app/frontend/dashboard/__tests__/ItemRow.test.jsx` (new test file, component doesn't have one today) — this crosses `react-dashboard.md`'s own "does this branch on data in a way that could be wrong" line (icon present vs. absent is a real conditional that could silently render a broken image or regress layout), unlike the rest of `ItemRow`'s already-tested-indirectly rendering. Two cases: renders an `<img>` with the expected `src` when `item.iconUrl` is set; renders no `<img>` when `item.iconUrl` is `null`/`undefined`.

## Implementation Steps

1. Before writing `icon_urls_by_name`, confirm the real field Steam returns in `descriptions` for CS2 inventory items (`icon_url`, and whether `icon_url_large` exists/is preferred, and whether the value is already an absolute URL or a relative path needing a CDN host prefix). This could not be confirmed live in this session (no outbound network access to `steamcommunity.com` from this environment — a direct check returned HTTP 403). Confirm this one way or another (a real inventory response pulled from a dev machine with network access, or current Steam Web API reference) before finalizing step 2's implementation — this determines whether any URL-prefixing logic is needed at all.
2. Add `Steam::Response::Data::InventoryData#icon_urls_by_name`, plus its spec (`inventory_data_spec.rb`).
3. Add `:icon_url` to `Item`'s `store_accessor` list.
4. Update `ItemParser::ItemDto`'s type alias to include `icon_url: T.nilable(String)` in `metadata`.
5. Update `UserInventorySyncService#call` to merge `icon_url` into each missing item's attrs before `upsert_all`; extend/add its spec cases.
6. Extend `inventories_spec.rb` to assert `icon_url` passes through the API response.
7. Update `useDashboardData.mapItem` to map `iconUrl`; extend its spec.
8. Update `ItemRow` to render the icon conditionally; add `dashboard.css`'s `.mover-icon` rule; add the new `ItemRow.test.jsx`.
9. Reset the local `app_fetcher` dev (and test, if separately seeded) database (`db:drop db:create db:migrate`, then re-seed/re-login to repopulate) now that the `Item`/metadata shape is final — confirmed acceptable since the project isn't deployed.

## Verification

- `app_fetcher`: `bundle exec rspec spec/lib/steam/response/data/inventory_data_spec.rb spec/services/user_inventory_sync_service_spec.rb spec/requests/api/v1/inventories_spec.rb`, then the full `bundle exec rspec` suite for regressions; `srb tc` (Sorbet) for the touched `# typed: strict` files.
- `app_core`: `npx vitest run` (or the project's existing test script) covering `useDashboardData.test.js` and the new `ItemRow.test.jsx`, then the full JS test suite for regressions.
- Manual: reset the local DB, log in, confirm icons render in the dashboard's item rows for a real inventory, and confirm an item with no icon (if any) renders cleanly with no broken-image glyph.

## Risks

- `inventories_spec.rb` is already flagged in `fix_me.md` for a WebMock→VCR migration "the next time [it is] otherwise touched." This plan touches it. Left for `implement-plan` to evaluate (migrate + remove the `fix_me.md` entry if the fix is small and within scope, per `CLAUDE.md`'s process) rather than decided here — don't let the icon feature's own scope silently expand into a VCR/Gemfile migration without that explicit call, but also don't skip it by default just because this plan didn't originally ask for it.
- The Steam field name/shape assumption (`icon_url`, possibly needing a CDN host prefix) is not verified against a live response in this codebase or session (outbound network to `steamcommunity.com` was unavailable here — confirmed 403). Getting this wrong fails silently (every item simply has a `nil` icon), not loudly, so this must be confirmed before or during Step 1/2, not assumed from general Steam API knowledge alone.
- Several styleguides/ADRs/plans (`architecture-layers.md`, `fix_me.md`, `steam-response-objects.md`, `background-jobs.md`, `ruby-sorbet.md`, `rspec-conventions.md`, and multiple `agent/plans/*.md`) still reference the pre-`2a41f20` `Steam::ItemParser`/`Steam::PriceLogBuilder` namespacing and `app/parsers/steam/`/`app/builders/steam/` paths. This plan uses the real, current, flat paths/class names throughout; `styleguides-check` should treat the stale doc references as a known discrepancy, not as the source of truth.
- `Item.upsert_all` writes raw column values, bypassing model callbacks/validations — already true today for the existing metadata fields, so adding `icon_url` to the same hash carries no new risk beyond what's already accepted for this path.

## Assumptions

- Steam's `descriptions` entries carry one icon field (`icon_url`) sufficient for the dashboard's small row-icon use case; a separate `icon_url_large` is not needed for this redesign (no larger/zoomed icon view exists in `ItemRow` today). Revisit if a future larger-icon view is added.
- A single `market_hash_name → icon_url` mapping is sufficient — i.e., Steam does not return meaningfully different icons for different instances of the same `market_hash_name` within one inventory response (no evidence either way in this codebase; `assets`, which could disambiguate per-instance via `classid`/`instanceid`, is unused today and this plan doesn't introduce that join).
- The local `app_fetcher` dev database reset (Scope) is safe and sufficient for repopulating `items` with the new shape, per the project owner's explicit confirmation that nothing is deployed yet.

## Applicable Styleguides

- `agent/styleguides/fetcher/architecture-layers.md` — constrains where the new logic lives: a derived read method on `InventoryData` (not `ItemParser`, not a new builder/service), merged into attrs inside `UserInventorySyncService`, the existing ADR-sanctioned cross-scenario service — consistent with "parsers depend on nothing else" and "don't introduce a layer for a single-Scenario need." Its own canonical-implementation paths (`app/parsers/steam/item_parser.rb`, `Steam::PriceLogBuilder`) are stale relative to the current flat, non-namespaced code (commit `2a41f20` dropped the `Steam::` namespace and `steam/` subdirectory) — the file's *rules* are still current and sufficient; only its illustrative paths are outdated. Not a blocker; this plan uses the real current paths/names throughout.
- `agent/styleguides/fetcher/steam-response-objects.md` — constrains `InventoryData#icon_urls_by_name`: a derived method on the DTO itself (its own SHOULD rule), defensive hash access (`desc["icon_url"]`, tolerating a missing key), no AR/model knowledge inside the DTO.
- `agent/styleguides/ruby-sorbet.md` — constrains typing on every touched file: `# typed: strict`, `extend T::Sig`, a `sig` on the new method, `T::Hash[String, T.nilable(String)]` (correctly a generic hash, not a fixed-key shape type, since the lookup has a dynamic number of keys per inventory), and updating `ItemParser::ItemDto`'s type alias. Same stale-example-path caveat as above (`Steam::ItemParser` naming in its Structure section); its typing rules themselves are current and sufficient.
- `agent/styleguides/fetcher/internal-api-controllers.md` — confirms, without requiring a change: `InventoriesController` already satisfies "don't parse Steam's raw response inside a controller," and its existing `render json: {...}` already passes the full `metadata` hash through, so `icon_url` needs zero controller changes.
- `agent/styleguides/rails-layering.md` — confirms the merge step belongs in the orchestration layer (`UserInventorySyncService`), not the model or controller; the model stays limited to the `store_accessor` addition.
- `agent/styleguides/rspec-conventions.md` — constrains the Test Plan: the new DTO method's unit spec lives at its mirrored path (`spec/lib/steam/response/data/inventory_data_spec.rb`, already exists); any new test data in `inventories_spec.rb`/`user_inventory_sync_service_spec.rb` goes through `FactoryBot`, not the legacy fixtures those files still partly use. Also surfaced the `inventories_spec.rb`/VCR correction captured in Risks above — the plan's original draft incorrectly called that migration "unrelated," which has been fixed.
- `agent/styleguides/fetcher/caching.md` — reviewed, not applicable: no `app/caching/` class or cache behavior is touched; icon backfill for pre-existing `Item` rows is out of scope, and the local DB reset sidesteps staleness for this task.
- `agent/styleguides/core/react-dashboard.md` — constrains `useDashboardData.mapItem`'s added `iconUrl` field (same pattern as every other mapped field), `ItemRow`'s presentational-only conditional render, the new `.mover-icon` CSS rule's BEM-ish naming, and justifies the new `ItemRow.test.jsx` file against this guide's own dividing line for when a component needs a dedicated test ("does this branch on data in a way that could be wrong" — yes, icon-present-vs-absent).
- `agent/styleguides/core/architecture-layers.md` — confirms, without requiring a change: no `app_core` proxy/backend endpoint is added; the dashboard keeps reading `app_fetcher`'s API directly.

## Completion Criteria

- [x] Desired behavior explicit (Expected Behavior)
- [x] Scope explicit (Scope)
- [x] Affected files/components identified (Files To Modify)
- [x] Test strategy defined (Test Plan)
- [x] Implementation steps ordered (Implementation Steps)
- [x] Verification defined (Verification)
- [x] Plan written to `agent/plans/item-icon-url.md`

# Implementation Summary

## Implemented

- `Steam::Response::Data::InventoryData#icon_urls_by_name` (`app_fetcher/lib/steam/response/data/inventory_data.rb`): a new derived method, mirroring `market_hash_names`, that maps each description's `market_hash_name` to its resolved icon URL (`descriptions[].icon_url`, prefixed with Steam's economy-image CDN host, `https://community.akamai.steamstatic.com/economy/image/`). A description with no `icon_url` maps to `nil`; one with no `market_hash_name` is skipped.
- `Item#metadata` (`app_fetcher/app/models/item.rb`): added `:icon_url` to the existing `store_accessor` list — no migration, `metadata` is already `jsonb`.
- `ItemParser::ItemDto` (`app_fetcher/app/parsers/item_parser.rb`): the `metadata` shape type now includes `icon_url: T.nilable(String)`. `ItemParser.parse` itself is unchanged — it still only parses `market_hash_name` text.
- `UserInventorySyncService#call` (`app_fetcher/app/services/user_inventory_sync_service.rb`): resolves `response.data.icon_urls_by_name` once per sync and merges `icon_url` into each newly-parsed item's `metadata` before `Item.upsert_all`.
- `Api::V1::InventoriesController`: no change, as planned — `as_json(only: [:market_hash_name, :metadata])` already passes the new key through.
- `useDashboardData.mapItem` (`app_core/.../hooks/useDashboardData.js`): maps `metadata.icon_url` to `iconUrl`.
- `ItemRow` (`app_core/.../components/ItemRow.jsx`): renders a 32×32 `<img className="mover-icon">` when `item.iconUrl` is present, or an empty placeholder `<span className="mover-icon">` otherwise — **deviation from the plan's literal JSX** (see Deviations).
- `dashboard.css`: added `.mover-icon` (32×32, `object-fit: cover`) and widened `.mover-row`'s grid from `1fr 38px auto` to `32px 1fr 38px auto`.
- `agent/styleguides/fix_me.md`: logged two newly-discovered, pre-existing `srb tc` errors found while touching these files (see Deviations) — documented, not fixed, per the project's process.

## Tests

- `app_fetcher/spec/lib/steam/response/data/inventory_data_spec.rb` — new `#icon_urls_by_name` examples (multiple descriptions, missing `icon_url`, missing `market_hash_name`).
- `app_fetcher/spec/services/user_inventory_sync_service_spec.rb` — two new contexts: icon present on an unknown item → stored on the backfilled `Item`; icon absent → `nil`, not an error.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — new context asserting `icon_url` passes through `GET /api/v1/inventories/me`'s JSON response for a newly-backfilled item.
- `app_core/app/frontend/dashboard/__tests__/useDashboardData.test.js` — extended to assert `iconUrl` mapping.
- `app_core/app/frontend/dashboard/__tests__/ItemRow.test.jsx` (new) — icon renders with the right `src` when present; no `<img>` when absent.

Commands executed:
- `docker compose run --rm app_fetcher bundle exec rspec` (full suite, repeated after each change)
- `docker compose run --rm app_fetcher bundle exec srb tc`
- `docker compose run --rm app_fetcher bundle exec rubocop app/models/item.rb app/parsers/item_parser.rb app/services/user_inventory_sync_service.rb lib/steam/response/data/inventory_data.rb spec/lib/steam/response/data/inventory_data_spec.rb spec/services/user_inventory_sync_service_spec.rb spec/requests/api/v1/inventories_spec.rb`
- `npx vitest run` (app_core, full suite) and targeted runs of the two JS test files during TDD

## Verification

- **app_fetcher RSpec**: 134 examples, 1 failure — `spec/caching/user_inventory_cache_spec.rb:18`. Confirmed pre-existing via `git stash` + re-run against unmodified `main` (identical failure, same file). Not touched; unrelated to this change.
- **app_fetcher Sorbet (`srb tc`)**: baseline (clean `main`) = 97 errors. After this change = 98. Diffed line-by-line against baseline: one new error (`user_inventory_sync_service.rb:29`, `icon_urls_by_name` on nilable `response.data`) — matches an already-existing, unfixed pattern two lines above it in the same method. One pre-existing error's text shifted (`item_parser.rb`'s `item_name` nilable-shape mismatch, present before this change, now reported alongside the new `icon_url` key). Both logged in `fix_me.md`; neither fixed (out of scope, not small/isolated — see Deviations).
- **app_fetcher Rubocop**: 7 files inspected, no offenses.
- **app_core Vitest**: 11 files, 67 examples, all passing (full suite).
- **Manual/visual**: could not complete a real logged-in browser walkthrough — the dashboard requires live Steam OpenID login, and this sandbox has no outbound network access to `steamcommunity.com` (confirmed via a direct curl attempt, HTTP 403). Instead, started the real `app_core` dev server (`preview_start`), confirmed the Vite build compiled the changed CSS/JS with no errors, and injected the actual `ItemRow`-shaped markup (icon present and icon absent) into the live page so the real compiled `dashboard.css` applied. Computed styles confirmed both rows resolve to the identical grid (`32px 159.984px 38px 45.0156px`) and the icon renders at exactly 32×32 with `object-fit: cover` — the grid-misalignment risk described below was verified fixed against the real stylesheet, not just reasoned about.
- **Local DB reset**: `db:drop db:create db:migrate` run against `app_fetcher`'s development database per the plan's confirmed Scope.

## Deviations

- **Icon CDN prefix decided during implementation, not verified live.** The plan flagged (Risks) that Steam's real field name/shape couldn't be confirmed in this session — a live check against `steamcommunity.com` returned HTTP 403 (no outbound network access from this sandbox), both during planning and re-attempted during implementation. Proceeded with `icon_url` plus the standard Steam economy-image CDN host (`https://community.akamai.steamstatic.com/economy/image/`) as the implementation, per the plan's own allowance to use "current Steam Web API reference" as an alternative to a live response. **This still needs confirmation against a real inventory sync** — flagged again below under Remaining Issues.
- **`ItemRow`'s icon placement, changed from the plan's literal JSX.** The plan said to render the `<img>` "before the `.mover-id` span," conditionally, with nothing rendered when absent. Implementing that literally (`{item.iconUrl && <img .../>}` as a `.mover-row` grid child) would have broken the row's CSS Grid layout: `.mover-row` has exactly 3 children today, auto-placed into a 3-column grid (`1fr 38px auto`); omitting the icon `<img>` for any item without one would shift every other child into the wrong column for that row only, misaligning it against rows that do have an icon — directly violating the plan's own "no layout break" requirement. Fixed by always rendering a same-sized element in that slot (the real `<img>` when `iconUrl` is present, an empty `<span className="mover-icon">` placeholder otherwise) and widening the grid to 4 explicit columns. Verified against the real compiled CSS in a running browser (see Verification) — both states resolve to an identical grid.
- **`inventories_spec.rb` not migrated to VCR.** The plan explicitly left this as implement-plan's call (it's flagged in `fix_me.md` as due for migration "next touched," and this change touches the file). Decided against migrating: it requires adding a new dependency (`vcr` isn't in the Gemfile yet) and recording a cassette from a real Steam response, which needs exactly the live network access this sandbox doesn't have — not a "small, within-scope" fix per `CLAUDE.md`'s own fix_me.md process, and adding a dependency without explicit approval is outside this skill's scope. Left the existing `fix_me.md` entry as-is.
- **Two newly-discovered, pre-existing Sorbet errors documented in `fix_me.md` instead of fixed**, surfaced only because this change touched the same lines: `item_parser.rb`'s `item_name` nilable-shape mismatch in `.parse`'s `else` branch, and `user_inventory_sync_service.rb`'s un-narrowed `response.data` across all three of its call sites (two pre-existing, one new from this change, left consistent with the other two rather than fixed in isolation). Root causes are unrelated to icon support and not small enough to fold into this change.
- **Unintended side effect caught and corrected during implementation**: running `db:drop db:create db:migrate` for the development database also recreated the `cache` sub-database (same `db:create`/`db:drop` multi-db step), but `db:migrate` only targets the primary DB — there's no `db/cache_migrate/` directory in this repo (the `solid_cache_entries` table was never backed by a committed migration, only by its schema dump). This left `cache_schema.rb` dumped as empty (version 0) and would have silently broken `Rails.cache` locally. Caught via `git status` showing an unexpected modified file, restored `cache_schema.rb` from git, and ran `db:schema:load:cache` instead to correctly recreate `solid_cache_entries` from the existing schema file. Verified via `SolidCache::Entry.count` (0, as expected post-reset) and a clean `git diff` on the schema file.
- **Post-commit review: `ItemParser.parse` now takes `icon_url:` directly, instead of the service mutating its result afterward.** The original implementation (justified at the time against `architecture-layers.md`/`steam-response-objects.md`) kept `ItemParser.parse`'s signature untouched and had `UserInventorySyncService` reach into the returned hash (`attrs[:metadata][:icon_url] = icon_by_name[name]`) to bolt the resolved icon on afterward. Code review called this out as an inconsistent special case versus every other metadata field, which `.parse` builds directly. Changed `.parse` to `def self.parse(market_hash_name, icon_url: nil)`, included in both branches' `metadata:` hash literal alongside `stattrak:`/`souvenir:`/etc. (Ruby 3.1 shorthand, same as its siblings), and the service now calls `ItemParser.parse(name, icon_url: icon_by_name[name])` directly — no post-hoc mutation. Still a parser in the `architecture-layers.md` sense (pure, stateless, string-in/DTO-out, no AR/IO) — accepting one more plain value doesn't change that. Added two new unit specs (`item_parser_spec.rb`) for the parameter's presence/default; existing service/request specs needed no changes (same observable behavior). Two code comments (on `ItemRow.test.jsx`'s `alt=""` rationale and `InventoryData`'s CDN-host rationale) were also removed per review feedback.

## Remaining Issues

- ~~Confirm the real Steam field shape...~~ **Resolved**: confirmed against a real, live-logged-in dashboard — `icon_url` plus the `community.akamai.steamstatic.com` prefix is correct; icons render properly for real inventory items.
- `spec/caching/user_inventory_cache_spec.rb:18` remains failing on `main`, pre-existing and unrelated — not logged in `fix_me.md` yet since it's outside this change's touched files; worth a separate look.
- The two newly-logged `fix_me.md` entries (`item_parser.rb` item_name nilability, `user_inventory_sync_service.rb` un-narrowed `response.data`) are documented but unresolved — next person to touch either file should check `fix_me.md` first per the project's process.
