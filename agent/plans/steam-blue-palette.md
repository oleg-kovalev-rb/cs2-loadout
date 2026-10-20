---
status: implemented
app: core
goal: Replace app_core's purple accent palette with the "variant 2" graphite + Steam-blue palette, with the CS2 orange brand mark unified with StatTrak.
created: 2026-10-20
---

# Development Plan — Steam-blue palette (variant 2)

## Goal

Replace the design-token palette in `app_core` from the current navy +
violet system to the approved **variant 2** system:

- graphite chrome (neutral, non-blue surfaces);
- **Steam blue** as the functional accent (buttons, links, active states,
  charts, focus);
- a single **CS2 orange** used for identity (brand mark slash) **and**
  StatTrak, unified into one value.

The result must apply consistently to every island (dashboard, tracked
items, inventories, admin panel) because all of them share
`shared/styles/tokens.css`.

## Expected Behavior

Observable after implementation:

- Page background, surfaces, borders and text use the graphite neutrals.
- `--accent` is Steam blue `#4ea8e0`: it drives focus outlines, chart
  line/area, active period pill, selected row, active chips, filter badge
  background, paginator active button, primary buttons, links.
- Text/icons placed **on** an accent background are dark (`--accent-ink`),
  not white, so they stay readable.
- The brand mark slash (`CS2<span>/</span>LOADOUT`) is the CS2 orange
  `--brand`, and `--stattrak` resolves to the same orange (single value).
- Up/down semantics (green/red) and canonical CS2 rarity colors are
  unchanged.
- No violet `#8368ff` / `rgba(131,104,255,…)` / `#4a3aa8` / `#7256f0`
  literals remain in `app_core/app/frontend`.

### Must remain unchanged

- CS2 rarity colors (`--rarity-*` in `inventories.css`, `RARITY_COLORS`
  in `tracked_items/utils/rarity.js`).
- `--up` / `--down` values and their semantic use.
- Component structure, markup and behavior (no layout or JS changes).

## Scope

### In Scope

- Base token values in `shared/styles/tokens.css`.
- New support tokens: `--brand`, `--brand-soft`, `--accent-ink`,
  `--accent-deep`, `--accent-hover`.
- Replacing hardcoded violet/accent literals in island stylesheets.
- Replacing navy-derived hover borders (`#39435c`).
- Keeping `NEUTRAL_RARITY_COLOR` in sync with the new `--text-muted`.
- Updating the one affected test (`rarity.test.js`).

### Out of Scope

- Adding the `CS2 MARKET` chip (decision: colors only).
- Changing CS2 rarity colors.
- Changing StatTrak to a separate hue (decision: unify with brand).
- Recoloring the yellow `Demo` badge (left as-is; noted as a risk).
- Layout, spacing, typography, radius changes.
- Adding new visual regression tooling.

## Implementation Approach

All surfaces consume CSS custom properties from
`shared/styles/tokens.css` (`:root`). Therefore the core of the change is
a token-block replacement plus removal of the remaining hardcoded legacy
literals that bypassed tokens.

Three small support tokens are introduced to avoid re-introducing
hardcodes:

- `--brand` / `--brand-soft` — the identity orange; `--stattrak` and
  `--stattrak-soft` alias them (`var(--brand)`), so one value drives both.
- `--accent-ink` — the dark foreground used on any accent-filled surface
  (replaces `color: #fff` on bright blue, which fails contrast).
- `--accent-deep` / `--accent-hover` — the avatar gradient end and the
  primary-CTA hover, replacing the last hardcoded purple hexes.

### Target palette

