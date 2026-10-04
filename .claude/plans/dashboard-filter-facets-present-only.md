---
status: implemented
app: core
goal: Fix the blank Weapon filter chip and make the Condition/Special filter facets only show options actually present in the signed-in user's inventory
created: 2026-10-04
---

## Applicable Styleguides

- **`.claude/styleguides/core/react-dashboard.md`** — governs the whole
  plan. Its "Derived Data: `utils/`" section directly specifies the
  shape the three new functions must have: plain data in/out, null/
  empty-safe by construction (not by a caller guard), dedicated unit
  tests with no rendering — exactly what `weaponTypesPresent`/
  `conditionsPresent`/`stattrakPresent` are planned as. Its "Testing"
  section's "what gets a dedicated test file" rule confirms no new
  `FilterDropdown`/`ItemsTile` component test is needed here, since the
  only new branching (`showStattrak &&`) is a plain boolean already
  proven correct at the unit level, not component-owned logic.
- **`.claude/styleguides/git-commits.md`** — commit format for the
  eventual change (`[Core] Imperative summary`).

Confirmed during this check: `fix_me.md` has no entry for `ItemsTile.jsx`,
`weaponTypes`, or `FilterDropdown.jsx` — the plan's move of the inline
`weaponTypes` computation into `utils/filters.js` is a voluntary
convention fix made because the file is already being touched, not a
logged deviation being closed out.

Note (non-blocking, carried over from the prior plan's styleguide-check):
`react-dashboard.md`'s "Derived Data" section still lists `marketVolume.js`
as a canonical example, which no longer exists (deleted in the
`dashboard-single-page-polish` plan). Still just a stale illustrative
reference, not a sufficiency problem — this check is not the place to
edit the styleguide itself.

# Development Plan

## Goal

Fix a blank chip in the dashboard's Weapon filter (caused by items with no
`weaponType`), and extend the same "derive from what the user actually
owns" principle to the Condition and Special (StatTrak) filter facets,
which currently show a fixed/full vocabulary regardless of inventory
contents.

## Expected Behavior

### Normal behavior

- The Weapon filter chip row never contains a blank/empty-label chip,
  regardless of how many inventory items lack a `weaponType` (knives,
  gloves, stickers, cases, agents).
- The Condition filter chip row shows only the wear conditions that at
  least one item in the current inventory actually has, in their
  existing canonical wear order (Factory New → Battle-Scarred) — not
  every condition that theoretically exists in CS2.
- The "Special" filter group (today just the StatTrak™ chip) does not
  render at all if the current inventory contains zero StatTrak items.
- Toggling any of these chips, clearing filters, and the active-filter
  count badge all keep working exactly as today — none of this changes
  how filtering/sorting/pagination behaves, only which chips are offered.

### Edge cases

- Empty inventory (`items === []`): all three facets resolve to
  "nothing to show" (empty weapon/condition chip rows, no Special
  group) without throwing.
- An item with `condition: undefined` (stickers/cases/agents) must not
  produce a blank Condition chip, mirroring the Weapon fix.
- An inventory with at least one StatTrak item must still show the
  Special group exactly as today.

### Must remain unchanged

- `ItemRow.jsx`'s per-row condition tag (which already renders blank for
  a conditionless item via `conditionAbbr(undefined)`) — a separate,
  pre-existing, unrequested issue found during research; not touched.
- `reducer.js` — no changes; `activeFilterCount`, `FILTERS_CLEARED`, and
  the toggle actions are already generic `Set` operations with no
  dependency on a fixed condition vocabulary.
- Filtering/sorting behavior (`applyFilters`/`applySort`) — unchanged.

## Scope

### In Scope

1. Fix `weaponTypes` to exclude falsy values before dedup/sort.
2. Add `conditionsPresent(items)` and `stattrakPresent(items)` derivations,
   both null/empty-safe, `conditionsPresent` preserving `CONDITIONS`'s
   canonical wear order.
3. Move all three facet derivations (weapon, condition, stattrak) out of
   `ItemsTile.jsx`'s inline `useMemo` into `utils/filters.js` as pure
   functions, consistent with `react-dashboard.md`'s "Derived Data:
   utils/" rule — the existing inline `weaponTypes` `useMemo` is itself a
   pre-existing deviation from that rule; fixing it while adding two
   siblings in the same inconsistent inline style would just compound
   the deviation.
4. `FilterDropdown.jsx` receives `conditions`/`showStattrak` as props
   instead of importing the fixed `CONDITIONS` array and unconditionally
   rendering the Special group.
5. Prop-drill the two new computed values through `ItemsToolbar.jsx` the
   same way `weaponTypes` already flows today.

### Out of Scope

- `ItemRow.jsx`'s blank condition tag for conditionless items.
- Any change to `applyFilters`/`applySort`, `reducer.js`, or the
  filter-toggle/clear actions.
- Any change to how `CONDITIONS`'s wear order itself is defined — it
  stays exported from `utils/filters.js` as the canonical order; it
  just stops being imported directly into `FilterDropdown.jsx`.
