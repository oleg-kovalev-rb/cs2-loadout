---
status: implemented
app: fetcher
goal: Replace the placeholder demo item pool with a curated 40–50 item CS2 set that carries real Steam icon URLs and make demo:seed_items store them
created: 2026-10-20
---

# Development Plan

## Goal

Turn the placeholder demo pool from `agent/plans/demo-account.md` into a
curated set of 40–50 real, marketable CS2 items, each with
`market_hash_name`, `rarity`, `category`, and a real Steam CDN `icon_url`,
and make `demo:seed_items` persist that icon metadata so the demo
dashboard, demo inventory card, and demo inventory detail render item
artwork instead of placeholders.

## Expected Behavior

### Curated pool

- `app_fetcher/config/demo_items.yml` contains 40–50 unique entries.
- Every entry has:
  - a real CS2 `market_hash_name`, including the wear suffix for skins
    (for example `AK-47 | Redline (Field-Tested)`);
  - a `rarity` label accepted by `RarityTier.for` (`Consumer Grade`,
    `Industrial Grade`, `Mil-Spec Grade`, `Restricted`, `Classified`,
    `Covert`, `Extraordinary`, or `Contraband`);
  - a `category` matching the Steam inventory Type tag
    (`Rifle`, `Sniper Rifle`, `Pistol`, `SMG`, `Shotgun`, `Machinegun`,
    `Knife`, `Gloves`);
  - a full Steam CDN `icon_url` in the same
    `https://community.akamai.steamstatic.com/economy/image/...` form
    the inventory sync already stores.
- The pool is a deliberate mix:
  - every category above is represented;
  - every rarity tier is represented (including at least one
    `Consumer Grade`, `Industrial Grade`, and `Mil-Spec Grade`);
  - it contains inexpensive skins, mid-tier skins, knives, and gloves so
    a seeded demo can produce both realistic and aspirational
    inventories.
- `Demo::ItemPool.entries` and `.market_hash_names` keep their current
  return shapes; no new loader API is required.

### Seeding

- `demo:seed_items` passes each entry’s `icon_url` to `ItemParser`.
- A new pool item stores the parsed metadata, including the icon URL, as
  today.
- An existing item that was created earlier without pool metadata (for
  example by an inventory sync) gets missing metadata filled in from the
  pool entry:
  - a missing/blank `icon_url`, `rarity`, or `category` is backfilled;
  - a non-nil existing value is never overwritten;
  - the task stays idempotent and does not create duplicate rows.
- `PriceUpdateWorker` is still enqueued once per pool item after the
  item is created or updated.
- Seeded items remain ordinary marketable catalog rows; nothing is
  demo-flagged and no demo inventory/value-log rows are written.

### Demo rendering

- `Demo::Dataset` selection behavior is unchanged: it still samples up
  to 20 priced pool items deterministically by seed and falls back to
  other priced marketable items when needed.
- Because seeded items now carry `icon_url`, the existing dashboard
  item rows, demo inventory card, and demo inventory detail show their
  icons through the existing `icon_url` serialization path.
- An item that already had a custom icon keeps that icon after seeding.

### Unchanged

- `Api::Demo::` endpoints, auth, response shapes, and fallback logic.
- `Demo::Dataset` generation and the 20-item cap.
- The price-overview pipeline, `PriceUpdateWorker`, and caches.
- The demo session, cookie, and token behavior in `app_core`.
- Public catalog/Tracked Items behavior other than the seeded items
  being ordinary catalog rows, as before.

## Scope

### In Scope

- Curating `app_fetcher/config/demo_items.yml` to 40–50 real items with
  rarity, category, and real icon URLs.
- Passing `icon_url` through `demo:seed_items`.
- Backfilling only missing metadata on existing pool items during
  seeding (including the icon URL).
- Unit/task spec coverage for the pool contents, icon presence, rarity/
  category validity, icon persistence, backfill, non-overwrite, and
  idempotency.
