---
status: implemented
app: fetcher+core
goal: Classify Steam's Extraordinary and Contraband rarities into the Gold tier so gloves/Howl stop disappearing from rarity breakdowns
created: 2026-10-19
---

# Development Plan

## Goal

Make `RarityTier.for_item` recognize Steam's `"Extraordinary"` (gloves)
and `"Contraband"` (M4A4 | Howl) rarity strings, mapping both to the
existing `Gold` tier, so items carrying those tags are counted in
`rarity_breakdown` and `rarity_mix_percent` instead of silently becoming
`nil`. Keep the frontend rarity palettes in sync with that grouping.

## Expected Behavior

- `RarityTier.for_item` returns `RarityTier::Gold` for an item whose raw
  `metadata["rarity"]` is `"Extraordinary"`, even when its
  `market_hash_name` has no `★` prefix.
- `RarityTier.for_item` returns `RarityTier::Gold` for an item whose raw
  `metadata["rarity"]` is `"Contraband"`.
- Existing behavior is unchanged: a `★`-prefixed `market_hash_name` is
  still `Gold` regardless of its raw rarity; the six existing grade
  mappings still resolve to their matching tiers; an unrecognized/missing
  rarity with no `★` prefix still returns `nil`.
- `rarity_breakdown` still contains exactly the same 7 tiers in the same
  order (`gold`, `covert`, `classified`, `restricted`, `mil_spec`,
  `industrial`, `consumer`). There is no new API key and no contract
  change: Extraordinary/Contraband items simply increment the existing
  `gold` count and participate in the percentage denominator.
- On the `tracked_items` frontend, `rarityColor("Extraordinary")` and
  `rarityColor("Contraband")` return the same gold color used by the
  inventories UI (`#e4ae39`) instead of the neutral fallback. Unknown
  rarities still fall back to the neutral color.
- On the `inventories` frontend, the 7-tier list remains unchanged; its
  comment documents that `gold` is the bucket for `★` items,
  `"Extraordinary"` gloves, and `"Contraband"` items.

## Scope

### In Scope

