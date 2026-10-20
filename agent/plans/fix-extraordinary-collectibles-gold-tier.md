---
status: implemented
app: fetcher+core
goal: Stop counting Steam "Extraordinary" collectibles/stickers as ★ Gold in inventory rarity breakdowns
created: 2026-10-20
---

# Development Plan

## Goal

Make the `★ Gold` rarity bucket contain only items that are actually
special-tier inventory items — `★`-prefixed knives/gloves and
`"Contraband"` items (M4A4 | Howl) — instead of every item whose raw
Steam rarity tag happens to be `"Extraordinary"`. Steam uses
`"Extraordinary"` for collectibles (service medals, coins, badges) and
stickers as well, so those currently inflate the Gold percentage.

## Expected Behavior

- An item whose raw rarity is `"Extraordinary"` but whose
  `market_hash_name` has no `★` prefix is **not** classified as
  `RarityTier::Gold`; it is excluded from the rarity breakdown
  (`nil`), the same as before the Extraordinary mapping was added.
  This covers `Collectible` medals/coins/badges and `Extraordinary`
  stickers.
- A `★`-prefixed item (knife or glove) is still `Gold` regardless of
  its raw rarity, including gloves whose raw rarity is
  `"Extraordinary"`.
- An item with raw rarity `"Contraband"` (M4A4 | Howl) stays in the
  `Gold` bucket, preserving the product decision from
  `agent/plans/fix-rarity-tier-extraordinary-contraband.md`.
- The API still exposes exactly the same 7 rarity keys in the same
  order; percentages continue to be computed against the recognized
  (non-nil) item count only. Items excluded as `nil` (consumer/stock/
  base-grade/exotic/high-grade/remarkable, and now collectible/
  sticker `"Extraordinary"`) do not participate in the denominator,
  exactly as before the previous change.
- For the reported `fnt` inventory specifically, the 16 `Extraordinary`
  collectibles no longer contribute `16/40 = 40%` to the Gold bucket;
  that inventory's Gold percentage becomes 0% because it has no
  `★` or `Contraband` items.
- The inventories frontend comment stops claiming that the `gold`
  bucket covers `"Extraordinary"` gloves as a raw-rarity rule; it
  documents `★` items and `"Contraband"` instead.
- The tracked-items raw-rarity color map is unchanged: Steam's
  `"Extraordinary"` rarity still renders in the gold rarity color
  there, because that helper colors a raw Steam rarity string and is
  not the inventory-tier bucketing logic.

## Scope

### In Scope

- `RarityTier` classification rule for raw `"Extraordinary"`.
- Ruby unit/query specs that currently pin `"Extraordinary"` → Gold.
- The inventories frontend documentation comment that describes the
  Gold bucket (and its stale `RarityTier.for_item` reference).
- A regression test using a realistic collectible/medal name proving it
  is not counted as Gold.

### Out of Scope

- Any change to the public API contract (still 7 tiers).
- Reclassifying Contraband or `★`-prefixed items.
- Changing the tracked-items raw-rarity color map or its tests.
- Re-syncing/backfilling stored `Item` metadata: classification happens
  at read time, so no data migration is needed.
- Editing the historical
  `agent/plans/fix-rarity-tier-extraordinary-contraband.md` record.
- Introducing a separate `collectible`/`sticker` tier.

## Implementation Approach

`RarityTier.for` currently has this precedence:

1. `★`-prefix → `Gold`;
2. raw `"Extraordinary"`/`"Contraband"` → `Gold`;
3. the six weapon-grade strings → their matching tiers;
4. everything else → `nil`.

Steam gloves/knives always carry the `★` prefix in
`market_hash_name`, so rule 1 already covers every real glove and
knife, including gloves whose raw rarity is `"Extraordinary"`. Rule 2's
`"Extraordinary"` half therefore only catches items that are *not*
gold-tier inventory items (collectibles, stickers) and is the reported
bug. Remove `"Extraordinary"` from rule 2, keeping `"Contraband"`:

```ruby
when "Contraband" then Gold
```

No query, serializer, or API-shape change is needed: both
`RarityBreakdownQuery` and `Demo::Dataset` funnel through
`RarityTier.for`, and `RarityBreakdownSerializer` keeps iterating
`RarityTier.values`.

Update the frontend's inventories rarity comment to match the new rule
and to reference the actual method name (`RarityTier.for`, not the
stale `RarityTier.for_item`).

## Files To Modify

- `app_fetcher/app/models/rarity_tier.rb` — remove the
  `"Extraordinary"` case arm, keep `"Contraband"`, and add a short
  comment explaining that raw `"Extraordinary"` is shared by
  collectibles/stickers and is therefore covered by the `★` prefix,
  not by raw rarity. Reason: root-cause fix.