| Token | Old | New |
|---|---|---|
| `--bg` | `#0c111b` | `#0b0c0e` |
| `--surface` | `#141a28` | `#151719` |
| `--surface-raised` | `#1c2334` | `#1d2023` |
| `--surface-sunken` | `#0f1420` | `#0f1012` |
| `--border` | `#262f44` | `#26292e` |
| `--border-soft` | `#1d2537` | `#1c1e22` |
| `--text` | `#edf0f7` | `#eef0f2` |
| `--text-muted` | `#8791ab` | `#8b9099` |
| `--text-faint` | `#57607a` | `#5b6069` |
| `--accent` | `#8368ff` | `#4ea8e0` |
| `--accent-soft` | `rgba(131,104,255,.16)` | `rgba(78,168,224,.15)` |
| `--up` | `#3fb878` | unchanged |
| `--up-soft` | `rgba(63,184,120,.14)` | unchanged |
| `--down` | `#f0546b` | unchanged |
| `--down-soft` | `rgba(240,84,107,.14)` | unchanged |
| `--stattrak` | `#e07b39` | `var(--brand)` |
| `--stattrak-soft` | `rgba(224,123,57,.16)` | `var(--brand-soft)` |
| `--brand` | *(new)* | `#f5a623` |
| `--brand-soft` | *(new)* | `rgba(245,166,35,.16)` |
| `--accent-ink` | *(new)* | `#08131d` |
| `--accent-deep` | *(new)* | `#1f4a6b` |
| `--accent-hover` | *(new)* | `#3f97cd` |

Hover-border neutral (replaces navy `#39435c`): `#34383e`.

## Files To Modify

### `app_core/app/frontend/shared/styles/tokens.css`

- Replace the `:root` values per the table; add the five new tokens;
  alias `--stattrak` / `--stattrak-soft` to `--brand` / `--brand-soft`.
- `body { background: #0c111b }` → `background: var(--bg)` (removes a
  duplicate literal).
- `.brand-mark span { color: var(--accent) }` → `var(--brand)` so the
  brand slash is the orange identity.
- `.avatar` gradient end `#4a3aa8` → `var(--accent-deep)`.
- `.toolbar-btn:hover` border `#39435c` → `#34383e`; add a matching
  neutral hover token only if a second use appears (not needed).
- `.toolbar-btn.has-active` border `rgba(131,104,255,.4)` →
  `rgba(78,168,224,.4)`.
- `.mover-row.is-selected` border `rgba(131,104,255,.4)` →
  `rgba(78,168,224,.4)`.

### `app_core/app/frontend/dashboard/styles/dashboard.css`

- `.signin-icon` border `rgba(131,104,255,.4)` →
  `rgba(78,168,224,.4)`.
- `.signin-cta { color: #fff }` → `color: var(--accent-ink)`.
- `.signin-cta:hover { background: #7256f0 }` →
  `var(--accent-hover)`.
- `.filter-badge { color: #fff }` → `var(--accent-ink)`.
- `.chip:hover` border `#39435c` → `#34383e`.
- `.chip.is-active` border `rgba(131,104,255,.5)` →
  `rgba(78,168,224,.5)`.

### `app_core/app/frontend/admin-panel/styles/admin-panel.css`

- `.admin-chip .avatar` border `rgba(131,104,255,.4)` →
  `rgba(78,168,224,.4)`.
- `.btn.primary { color: #fff }` → `var(--accent-ink)`.
- `.btn…` stattrak border `rgba(224,123,57,.35)` →
  `rgba(245,166,35,.35)`.
- StatTrak chip border `rgba(224,123,57,.4)` →
  `rgba(245,166,35,.4)`.
- `.pg-btn.active { color: #fff }` → `var(--accent-ink)`.

### `app_core/app/frontend/inventories/styles/inventories.css`

- One hover border `#39435c` → `#34383e`.

### `app_core/app/frontend/tracked_items/styles/tracked_items.css`

- Three hover borders `#39435c` → `#34383e`.

### `app_core/app/frontend/tracked_items/utils/rarity.js`

- `NEUTRAL_RARITY_COLOR = '#8791ab'` → `'#8b9099'` so the neutral
  fallback tracks the new `--text-muted`.

### `app_core/app/frontend/tracked_items/__tests__/rarity.test.js`

