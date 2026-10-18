---
status: implemented
app: core
goal: Make the admin panel reuse app_core's shared design tokens and fonts instead of duplicating them locally
created: 2026-10-18
---

# Development Plan

## Goal

Remove the admin panel's duplicated `@font-face` and design-token block by
making `shared/styles/tokens.css` the single source of those values for
every React island, including `admin-panel/`, and import that shared
stylesheet from the admin panel's Vite entrypoint.

## Expected Behavior

**Normal behavior:**

- Every island's entrypoint, including `entrypoints/admin-panel.jsx`,
  imports `shared/styles/tokens.css` before its own island stylesheet.
- `shared/styles/tokens.css` exposes the shared color/font/radius custom
  properties at `:root`, so an island whose root class is not `.dash-root`
  (the admin panel's `.admin-shell`) can use the same tokens.
- `admin-panel.css` no longer declares its own `@font-face` rules, its own
  copy of the shared token block, or its own `body` reset. It only keeps
  admin-panel-specific layout/component rules plus any genuinely
  admin-only additions.
- The admin panel renders with the same dark palette, fonts, and sidebar
  layout as before the refactor.

**Edge cases:**

- The admin panel needs two tokens not previously present in the shared
  block: `--surface-sunken` and `--border-soft`. They move into the shared
  token block so no island-local redefinition remains.
- Other islands (`dashboard/`, `tracked_items/`, `inventories/`) continue
  to resolve every token through the same shared block; because they
  already wrap their content in `.dash-root`, inheriting the tokens from
  `:root` produces identical computed values.
- Pages that load `application.css` only (the admin login page) are
  unaffected: `application.css` does not use the shared custom properties.

**Failure behavior:**

- None introduced. This is a stylesheet/entrypoint refactor with no
  runtime logic, network calls, or authentication changes.

**Behavior that must remain unchanged:**

- All admin panel layout, colors, typography, table/pagination styling,
  and interactions.
- Dashboard, tracked-items, and inventories page appearance.
- `application.css`'s login-page body reset and admin login behavior.
- Existing Vitest/RSpec suites.

## Scope

### In Scope

- Splitting the token declarations out of `shared/styles/tokens.css`'s
  `.dash-root` block into a `:root` block, leaving `.dash-root`'s layout
  declarations in place.
- Adding the two admin-used tokens (`--surface-sunken`, `--border-soft`)
  to that shared block.
- Importing `shared/styles/tokens.css` first in
  `entrypoints/admin-panel.jsx`.
- Deleting the duplicated `@font-face`, `:root` token block, and `body`
  rule from `admin-panel.css`.
- Removing the two now-resolved entries from
  `agent/styleguides/fix_me.md`.
- Browser verification of the admin panel plus at least one other island.

### Out of Scope

- Changing any token values, the palette, typography, or layout.
- Introducing CSS modules, a preprocessor, or a build-system change.
- Refactoring admin-panel-specific selectors/classes.
- Changing `application.css` or the login page again.

## Implementation Approach

`shared/styles/tokens.css` currently defines the shared tokens **inside
`.dash-root`** (lines 64-95), then uses the same block for `.dash-root`'s
own layout. That is why the admin panel never received them: its root is
`.admin-shell`, not `.dash-root`, so it copied the token block locally.

The minimal structural fix is:

1. Move the custom-property declarations into a new `:root { ... }`
   block; leave `position`/`min-height`/`padding`/`max-width`/`margin`/
   `background`/`color`/`font-family` on `.dash-root`.
2. Add `--surface-sunken: #0f1420` and `--border-soft: #1d2537` to that
   `:root` block (the only two admin-specific tokens).
3. Import `../shared/styles/tokens.css` before
   `../admin-panel/styles/admin-panel.css` in `entrypoints/admin-panel.jsx`.
4. Delete `admin-panel.css`'s `@font-face` rules, its local `:root` block
   (including `body`), and rely on the shared block. The admin panel's
   `--accent-soft`/`--up-soft`/`--down-soft`/`--stattrak-soft` alphas
   change by at most 0.02, matching the shared design tokens; this is the
   intended unification, not a visual redesign.
5. Remove the two entries this resolves from `fix_me.md`.

No JavaScript/JSX behavior changes, so no new Vitest test is meaningful
for the import itself. Verification is visual/computed-style based in a
browser, plus existing suites to prove no regression.

## Files To Modify

- `app_core/app/frontend/shared/styles/tokens.css` — split the token
  block into `:root`, add `--surface-sunken`/`--border-soft`. Reason:
  make tokens available to every island root, not only `.dash-root`.
- `app_core/app/frontend/entrypoints/admin-panel.jsx` — import
  `shared/styles/tokens.css` before the admin stylesheet. Reason: match
  every other island entrypoint and load the shared tokens/fonts.
- `app_core/app/frontend/admin-panel/styles/admin-panel.css` — remove the
  duplicated `@font-face` rules, local `:root` token block, and `body`
  reset. Reason: one source of truth.
- `agent/styleguides/fix_me.md` — delete the two entries for
  `admin-panel.jsx` and `admin-panel.css`. Reason: they are now
  compliant; the file's own instruction is to remove resolved entries.

## Files To Create

None.

## Test Plan

- No new unit/component test: the change is CSS import/source-of-truth
  plumbing with no branching logic, and jsdom does not load stylesheets.
- Run the existing Vitest suite to prove the entrypoint/style import does
  not break module loading.
- Run the existing `app_core` RSpec suite (admin panel request spec
  renders the page with the Vite entrypoint).
- Browser/computed-style verification:
  - `/admin`: `.admin-shell` still flex with left sidenav; computed
    `font-family` of a nav link resolves to IBM Plex Sans; computed
    colors resolve to the shared values; no duplicate font loading.
  - `/` (dashboard), `/tracked-items`, and `/inventories`: computed
    tokens on `.dash-root` are unchanged (same `--bg`, `--accent`,
    `--font-body`).

## Implementation Steps

1. Edit `shared/styles/tokens.css`: add `:root` token block, add the two
   missing tokens, keep `.dash-root` layout declarations.
2. Edit `entrypoints/admin-panel.jsx`: add the shared tokens import first.
3. Edit `admin-panel.css`: remove local `@font-face`, `:root`, and `body`
   duplicates.
4. Edit `fix_me.md`: remove the two resolved entries.
5. Run `app_core` RSpec and Vitest.
6. Verify admin panel and the three other islands in a browser.
7. Update the plan file with `status: implemented` and an Implementation
   Summary.

## Verification

- `app_core`: `bundle exec rspec` (with CI env vars + `node_modules`
  mount, as used for the previous admin fix).
- `app_core`: `npm test`.
- `app_core`: `npm run format:check` and `npm run lint`.
- Browser: admin panel layout/fonts/colors after the refactor; dashboard,
  tracked-items, and inventories token values before/after.

## Risks

- Moving tokens from `.dash-root` to `:root` makes them globally
  available. No selectors or property names collide today; the only
  visible effect should be the intended admin-panel reuse. Verify the
  three existing islands in a browser.
- Shared soft-color alphas differ slightly from the admin panel's local
  copies (e.g. `--up-soft` 0.14 vs 0.13). This is the unification the
  refactor is for; it is a subtle tint change, not a functional one.
- The admin entrypoint will now also receive tokens.css's global
  `html { font-size: clamp(...) }`. Admin panel styles are px-based, so no
  layout change is expected; verify in the browser.

## Assumptions

- `shared/styles/tokens.css` is intended as the one shared token/font
  layer for every island (stated in `react-dashboard.md`); scoping the
  tokens to `.dash-root` was an implementation detail that the admin
  panel exposed, not a deliberate exclusion.
- The two extra admin tokens are generic enough to live in the shared
  block rather than staying island-local.

## Applicable Styleguides

- `agent/styleguides/core/react-dashboard.md` — its Styling section
  requires every island entrypoint to import
  `shared/styles/tokens.css` before the island's own stylesheet and
  requires island stylesheets to rely on that shared token block instead
  of redefining it. This refactor is exactly that rule's implementation
  for `admin-panel/`.
- `agent/styleguides/git-commits.md` — commit message format for the
  resulting local commit.

## Completion Criteria

- `admin-panel.jsx` imports `shared/styles/tokens.css` first.
- `admin-panel.css` has no duplicated font/token/body declarations.
- The admin panel and existing islands render unchanged in a browser.
- `fix_me.md` no longer flags either admin-panel file.
- RSpec, Vitest, Prettier, and ESLint pass as before.
- The plan file is marked `implemented` with a summary.

## Implementation Summary

**Implemented**

- Split `shared/styles/tokens.css`'s token declarations out of
  `.dash-root` into a global `:root` block, added `--surface-sunken` and
  `--border-soft`, and left `.dash-root`'s layout declarations in place.
- Imported `../shared/styles/tokens.css` before
  `../admin-panel/styles/admin-panel.css` in
  `entrypoints/admin-panel.jsx`.
- Removed the duplicated `@font-face` rules, local `:root` token block,
  and `body` reset from `admin-panel.css`.
- Removed the two now-resolved admin-panel entries from
  `agent/styleguides/fix_me.md`.

**Tests**

No new test was added: this is a CSS source-of-truth/import refactor
with no branching logic, and jsdom does not load stylesheets. Existing
suites were run instead.

Commands actually executed:

- `docker run ... bundle exec rspec` — 50 examples, 0 failures.
- `npm test` — 42 files / 255 tests passed.
- `npm run format:check` — clean.
- `npm run lint` — no errors (the same pre-existing
  `react-hooks/exhaustive-deps` warning in
  `tracked_items/TrackedItems.jsx`).

**Verification**

Browser/computed-style comparison on the worktree preview:

- `/admin`: nav font still `"IBM Plex Sans", ...`, nav color
  `rgb(237, 240, 247)`, topbar `rgb(28, 35, 52)`, body
  `rgb(12, 17, 27)`, `.admin-shell` still `display: flex`, nav geometry
  `x=0..216`.
- `/`, `/tracked-items`, `/inventories`: `.dash-root`'s computed
  `--bg`/`--accent`/`--font-body` unchanged; `:root` now also exposes
  `--surface-sunken`/`--border-soft`, as intended.
- Temporary preview container and admin user were removed afterward.

**Deviations**

None.

**Remaining Issues**

None.