- `app_fetcher/spec/models/rarity_tier_spec.rb` — change the mapping
  table so `"Extraordinary"` is no longer expected to be `Gold`; add
  an explicit example that a realistic `"Extraordinary"` collectible
  name without `★` returns `nil`, while a `★` glove with
  `"Extraordinary"` still returns `Gold`. Reason: pin the corrected
  precedence.
- `app_fetcher/spec/queries/rarity_breakdown_query_spec.rb` — update
  the existing Gold-mapping example to create a `★` item, a
  `"Contraband"` item, and an `"Extraordinary"` collectible, asserting
  `Gold => 2` and that the collectible is omitted. Reason: prove the
  query no longer counts collectibles.
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb` — replace
  the current "counts Extraordinary and Contraband rarities under Gold"
  regression with one that counts a `★` knife, a `"Contraband"` Howl,
  and an `"Extraordinary"` collectible, asserting `Gold => 2`. Reason:
  the reported bug flows through this query.
- `app_core/app/frontend/inventories/utils/rarity.js` — comment-only
  update: `gold` is the bucket for `★` items and `"Contraband"`; raw
  `"Extraordinary"` collectibles/stickers are not counted; point at
  `RarityTier.for`. Reason: keep the UI legend documentation truthful.

## Files To Create

None.

## Applicable Styleguides

- `agent/styleguides/ruby-sorbet.md` — constrains the `RarityTier` edit:
  keep `# typed: strict`, keep the existing `sig`, and use a plain
  `case` arm; no runtime checks for statically known values.
- `agent/styleguides/rspec-conventions.md` — constrains test placement
  and data setup: `RarityTier` mapping stays in its unit spec, the
  DB-backed count regressions stay in the existing query unit specs,
  and new records use FactoryBot rather than fixtures.
- `agent/styleguides/fetcher/list-query-objects.md` — constrains the
  query/serializer boundary: classification stays in `RarityTier` as
  called by `RarityBreakdownQuery`; serializers remain pure and keep
  iterating `RarityTier.values` (still exactly 7 keys).
- `agent/styleguides/core/react-dashboard.md` — constrains the
  comment-only frontend edit: no palette/behavior change, no new CSS
  token or component.
- `agent/styleguides/fix_me.md` — checked; none of the files this plan
  touches is currently listed as a known deviation.

## Test Plan

- **`app_fetcher/spec/models/rarity_tier_spec.rb` (unit):** all six
  weapon-grade mappings, `"Contraband"` → Gold, `"Extraordinary"`
  collectible without `★` → `nil`, `★` glove with `"Extraordinary"` →
  Gold, `★` knife with `"Covert"` → Gold, unknown/missing → `nil`.
- **`app_fetcher/spec/queries/rarity_breakdown_query_spec.rb` (unit,
  real DB):** one `★` item + one `"Contraband"` item + one
  `"Extraordinary"` collectible in the same inventory yields
  `RarityTier::Gold => 2`; the existing cross-inventory isolation and
  empty-input examples stay green.
- **`app_fetcher/spec/queries/inventory_detail_query_spec.rb` (unit,
  real DB):** the detail query carries the same corrected counts, so the
  serializer path gets the fixed numbers.
- **`app_core/app/frontend/inventories/__tests__/rarity.test.js`:** no
  assertion change expected (7-tier shape is unchanged); run it to
  confirm the comment-only edit did not disturb anything.
- Existing serializer/request specs expecting exactly 7 rarity keys
  must pass unchanged.

## Implementation Steps

1. Write the failing Ruby examples first: update the `RarityTier`
   mapping table, add the collectible-vs-`★`-glove precedence example,
   and update the two query regressions to expect `Gold => 2` with an
   `"Extraordinary"` collectible present. Run them red.
2. Remove the `"Extraordinary"` arm from `RarityTier.for` and add the
   explanatory comment. Run the focused Ruby specs green.
3. Update the inventories frontend comment in
   `app/frontend/inventories/utils/rarity.js` (`RarityTier.for`).
4. Run the focused Vitest rarity spec, then the full verification
   below.
5. Manually recompute the `fnt` inventory breakdown against the running
   development database (read-only) to confirm Gold drops from 40% to
   0% and the other tier percentages become relative to 24 classified
   items instead of 40.

## Verification

- `app_fetcher`: focused `bundle exec rspec
  spec/models/rarity_tier_spec.rb
  spec/queries/rarity_breakdown_query_spec.rb
  spec/queries/inventory_detail_query_spec.rb`, then full
  `bundle exec rspec`, `bin/rubocop`, `bundle exec srb tc`.
- `app_core`: focused `npm run test -- 
  app/frontend/inventories/__tests__/rarity.test.js`, then
  `npm run lint`, `npm run format:check`, and the full Vitest suite.
- Read-only DB check against `app_fetcher_development`: query the `fnt`
  inventory (`steam_id` `76561198425050957`) grouped by
  `metadata->>'rarity'`/`category`, and confirm the 16
  `Extraordinary`/`Collectible` rows are excluded from the Gold count.