- Updating the demo API styleguide where it still describes the pool as
  a placeholder.

### Out of Scope

- Fetching icons from Steam at seeding/runtime, or adding a new Steam
  metadata client/parser.
- Changing `Demo::Dataset`, the demo endpoints, React components, or
  `app_core`.
- Re-pricing or re-syncing already existing items beyond enqueueing the
  existing price worker.
- Adding `StatTrak™`/`Souvenir` variants, stickers, cases, agents, or
  other non-skin catalog rows.
- Admin-panel item management or a pool-editing UI.
- Refactoring the old `agent/plans/demo-account.md` plan beyond a short
  note that this follow-up is complete.

## Applicable Styleguides

- `agent/styleguides/fetcher/demo-api.md` — the curated pool contract
  (40–50 entries, required `icon_url`, accepted rarity/category labels),
  the seed task’s icon pass-through and fill-only-missing backfill rule,
  and the offline pool/task spec expectations. This guide was amended
  during `styleguides-check` to replace the placeholder-pool wording.
- `agent/styleguides/fetcher/architecture-layers.md` — keeps
  `demo:seed_items` as the only demo writer with its allowed
  dependencies (`Demo::ItemPool`, `ItemParser`, `Item`,
  `PriceUpdateWorker`) and leaves `Demo::Dataset`/`Api::Demo::`
  read-only.
- `agent/styleguides/rspec-conventions.md` — unit/task spec levels,
  `FactoryBot` data, `Sidekiq::Testing.fake!` for the enqueue
  assertion, and the rule that external HTTP is never exercised in
  these specs.
- `agent/styleguides/fetcher/background-jobs.md` — the seed task keeps
  enqueueing the existing `PriceUpdateWorker` once per item and does not
  move Steam I/O or parsing into the task.
- `agent/styleguides/ci-and-coverage.md` — where the focused and full
  `app_fetcher` test/CI commands run.
- `agent/styleguides/git-commits.md` — the implementation ships as a
  `[Fetcher] Imperative summary` commit with the plan/styleguide update
  included.

## Implementation Approach

Keep the compact existing design: the YAML is still the only source of
the pool, `Demo::ItemPool` still loads it verbatim, and
`demo:seed_items` remains the only writer.

- Curate the YAML by selecting real, marketable base skins/knives/gloves
  and appending the chosen wear to form the exact `market_hash_name`.
  Source the matching Steam CDN `icon_url` for each base item once and
  check it into the YAML, so seeding needs no network call for icons.
- Extend the seed task, not the API/read path:
  - parse the entry with `icon_url: entry["icon_url"]`;
  - on a new row, save the parsed metadata as today;
  - on an existing row, merge the parsed metadata under the existing
    metadata so only missing keys are filled.
- Strengthen the unit specs so the checked-in pool itself is validated:
  size, uniqueness, required keys, accepted rarity labels, accepted
  categories, and an icon URL on every entry. These tests use the real
  YAML and make no network requests.
- Extend the task spec with an icon-bearing entry and an existing item
  that has some metadata but no icon, proving backfill and
  non-overwrite behavior.

### Pool construction notes

- Use the Steam inventory Type tag names in singular form for
  `category` (`Rifle`, `Sniper Rifle`, `Pistol`, `SMG`, `Shotgun`,
  `Machinegun`, `Knife`, `Gloves`) so seeded rows match metadata
  produced by `UserInventorySyncService`.
- Knife and glove names keep the leading `★`, which makes
  `RarityTier.for` count them as Gold; their `rarity` metadata still
  records the real Steam label (`Covert` for knives, `Extraordinary` for
  gloves).
- Include at least one entry from each rarity label the app recognizes,
  with the selection weighted toward popular, commonly priced skins.
- Keep `AK-47 | Redline (Field-Tested)` in the pool because an existing
  `Demo::ItemPool` spec asserts it.

## Files To Modify

### `app_fetcher`