- Ruby classification table in `RarityTier`.
- RSpec unit coverage for the two new raw-rarity mappings.
- One database-backed query regression proving both raw rarities end up
  in the Gold bucket (so they are no longer excluded from the
  serializers' percentages).
- `app_core` tracked-items rarity color map and its Vitest coverage.
- `app_core` inventories rarity-tier comment (no structural change).

### Out of Scope

- A separate `contraband` tier or any new API key/tier. Per the product
  decision, Contraband folds into Gold.
- Changing the `★ Gold` label or the 7-tier API/UI contract.
- Mapping knives to gold in `tracked_items/utils/format.js` — that
  helper only receives the raw `rarity` string, not
  `market_hash_name`, so a knife's raw `"Covert"` tag still renders
  Covert there. (The inventories API already buckets it as Gold.)
- Backfilling/re-syncing existing `Item` rows: classification happens at
  read time in the queries, so stored `metadata.rarity` values do not
  need to change.
- Any change to the historical `agent/plans/public-inventory-endpoints.md`
  record.

## Implementation Approach

`RarityTier.for_item` already has a single `case item.rarity` table.
Add one combined branch for the two Steam tags that the product decision
groups into Gold:

```ruby
when "Extraordinary", "Contraband" then Gold
```

The `★`-prefix guard stays first, so it still overrides raw rarity. No
enum values, query code, or serializer code changes are needed: both
queries fold through `RarityTier.for_item`, and both serializers iterate
`RarityTier.values`, so the Gold bucket automatically appears in their
existing `gold` key.

On the frontend, `tracked_items/utils/format.js` maps raw Steam rarity
strings to colors. Add `'Extraordinary'` and `'Contraband'` entries
pointing at the same gold hex already used by
`inventories/styles/inventories.css` (`#e4ae39`), and update the
comment that currently claims there is no gold handling there.
`inventories/utils/rarity.js` keeps its 7 entries; only its comment is
updated to explain that the `gold` bucket also covers
Extraordinary/Contraband.

## Files To Modify

- `app_fetcher/app/models/rarity_tier.rb` — add
  `when "Extraordinary", "Contraband" then Gold` to the rarity `case`.
  Reason: both currently fall through to `nil`, excluding the item from
  rarity counts/percentages.
- `app_fetcher/spec/models/rarity_tier_spec.rb` — extend the mapping
  example with `"Extraordinary" => RarityTier::Gold` and
  `"Contraband" => RarityTier::Gold` (using a non-`★` item name so the
  raw tag alone is what drives the result). Reason: pin the new
  classification and guard against regression.
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb` — add a
  regression example creating one `"Extraordinary"` item and one
  `"Contraband"` item in the same inventory and asserting
  `page.rarity_counts == { RarityTier::Gold => 2 }`. Reason: the reported
  bug is about these items disappearing from the query output that feeds
  both serializers.
- `app_core/app/frontend/tracked_items/utils/format.js` — add
  `'Extraordinary'` and `'Contraband'` to `RARITY_COLORS`, both
  `#e4ae39`; update the explanatory comment. Reason: keep tracked-item
  dots consistent with the Gold bucket used by the inventories UI.
- `app_core/app/frontend/tracked_items/__tests__/format.test.js` — add
  both rarities to the `test.each` color table and change the
  fallback test to use a genuinely unknown rarity (e.g. `"High Grade"`)
  instead of `"Contraband"`. Reason: existing test asserts the old,
  now-wrong neutral fallback for Contraband.
- `app_core/app/frontend/inventories/utils/rarity.js` — update only the
  header comment to state that `gold` also covers Steam's
  `"Extraordinary"` and `"Contraband"` tags. Reason: keep the two
  frontend rarity definitions conceptually synchronized without adding an
  8th tier.

## Files To Create

None.

## Applicable Styleguides

- `agent/styleguides/ruby-sorbet.md` — constrains the `RarityTier` edit:
  keep the file `# typed: strict`, keep the existing `sig`, and use a
  plain `case` branch (no new runtime checks or untyped helpers).
- `agent/styleguides/rspec-conventions.md` — constrains test placement:
  `RarityTier` mapping coverage stays in its unit spec; the DB-backed
  Gold-count regression belongs in the existing query unit spec; no
  request-spec changes since the HTTP contract does not change.
- `agent/styleguides/fetcher/list-query-objects.md` — constrains the
  query/serializer boundary: classification stays in `RarityTier` as
  called by the query objects; serializers remain pure and keep
  iterating `RarityTier.values` (still exactly 7 keys).
- `agent/styleguides/core/react-dashboard.md` — constrains the frontend
  edits: color/rarity mapping stays a pure function in `utils/`, is
  covered by a dedicated no-render Vitest unit test with explicit
  `vitest` imports, and reuses the existing gold color/token rather than
  introducing a new palette or an 8th UI tier.
- `agent/styleguides/fix_me.md` — checked; none of the files this plan
  touches are currently listed as known deviations, so no entry needs to
  be fixed or removed as part of this change.

## Test Plan

- **`app_fetcher/spec/models/rarity_tier_spec.rb` (unit):** every raw
  mapping, now including Extraordinary and Contraband → Gold;
  `★`-prefix precedence; unknown/missing rarity → `nil` remain covered.
- **`app_fetcher/spec/queries/inventory_detail_query_spec.rb` (unit,
  real DB):** a regression example asserting an inventory containing
  one Extraordinary and one Contraband item produces a single
  `RarityTier::Gold => 2` count, proving they no longer get dropped
  before `rarity_breakdown`.
- **`app_core/app/frontend/tracked_items/__tests__/format.test.js`
  (Vitest):** both new raw strings map to `#e4ae39`; an unknown rarity
  and `undefined` still fall back to `#8791ab`.
- **`app_core/app/frontend/inventories/__tests__/rarity.test.js`:** no
  assertion change needed — the 7-tier shape is intentionally unchanged.
  Run it to confirm the comment-only file edit didn't disturb anything.
- Existing serializer/request specs already assert the exact 7-key
  contract; they should continue to pass unchanged, proving no API
  contract change.

## Implementation Steps

1. Add the Extraordinary/Contraband → Gold branch in
   `app_fetcher/app/models/rarity_tier.rb`.
2. Extend `app_fetcher/spec/models/rarity_tier_spec.rb` with the two
   mapping cases, following TDD: run it red before step 1's behavior is
   present, then green.
3. Add the Extraordinary/Contraband Gold-count regression to
   `app_fetcher/spec/queries/inventory_detail_query_spec.rb`.
4. Add the two color entries and update the comment in
   `app_core/app/frontend/tracked_items/utils/format.js`.
5. Update `app_core/app/frontend/tracked_items/__tests__/format.test.js`
   (new expected colors, new unknown-rarity fixture for the fallback).
6. Update the comment in
   `app_core/app/frontend/inventories/utils/rarity.js`.
7. Run the focused Ruby and Vitest suites, then the full app suites and
   linters per Verification.

## Verification

- `app_fetcher`: focused
  `bundle exec rspec spec/models/rarity_tier_spec.rb
  spec/queries/inventory_detail_query_spec.rb`, then the full
  `bin/ci` (or at minimum `bundle exec rspec`, `bin/rubocop`,
  `bundle exec srb tc`).
- `app_core`: focused
  `npm run test -- app/frontend/tracked_items/__tests__/format.test.js
  app/frontend/inventories/__tests__/rarity.test.js` (or the project's
  equivalent), then the full `bin/ci` (`npm run lint`,
  `npm run format:check`, `npm run test:coverage`, RSpec).
- Confirm serializer/request specs still expect exactly 7 rarity keys
  and pass without modification.
- Manual sanity check (optional): call
  `RarityTier.for_item` with an `Extraordinary` glove name without `★`
  and a `Contraband` Howl, and with a `★`-prefixed name, confirming all
  return `Gold`.

## Risks

- Real inventory data may use localized rarity labels rather than the
  English strings (`InventoryData#rarity_tag` reads
  `localized_tag_name`). If a user's Steam client returns a localized
  value, these mappings won't match; that is a pre-existing limitation
  for all six existing tags too, not introduced here.
- Contraband items will render under the `★ Gold` label in the
  inventories legend. This is the accepted product trade-off of folding
  Contraband into Gold rather than adding an 8th tier/API key.
- `tracked_items` still shows knives as Covert because that helper gets
  only the raw rarity string. This plan deliberately does not change its
  input shape; if knife-gold display there is wanted later, it needs a
  separate change.

## Assumptions

- Steam's glove rarity tag is exactly `"Extraordinary"` and the Howl's
  is exactly `"Contraband"` (as stated in the bug report; not present in
  current specs or fixtures).
- Folding Contraband into Gold is the product decision (confirmed by the
  user), so no new `contraband` API key or frontend tier is expected.

## Completion Criteria

- Both raw tags classify to `Gold` and are counted by the inventory
  queries/serializers.
- The public inventories API still exposes exactly 7 rarity keys.
- Tracked-items colors show both tags in gold rather than neutral.
- Focused and full app test/lint verification passes, or any unrelated
  pre-existing failures are explicitly identified.

# Implementation Summary

## Implemented

- `app_fetcher/app/models/rarity_tier.rb` — added one combined
  `when "Extraordinary", "Contraband" then Gold` branch to the existing
  raw-rarity `case`. The `★`-prefix guard is unchanged and still takes
  precedence.
- `app_fetcher/spec/models/rarity_tier_spec.rb` — extended the raw-rarity
  mapping table with Extraordinary and Contraband → Gold.
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb` — added a
  real-DB regression proving a glove (`Extraordinary`) and a Howl
  (`Contraband`) in one inventory count as `RarityTier::Gold => 2`
  instead of disappearing.
- `app_core/app/frontend/tracked_items/utils/format.js` — mapped both raw
  strings to the existing gold hex `#e4ae39` and corrected the comment
  that previously claimed there was no gold handling in this helper.
- `app_core/app/frontend/tracked_items/__tests__/format.test.js` — added
  both expected gold mappings; changed the neutral-fallback fixture to an
  actually unknown rarity (`High Grade`).
- `app_core/app/frontend/inventories/utils/rarity.js` — comment-only
  update documenting that the existing `gold` key is the bucket for
  `★` items, Extraordinary gloves, and Contraband items. The 7-tier
  structure is intentionally unchanged.

No enum value, query, serializer, controller, or API-contract change was
needed. `rarity_breakdown` / `rarity_mix_percent` still expose exactly
the same 7 keys.

## Tests

TDD red→green was followed for both sides:

- Ruby unit/query specs: red first (`2 failures`: both new raw tags
  returned `nil`; the inventory Gold count was `{}`), then green.
- Vitest color spec: red first (`2 failures`: both new tags returned the
  neutral fallback), then green.

Commands actually executed inside the project's Docker Compose services:

- `bundle exec rspec spec/models/rarity_tier_spec.rb
  spec/queries/inventory_detail_query_spec.rb` — 22 examples, 0 failures
  (after being red before the implementation).
- `npm run test -- app/frontend/tracked_items/__tests__/format.test.js
  app/frontend/inventories/__tests__/rarity.test.js` — 14 tests passed
  (after being red before the implementation).
- `bundle exec rspec` (full `app_fetcher` suite) — 390 examples,
  0 failures.
- `npm run test` (full `app_core` Vitest suite) — 41 files, 248 tests
  passed.
- `bundle exec rubocop app/models/rarity_tier.rb
  spec/models/rarity_tier_spec.rb spec/queries/inventory_detail_query_spec.rb`
  — 3 files inspected, no offenses.
- `bundle exec srb tc` — `No errors! Great job.`
- `npm run lint` — 0 errors, 1 pre-existing
  `react-hooks/exhaustive-deps` warning in
  `tracked_items/TrackedItems.jsx` (untouched by this change).
- `npm run format:check` — all matched files use Prettier code style.

## Verification

- Focused and full Ruby suites are green; the new regression fails on the
  old classifier and passes on the new one.
- Full frontend suite is green; the new color assertions fail on the old
  map and pass on the new one.
- The public inventories API shape is unchanged (existing
  serializer/request specs expecting exactly 7 rarity keys still pass).
- Final diff is limited to the six planned files plus this plan.

## Deviations

None. Implementation matched the plan.

## Remaining Issues

None introduced by this change. The one ESLint warning
(`tracked_items/TrackedItems.jsx`) is pre-existing and unrelated.