- Update the two fallback expectations from `#8791ab` to `#8b9099`.

## Files To Create

None.

## Applicable Styleguides

- `agent/styleguides/core/react-dashboard.md`
  - **Styling** — constrains where tokens live (`shared/styles/tokens.css`,
    the single custom-property block) and requires every island stylesheet
    to rely on those custom properties instead of redefining them. The
    plan therefore changes token values in one place and only replaces
    hardcoded legacy literals in island stylesheets; it must not
    re-declare `--accent`/`--surface`/etc. per island.
  - **Testing** — constrains the test change to the existing Vitest +
    `@testing-library` setup and the flat per-island `__tests__/`
    layout; `rarity.test.js` is updated in place.
- `agent/styleguides/git-commits.md` — constrains the commit message
  (`[Scope] Imperative summary`) when the finished change is committed.

`agent/styleguides/fix_me.md` currently lists no `app_core` entry for any
file this plan touches (verified during research).

## Test Plan

- **TDD for the one testable behavior:** update the `rarity.test.js`
  fallback expectations first, confirm they fail, then change
  `NEUTRAL_RARITY_COLOR` until green.
- **No new palette unit tests.** The palette has no behavioral contract;
  a test that parses `tokens.css` would be brittle and does not follow an
  existing pattern (no frontend test currently reads files).
- **Regression:** run the full `app_core` Vitest suite to prove no island
  test depends on the old literals.
- **Visual verification:** open dashboard, tracked items, inventories and
  admin panel in the running app (or the mockup) and check accent
  legibility, StatTrak/brand orange, rarity dots, and dark-on-accent
  buttons.

## Implementation Steps

1. Update the `:root` token block and add `--brand`, `--brand-soft`,
   `--accent-ink`, `--accent-deep`, `--accent-hover`; alias StatTrak to
   the brand orange.
2. Replace the remaining hardcoded literals in `tokens.css` (body
   background, brand slash, avatar gradient, hover/selected borders).
3. Update `dashboard.css` (sign-in CTA/icon, filter badge, chips).
4. Update `admin-panel.css` (avatar ring, primary buttons, paginator,
   StatTrak borders).
5. Update the neutral hover borders in `inventories.css` and
   `tracked_items.css`.
6. Update `rarity.test.js` expectations (red), then
   `NEUTRAL_RARITY_COLOR` (green).
7. Run lint, format check, and the Vitest suite.
8. Visually verify all four islands.

## Verification

From `app_core/` (or the docker-compose CI equivalent):

- `npm test` — Vitest suite passes.
- `npm run lint` — ESLint passes.
- `npm run format:check` — Prettier passes.
- `grep -rnE "8368ff|4a3aa8|7256f0|131, 104, 255" app_core/app/frontend`
  returns nothing.
- Manual/preview check: dashboard, tracked items, inventories, admin.
- Optional: `bin/ci` for the full app-level gate.

## Risks

- **Bright-accent text contrast.** White on `#4ea8e0` is ~2.6:1; every
  `color:#fff` on an accent background must become `--accent-ink`
  (dark). Missing one is a real accessibility regression.
- **Mil-Spec blue adjacency.** The accent `#4ea8e0` is ~9° from the
  canonical Industrial/Consumer rarity blues. Rarity dots are small and
  desaturated, but the inventories page must be checked.
- **Demo badge.** The yellow `Demo` badge (`#ffc107`) now sits near the
  orange brand (8°). Left as-is to keep scope tight; can be neutralized
  later if it reads muddy.
- **Global tokens.** Because the block is `:root`, admin-panel inherits
  the change automatically; its hardcoded literals are updated in the
  same pass so it doesn't drift.