- `app_fetcher/config/demo_items.yml` — replace the five-entry
  placeholder with 40–50 curated entries, each with
  `market_hash_name`, `rarity`, `category`, and `icon_url`; remove the
  “curation is a follow-up” comment. Reason: this is the feature.
- `app_fetcher/lib/tasks/demo.rake` — pass `entry["icon_url"]` into
  `ItemParser.parse`; merge parsed metadata into existing rows so only
  missing keys are filled; keep the find-or-initialize and
  `PriceUpdateWorker` flow. Reason: icons must reach persisted items
  without clobbering real metadata.
- `app_fetcher/spec/queries/demo/item_pool_spec.rb` — replace the
  “placeholder” assertions with pool-contract assertions: 40–50
  entries, unique names, required keys, every entry has an icon URL,
  rarity labels are accepted by `RarityTier`, and categories are in the
  known set. Keep the `AK-47 | Redline` market-hash-name assertion.
- `app_fetcher/spec/lib/tasks/demo_spec.rb` — add icon-bearing fixtures
  and cover: new item stores the icon, existing item with missing
  metadata is backfilled, existing non-nil metadata is preserved,
  repeated runs do not duplicate rows, and price updates are enqueued
  per item.

### Documentation

- `agent/styleguides/fetcher/demo-api.md` — replace the “placeholder
  pool/curation follow-up” statements with the curated-pool contract
  (40–50 entries, required `icon_url`, Steam CDN format), the seed
  task’s icon pass-through, and the “fill only missing metadata”
  backfill rule.
- `agent/plans/demo-account.md` — under Remaining Issues, mark the
  curated pool/icon follow-up as completed by this plan (one-line note;
  do not rewrite the historical plan).

## Files To Create

- `agent/plans/demo-item-pool.md` — this plan (already created).

No new application files are expected: the YAML, loader, task, and
serializer path already exist.

## Test Plan

### `app_fetcher` unit specs

`spec/queries/demo/item_pool_spec.rb`:

- The real YAML loads and contains between 40 and 50 entries.
- `market_hash_names` are unique and include
  `AK-47 | Redline (Field-Tested)`.
- Every entry has non-blank `market_hash_name`, `rarity`, `category`,
  and `icon_url`.
- Every `icon_url` starts with
  `https://community.akamai.steamstatic.com/economy/image/`.
- Every `rarity` value resolves through `RarityTier.for` for its item
  name (so knifes/gloves resolve via their `★` prefix and every other
  label is one of the recognized Steam labels).
- Every `category` is in the known Steam Type set.

These are offline tests over the checked-in YAML.

### `app_fetcher` task specs

`spec/lib/tasks/demo_spec.rb`:

- A new pool entry with `icon_url` creates one item whose
  `metadata["icon_url"]` equals the YAML value.
- An existing item with `icon_url: nil` and no `rarity`/`category` gets
  those values backfilled from the pool entry.
- An existing item with a custom `icon_url` and metadata keeps its
  values; the task does not overwrite them.
- A second invocation does not change `Item.count`.
- `PriceUpdateWorker` receives one job per pool entry on each run (or
  the existing assertion’s equivalent), with `Sidekiq::Testing.fake!`.

### Regression coverage

- Existing `Demo::Dataset` specs remain untouched and must pass; the
  pool size change does not affect their stubbed pool.
- Existing demo request specs remain untouched and must pass; item
  payloads now legitimately include `icon_url`.
- `ItemParser` specs remain untouched; the parser already accepts
  `icon_url`.

## Implementation Steps

1. **Curate the pool.** Replace `config/demo_items.yml` with 40–50 real
   marketable CS2 entries. For each base item, choose a wear, build the
   exact `market_hash_name`, map the Steam Type tag to the singular
   `category` set, copy the recognized `rarity` label, and add the
   corresponding Steam CDN `icon_url`. Keep the pool mix described
   above and keep `AK-47 | Redline (Field-Tested)`.