- Confirm the public inventories API still returns exactly 7 rarity
  keys.

## Risks

- Removing the raw-`"Extraordinary"` mapping relies on Steam always
  prefixing glove/knife `market_hash_name`s with `★`. This is the
  canonical Steam naming convention and the existing `★` rule already
  depends on it; no real non-`★` glove has been observed.
- The tracked-items raw-rarity color map keeps `"Extraordinary"` gold.
  That is intentional (it colors the raw Steam rarity, not the
  inventory tier), but it is a deliberate inconsistency worth noting.
- Users who saw collectibles previously counted as Gold will see the
  Gold percentage drop and other percentages rise because the
  denominator shrinks; this is the correct pre-regression behavior.

## Assumptions

- Steam's `market_hash_name` for gloves/knives always starts with
  `★`, so the `★` guard fully replaces the `"Extraordinary"` arm for
  real gold-tier items.
- The product decision to fold `"Contraband"` into Gold still holds.
- Collectibles/stickers should stay out of the rarity denominator
  rather than receiving their own tier, matching the behavior before
  the Extraordinary mapping was introduced.

## Completion Criteria

- Raw `"Extraordinary"` without `★` is not counted as Gold anywhere.
- `★` items and `"Contraband"` remain Gold.
- The 7-tier API shape is unchanged.
- Focused and full verification passes, and the `fnt` breakdown no
  longer reports a false Gold percentage.

# Implementation Summary

## Implemented

- `app_fetcher/app/models/rarity_tier.rb` — removed the raw
  `"Extraordinary"` case arm; only `"Contraband"` still maps to `Gold`
  by rarity. Added a comment explaining that Steam also tags
  collectibles/stickers `"Extraordinary"`, while gold-tier
  gloves/knives are covered by the `★` prefix.
- `app_fetcher/spec/models/rarity_tier_spec.rb` — dropped
  `"Extraordinary"` from the raw-rarity mapping table, added a
  regression that an `"Extraordinary"` collectible without `★` is
  unclassified, and a regression that a `★` glove with
  `"Extraordinary"` is still `Gold`.
- `app_fetcher/spec/queries/rarity_breakdown_query_spec.rb` — the Gold
  regression now contains a `★` item, a `"Contraband"` item, an
  `"Extraordinary"` collectible, and an unknown rarity; it expects
  `Gold => 2`.
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb` — same
  corrected regression through the detail query (star-prefixed glove +
  Howl = Gold 2; collectible excluded).
- `app_core/app/frontend/inventories/utils/rarity.js` — comment-only
  update: the `gold` bucket is `★` + `"Contraband"`; raw
  `"Extraordinary"` collectibles/stickers are not counted. Also fixed
  the stale `RarityTier.for_item` reference to `RarityTier.for`.

## Tests

TDD red→green was followed:

- Ruby focused specs were red first (`3 failures`: collectible returned
  `Gold`; both query regressions returned `Gold => 3`), then green.
- Focused command:
  `bundle exec rspec spec/models/rarity_tier_spec.rb
  spec/queries/rarity_breakdown_query_spec.rb
  spec/queries/inventory_detail_query_spec.rb`
  — 32 examples, 0 failures.
- Full `app_fetcher` suite: `bundle exec rspec` — 534 examples,
  0 failures.
- Frontend focused: `npm run test -- 
  app/frontend/inventories/__tests__/rarity.test.js` — 4 tests passed.
- Full frontend suite: `npm run test` — 53 files, 320 tests passed.

## Verification

- `bundle exec rubocop` — 194 files inspected, no offenses.
- `bundle exec srb tc` — `No errors! Great job.`
- `npm run lint` — 0 errors, 1 pre-existing
  `react-hooks/exhaustive-deps` warning in
  `tracked_items/TrackedItems.jsx` (untouched by this change).
- `npm run format:check` — all matched files use Prettier code style.
- Read-only `rails runner` against `app_fetcher_development` for the
  reported `fnt` inventory (`steam_id` `76561198425050957`):
  `counts={"industrial"=>7, "consumer"=>15, "mil_spec"=>1,
  "classified"=>1}`; serialized breakdown has no `gold` row with a
  positive count (consumer 62.5%, industrial 29.2%, classified 4.2%,
  mil_spec 4.2%). The false 40% Gold is gone.

## Deviations

None from the plan. The test-suite counts differ from the older
`fix-rarity-tier-extraordinary-contraband.md` record because the current
branch has more examples (534 vs. the 390 noted there); no tests were
removed to make the count change.

## Remaining Issues

- The tracked-items raw-rarity color map still renders the raw Steam
  `"Extraordinary"` string as gold. This is intentional: that helper
  colors a raw rarity tag, not the inventory `★ Gold` bucket, and it is
  unaffected by this bug. If a collectible ever appears in tracked
  items, its dot will be gold by raw Steam rarity, which is the correct
  Steam display color.
- No data migration/backfill is needed because classification is
  computed at read time.