- **`--brand` alias.** `--stattrak: var(--brand)` makes the StatTrak tag
  brighter (#f5a623 vs #e07b39); confirm the `ST` tag still reads as a
  marker and not as a brand highlight.

## Assumptions

- Variant 2 chrome values are exactly the ones approved in the mockup.
- "Merge into one orange" means one color value shared by the brand mark
  and StatTrak; a `--brand` token aliased by `--stattrak` is the
  implemented form.
- `NEUTRAL_RARITY_COLOR` is intended to match `--text-muted` (it did
  before the change).
- The Demo badge is out of scope.

## Completion Criteria

- The token table is applied and no legacy violet literals remain.
- All islands render with the new palette and readable accent text.
- `rarity.test.js` passes with the new neutral value.
- Lint, format check and the full Vitest suite pass.

# Implementation Summary

## Implemented

- Replaced the `:root` palette in `shared/styles/tokens.css` with the
  graphite + Steam-blue values (see the token table above).
- Added support tokens `--brand`, `--brand-soft`, `--accent-ink`,
  `--accent-deep`, `--accent-hover`; aliased `--stattrak` /
  `--stattrak-soft` to `var(--brand)` / `var(--brand-soft)`.
- `body` background now uses `var(--bg)`; the brand-mark slash uses
  `var(--brand)`; the avatar gradient uses `var(--accent-deep)`.
- Replaced the remaining hardcoded legacy literals:
  - `dashboard.css` — sign-in icon ring, sign-in CTA text/hover, filter
    badge text, chip hover and active borders.
  - `admin-panel.css` — avatar ring, primary/paginator button text,
    StatTrak borders.
  - `inventories.css` / `tracked_items.css` — neutral hover borders
    (`#39435c` → `#34383e`); `tracked_items.css` embedded chevron SVG
    (`%238791ab` → `%238b9099`).
- `NEUTRAL_RARITY_COLOR` now matches the new `--text-muted`.

## Tests

- Updated `app_core/app/frontend/tracked_items/__tests__/rarity.test.js`
  fallback expectations to `#8b9099` (watched fail first, then passed
  after changing `rarity.js`).
- Commands executed:
  - `npx vitest run app/frontend/tracked_items/__tests__/rarity.test.js`
  - `npx vitest run` (full suite)
  - `npx eslint app/frontend`
  - `npx prettier --check "app/frontend/**/*.{css,js,jsx}"`

## Verification

- Full Vitest suite: **53 test files / 320 tests passed**. One file
  (`controllers/__tests__/flash_controller.test.js`) fails to load
  because `@hotwired/stimulus` is declared in `package.json` but not
  installed in this local `node_modules`; it fails identically with the
  change stashed, so it is pre-existing and unrelated.
- ESLint: exit 0, no errors (one pre-existing `react-hooks` warning in
  `tracked_items/TrackedItems.jsx`, untouched).
- Prettier: all matched files pass.
- Legacy-literal grep (`8368ff|4a3aa8|7256f0|131,104,255|39435c|e07b39|
  224,123,57|0c111b|…`) returns clean across `app_core/app/frontend`.
- Visual check of the dashboard rendered with the real updated
  `tokens.css` + `dashboard.css`: graphite chrome, blue accent, orange
  brand slash, orange `ST` tags, dark text on the blue filter badge.

## Deviations

- Also updated the embedded data-URI chevron colour in
  `tracked_items.css` (`%238791ab` → `%238b9099`). It was not listed
  explicitly in the plan, but it is the same neutral literal that had to
  stay in sync with `--text-muted`; leaving it would have shipped a stale
  grey.
- No other deviations.

## Remaining Issues

- `flash_controller.test.js` cannot load locally without installing
  `@hotwired/stimulus`; run the suite in CI / a fully installed
  environment to confirm it. Not caused by this change.
- Non-dashboard islands (tracked items, inventories, admin) were not
  rendered in a live app during this session; they consume the same
  tokens and the updated literals. A quick pass in the running stack is
  recommended.
- The yellow `Demo` badge was intentionally left unchanged (out of
  scope); it sits near the new orange and can be neutralized later if it
  reads muddy.