2. **Pass icons through seeding.** In `lib/tasks/demo.rake`, add
   `icon_url: entry["icon_url"]` to the `ItemParser.parse` call.
3. **Backfill only missing metadata.** For an existing item, merge the
   parsed metadata under the stored metadata so absent/nil keys are
   filled and non-nil values are preserved; save only when the merged
   hash changes. Keep the new-record path and the price enqueue
   unchanged. Do not change the find-or-initialize key.
4. **Validate the checked-in pool in specs.** Rewrite the item-pool spec
   to assert size, uniqueness, keys, icon prefix, recognized rarities,
   and known categories against the real YAML.
5. **Cover the seed behavior.** Extend the task spec for icon
   persistence, missing-metadata backfill, non-overwrite, idempotency,
   and price enqueueing.
6. **Update documentation.** Amend the demo API styleguide’s pool/
   seeding rules and add the completion note to
   `agent/plans/demo-account.md`.
7. **Run verification.** Run the focused specs, then the full
   `app_fetcher` suite and `app_fetcher/bin/ci`. Update this plan’s
   frontmatter to `implemented` when the checks pass.

## Verification

- `docker compose run --rm app_fetcher bundle exec rspec
  spec/queries/demo/item_pool_spec.rb spec/lib/tasks/demo_spec.rb`
  — focused specs pass.
- `docker compose run --rm app_fetcher bundle exec rspec` — full suite
  passes.
- `docker compose run --rm app_fetcher bin/ci` — RuboCop, Sorbet,
  Brakeman, bundler-audit, and RSpec pass.
- Manual sanity check:
  - inspect the YAML: 40–50 entries, unique names, no blank icon URLs;
  - run `bin/rails demo:seed_items` against a dev database and confirm
    the seeded `Item` rows have `metadata["icon_url"]` set;
  - rerun it and confirm no duplicate rows and no overwritten custom
    metadata;
  - start a demo and confirm the dashboard and `/demo/inventory` show
    item artwork for seeded items.
- No new environment variables, migrations, gems, or network calls in
  tests or at seed time.

## Risks

- **Incorrect market hash names.** A typo or a wear suffix that Steam
  does not list makes `PriceUpdateWorker` mark the item unavailable and
  the demo falls back to other priced items. Curate from a canonical
  CS2 skin dataset and double-check wear suffixes; keep the pool large
  enough that a few misses do not empty the demo.
- **Icon URL correctness.** Steam CDN image hashes are opaque. A wrong
  hash renders a broken image. Validate every URL is on the expected
  CDN host and, as a manual check, open a sample in a browser; do not
  add a runtime network fetch just to validate.
- **Icon URL drift.** Steam can rehost images. The URLs are static
  metadata like the existing inventory-sync icons; a future change can
  refresh them without changing the schema.
- **Backfill overwriting user data.** Seeding runs on a shared catalog.
  Merge only absent/nil keys, preserve existing `false` values, and
  test the non-overwrite path explicitly.
- **Pool-size test brittleness.** A hard 40–50 assertion is intentional
  (it mirrors the feature requirement), but keep the curated set at a
  stable 40–50 and update the test only when intentionally changing the
  pool size.
- **Rarity/category mismatch.** `RarityTier.for` returns `nil` for
  labels like `"Rare"` or `"★"` categories; the pool contract test
  catches this before seeding.
- **Price coverage.** Seeding only enqueues price updates. A fresh
  environment may still show fewer than 20 priced items until workers
  run; this is the existing fallback behavior, not a regression.
- **YAML size.** Forty-five long icon URLs make the file noticeably
  larger; keep one entry per block and no shared anchors so
  `YAML.safe_load_file(aliases: false)` keeps working.

## Assumptions

- “Полный пул” means 40–50 real marketable CS2 skins/knives/gloves, not
  the full Steam catalog and not cases/stickers/agents.
- Real icon metadata means a checked-in
  `https://community.akamai.steamstatic.com/economy/image/...` URL per
  item, matching what `UserInventorySyncService` already stores. No
  runtime Steam metadata fetching is desired.