- Visual/CSS changes to the filter chips themselves.

## Implementation Approach

`utils/filters.js` gains three exported pure functions sitting next to
`applyFilters`/`applySort`:

- `weaponTypesPresent(items)` — `[...new Set(items.map(i => i.weaponType))].filter(Boolean).sort()`.
- `conditionsPresent(items)` — intersect `CONDITIONS` (in its existing
  order) with the Set of conditions actually present in `items`, instead
  of collecting-then-sorting arbitrary values — this is what keeps the
  canonical wear order regardless of inventory composition, and is
  naturally null-safe (a value not in `CONDITIONS` or undefined is
  simply never included, no explicit falsy filter needed).
- `stattrakPresent(items)` — `items.some(i => i.stattrak)`.

All three take the same plain `items` array shape already used by
`applyFilters`, return plain data, and require no React/JSX.

`ItemsTile.jsx` drops its inline `weaponTypes` `useMemo` and instead
calls the three new functions (still memoized the same way, to avoid
recomputing on every render) via one `useMemo` with the same `[items]`
dependency, passing the three results down through `ItemsToolbar` to
`FilterDropdown` alongside the existing `filters`/toggle-callback props.

`FilterDropdown.jsx` replaces its `CONDITIONS` import with a `conditions`
prop (mapped the same way `weaponTypes` already is) and wraps the
existing "Special" `filter-group` block in a conditional on a new
`showStattrak` prop — when false, that whole group (label + chip-row),
not just the chip, is omitted, matching how the Weapon/Condition groups
already naturally render an empty `chip-row` with nothing inside when
their array is empty (no explicit empty-state needed there, but Special
has no "chip-row with nothing in it" equivalent since it's a single
fixed chip, so it needs an explicit conditional instead).

## Files To Modify

- `app_core/app/frontend/dashboard/utils/filters.js` — add
  `weaponTypesPresent`, `conditionsPresent`, `stattrakPresent`.
- `app_core/app/frontend/dashboard/components/ItemsTile.jsx` — replace
  the inline `weaponTypes` `useMemo` with calls to the three new
  `utils/filters.js` functions; pass `conditions`/`showStattrak` down to
  `ItemsToolbar` alongside the existing `weaponTypes` prop.
- `app_core/app/frontend/dashboard/components/ItemsToolbar.jsx` — accept
  and forward `conditions`/`showStattrak` props to `FilterDropdown`,
  same pattern as `weaponTypes`.
- `app_core/app/frontend/dashboard/components/FilterDropdown.jsx` —
  drop the `CONDITIONS` import; accept `conditions`/`showStattrak` props;
  render the Condition chip row from the `conditions` prop; wrap the
  Special `filter-group` in `{showStattrak && (...)}`.
- `app_core/app/frontend/dashboard/__tests__/filters.test.js` — add
  tests for the three new functions.

## Files To Create

None.

## Test Plan

All new coverage lives in `filters.test.js`, following its existing
plain-fixture/direct-call pattern (no rendering):

- `weaponTypesPresent`: empty items → `[]`; items with a mix of real and
  falsy (`undefined`/`null`/`''`) weaponType → falsy values excluded,
  real ones deduped and alphabetically sorted (regression test for the
  reported bug).
- `conditionsPresent`: empty items → `[]`; items whose conditions are a
  strict subset of `CONDITIONS` → result matches `CONDITIONS`'s relative
  order, not insertion/alphabetical order (construct the fixture so a
  naive sort would visibly disagree, e.g. items present in
  `['Battle-Scarred', 'Factory New']` input order but expected output
  `['Factory New', 'Battle-Scarred']`); items with a falsy `condition` →
  excluded, no blank entry.
- `stattrakPresent`: empty items → `false`; items with zero stattrak →
  `false`; items with at least one stattrak → `true`.

No new `FilterDropdown`/`ItemsTile` component test: the "hide Special
when empty" branch is a one-line prop-gated conditional with no data
transformation of its own — by the time `showStattrak` reaches
`FilterDropdown` it's already a plain boolean proven correct by
`stattrakPresent`'s own unit tests, so there's no additional branching
logic in the component itself worth isolating, consistent with
`react-dashboard.md`'s testing line for presentational leaf components.

## Implementation Steps

1. Add `weaponTypesPresent`, `conditionsPresent`, `stattrakPresent` to
   `utils/filters.js`, with their unit tests in `filters.test.js` first
   (RED), then the implementations (GREEN).
2. Update `ItemsTile.jsx` to use the three new functions instead of its
   inline `weaponTypes` `useMemo`, passing all three down.
3. Update `ItemsToolbar.jsx` to forward the two new props.
4. Update `FilterDropdown.jsx` to consume `conditions`/`showStattrak`
   props instead of the `CONDITIONS` import, and conditionally render
   the Special group.
5. Run the full JS suite and fix any fallout.

## Verification

- `npm test` (full vitest suite).
- Manual check in a browser (same approach as the prior plan, since a
  real Steam login isn't available in this environment): confirm no
  blank chip appears in Weapon, Condition only lists conditions present,
  Special group disappears entirely when no StatTrak item exists and
  reappears when one does.

## Risks

- `conditionsPresent`'s order-preservation only matters if a future
  inventory has conditions in a different insertion order than
  `CONDITIONS` itself — the test fixture must actually exercise an
  out-of-canonical-order input to catch a regression here, a check that
  is easy to accidentally write in a way that passes regardless of
  implementation (e.g. a fixture already in canonical order would pass
  with a naive `.sort()` too) — call this out explicitly when writing
  the test, not just add any passing fixture.
- None of the three new functions are covered by a render-level test, so
  a wiring mistake in the prop-drilling chain (`ItemsTile` →
  `ItemsToolbar` → `FilterDropdown`) wouldn't be caught by
  `filters.test.js` alone; the manual browser check is the only
  safety net for that specific mistake class, consistent with how
  `weaponTypes`'s existing wiring has never had a dedicated test either.

## Assumptions

None — every open question from the research was resolved by reading
the actual code rather than asking the user.

# Implementation Summary

## Implemented

- `utils/filters.js`: added `weaponTypesPresent(items)`,
  `conditionsPresent(items)`, `stattrakPresent(items)` — three pure,
  null/empty-safe functions next to `applyFilters`/`applySort`.
  `conditionsPresent` filters the canonical `CONDITIONS` array down to
  what's present, rather than collecting-then-sorting, so order always
  matches the canonical wear order regardless of inventory composition.
  Updated the stale comment above `CONDITIONS` ("shown in full
  regardless of which conditions are present") to reflect its new role.
- `ItemsTile.jsx`: replaced the inline `weaponTypes` `useMemo` (which had
  the blank-chip bug — no falsy filter before `.sort()`) with one
  `useMemo` calling all three new functions, passing `weaponTypes`/
  `conditions`/`showStattrak` down to `ItemsToolbar`.
- `ItemsToolbar.jsx`: forwards `conditions`/`showStattrak` to
  `FilterDropdown`, same pattern as the existing `weaponTypes`.
- `FilterDropdown.jsx`: dropped the `CONDITIONS` import, renders the
  Condition chip row from the new `conditions` prop, and wraps the
  entire "Special" `filter-group` (not just its chip) in
  `{showStattrak && (...)}` so the group doesn't render at all when the
  inventory has no StatTrak items.

## Tests

- `filters.test.js`: 9 new tests across three new `describe` blocks
  (`weaponTypesPresent`, `conditionsPresent`, `stattrakPresent`),
  covering empty items, falsy-value exclusion (the regression test for
  the reported bug), and — per the plan's own Risk callout —
  `conditionsPresent`'s order-preservation test uses a fixture
  (`Well-Worn, Factory New, Battle-Scarred` insertion order) deliberately
  chosen so canonical order, insertion order, and alphabetical order all
  disagree, so the test can only pass against a real canonical-order
  implementation.
- Written RED-first (confirmed failing with `TypeError: ... is not a
  function` against the pre-change `utils/filters.js`), then GREEN after
  implementation.
- No new component test for `FilterDropdown`/`ItemsTile` — per the plan
  and `react-dashboard.md`'s testing convention, the only new branching
  (`showStattrak &&`) is a plain boolean already proven correct at the
  unit level. The existing `ItemsTile.test.jsx` integration test (which
  mounts the real `ItemsTile → ItemsToolbar → FilterDropdown` tree via a
  real reducer) ran unmodified and still passed, which is itself a real
  end-to-end proof the new prop-threading didn't break anything.

Commands executed: `npm test` (vitest run, full suite, both after the
RED tests and again after full implementation), `bundle exec rspec`
(full `app_core` suite, unaffected since no Ruby files changed), `bundle
exec rubocop app/frontend` (0 files — rubocop doesn't lint JS, included
for completeness per Verification; `app/frontend` has no `.rb` files).

## Verification

- `npm test`: 10 test files, 65 tests, all passing (56 pre-existing + 9
  new).
- `bundle exec rspec`: 6 examples, 0 failures (unaffected, confirms
  nothing in the Rails layer regressed).
- Manual check via the running `app_core` dev server: built a temporary
  static HTML fixture (two scenarios — inventory with a knife-like item
  and no StatTrak items vs. an inventory with a StatTrak item) styled
  with the real `dashboard.css`, to visually confirm no blank chip
  appears and the "Special" group is fully absent (not just its chip)
  rather than leaving an empty label/box — both confirmed via
  screenshot. As with the prior plan, this is hand-authored markup
  representing the expected output, not the live React tree (no real
  Steam login available in this environment) — the actual logic's
  correctness rests on the unit tests and the unmodified, still-passing
  `ItemsTile.test.jsx` integration test. The fixture file was deleted
  after verification; never committed.

## Deviations

None — implementation matched the plan exactly.

## Remaining Issues

None blocking. The same non-blocking `react-dashboard.md` stale-example
note carried over from the prior plan still stands (unrelated to this
change).