- The curated list may be sourced offline from a public CS2 skin
  dataset, but the repository stores only the resulting static YAML.
- Categories use Steam’s singular inventory Type labels, consistent
  with `ItemParser`/inventory-sync output; no UI depends on plural
  labels.
- Existing items keep their current metadata when it is already
  populated; the task only fills gaps.
- The demo still samples 20 items from the enlarged pool; the pool does
  not need to be exactly 20 items or map one-to-one to a demo
  inventory.

## Completion Criteria

- `config/demo_items.yml` holds 40–50 unique, real, marketable CS2
  entries with valid rarity labels, Steam Type categories, and Steam CDN
  icon URLs.
- `demo:seed_items` stores icons on new items and backfills missing
  metadata on existing items without overwriting populated values.
- The checked-in pool and the seed behavior are covered by offline
  specs, and the full `app_fetcher` suite/CI passes.
- The demo API styleguide no longer describes the pool as a
  placeholder, and the old demo-account plan records that this
  follow-up is done.
- No new runtime network dependency, migration, gem, or environment
  variable is introduced.
- This plan is marked `status: implemented` after verification.

# Implementation Summary

## Implemented

- Replaced the five-entry placeholder `app_fetcher/config/demo_items.yml`
  with 48 curated real CS2 entries: skins, knives, and gloves spanning
  all eight Steam inventory Type categories and every `RarityTier`
  label (Consumer through Covert, plus Contraband and Extraordinary).
- Every entry carries a checked-in Steam CDN `icon_url`; all 48 URLs
  were HEAD-checked and returned `200`.
- `demo:seed_items` now passes `icon_url` into `ItemParser`.
- On an existing item, the task merges parsed metadata under the stored
  metadata: absent/nil `icon_url`, `rarity`, and `category` are
  backfilled, populated values are preserved, and the row is saved only
  when the merged hash changes.
- Kept find-or-initialize, `PriceUpdateWorker` enqueue, and idempotency
  behavior unchanged.
- Updated `agent/styleguides/fetcher/demo-api.md` with the curated-pool
  contract, icon format, backfill rule, and offline test expectations.
- Noted the completed follow-up in `agent/plans/demo-account.md`.

## Tests

Added/changed:

- `app_fetcher/spec/queries/demo/item_pool_spec.rb` — pool size,
  uniqueness, required keys, Steam CDN icon prefix, `RarityTier`
  coverage, known categories, and name-list parity.
- `app_fetcher/spec/lib/tasks/demo_spec.rb` — new-item icon persistence,
  missing-metadata backfill, populated-metadata non-overwrite, price
  enqueue, and idempotency.

Commands executed:

- `docker compose run --rm app_fetcher bundle exec rspec spec/queries/demo/item_pool_spec.rb spec/lib/tasks/demo_spec.rb` — 11 examples, 0 failures.
- `docker compose run --rm app_fetcher bundle exec rspec` — 539 examples, 0 failures.
- `docker compose run --rm app_fetcher bin/ci` — passed: setup, RuboCop
  (194 files, no offenses), Sorbet (no errors), bundler-audit (no
  vulnerabilities), Brakeman (no warnings), RSpec (539 examples, 0
  failures), and seed replant.

## Verification

- The checked-in YAML parses with 48 unique names and the full category/
  rarity spread.
- All 48 icon URLs were HEAD-requested from the Steam CDN and returned
  `200`.
- The full `app_fetcher` CI suite passes.

## Deviations

None. The pool landed at 48 entries within the planned 40–50 range.

## Remaining Issues

- The dev-database `demo:seed_items` run and final browser check were
  not performed against the live stack to avoid enqueueing real Steam
  price jobs; the task spec exercises the same code path.
- Demo price coverage still depends on `PriceUpdateWorker` running after
  seeding, as before; unpriced pool items fall back to other priced
  catalog items.
