---
status: implemented
app: core
goal: Replace every remaining Russian user-facing string in the admin panel with English
created: 2026-10-18
---

# Development Plan

## Goal

Make the admin panel's UI copy consistently English by translating all
remaining Russian labels, headers, placeholders, ARIA labels, hints, and
pagination copy, and updating the Vitest expectations that drive those
strings.

## Expected Behavior

**Normal behavior:**

- The admin sidenav groups read "Catalog & Prices" and "Inventories".
- Every admin resource page's loading/error/empty states, section
  headings, buttons, table headers, menu actions, create-panel labels,
  hints, and ARIA labels are English.
- Pagination reads "Showing X–Y of Z", "No records", and "per page".
- The existing admin functionality and API calls are unchanged; only
  display/accessibility text changes.

**Edge cases:**

- The inventory row-expand overflow marker becomes English
  ("…and N more") and its test is updated.
- The two read-only pages keep asserting that no create button exists,
  now using the English "New" matcher.
- The `market_hash_name` header, item names, and other domain identifiers
  stay unchanged.

**Failure behavior:**

- No behavior change: loading/error states still render in the same
  places with the same conditions, now with English copy.

**Behavior that must remain unchanged:**

- All admin API endpoints, request shapes, hashes/routes, reducers,
  layout, styling, and data formatting.
- The admin login page (already English).
- Non-admin pages' copy.

## Scope

### In Scope

- `AdminPanel.jsx` sidenav group labels.
- `Pagination.jsx` range/empty/per-page copy.
- `ItemsPage.jsx` loading/error, toolbar, create panel, table headers,
  row actions, ARIA labels, hints.
- `PriceLogsPage.jsx` loading/error, heading, table headers, delete
  action label.
- `UserInventoriesPage.jsx` loading/error, heading, toolbar, table
  headers, expand/sync/delete labels, nested-table headers, overflow
  marker.
- `InventoryValueLogsPage.jsx` loading/error, heading, table headers,
  delete action label.
- Matching Vitest expectations in
  `app_core/app/frontend/admin-panel/__tests__/`.

### Out of Scope

- Adding i18n/Rails locale infrastructure or a translation dictionary.
- Changing non-admin pages or backend API response messages.
- Changing Russian text in `agent/` planning docs (historical records).
- Any visual redesign or layout change.

## Implementation Approach

Keep this as a literal copy replacement, file by file. Use natural,
consistent English matching the existing app's tone (`Couldn&rsquo;t
load ...`, `Loading…`, `Cancel`, `Delete`). Prefer the API's own
terminology where it is already English (`market_hash_name`, `Item`,
`PriceLog`, `UserInventory`, `InventoryValueLog`, `Steam ID`).

Cache-action labels are translated as "Warm cache" / "Warm catalog
cache" rather than the literal "Rebuild cache": the backend action only
ensures the cache is warm (documented in
`agent/plans/admin-panel-frontend.md`), so the English copy can describe
the actual effect instead of carrying over a misleading literal label.

Update the Vitest tests in the same change so they assert the English
copy. No new test files are needed.

## Files To Modify

- `app_core/app/frontend/admin-panel/AdminPanel.jsx` — nav group labels.
- `app_core/app/frontend/admin-panel/components/Pagination.jsx` —
  pagination summary and per-page selector copy.
- `app_core/app/frontend/admin-panel/pages/ItemsPage.jsx` — all Russian
  text and ARIA labels.
- `app_core/app/frontend/admin-panel/pages/PriceLogsPage.jsx` — same.
- `app_core/app/frontend/admin-panel/pages/UserInventoriesPage.jsx` —
  same.
- `app_core/app/frontend/admin-panel/pages/InventoryValueLogsPage.jsx` —
  same.
- `app_core/app/frontend/admin-panel/__tests__/AdminPanel.test.jsx` —
  assert English group labels.
- `app_core/app/frontend/admin-panel/__tests__/ItemsPage.test.jsx` —
  assert English selected/cache/create/delete/refresh labels.
- `app_core/app/frontend/admin-panel/__tests__/UserInventoriesPage.test.jsx`
  — assert English expand/cache/sync/delete/overflow labels.
- `app_core/app/frontend/admin-panel/__tests__/PriceLogsPage.test.jsx` —
  assert English delete label and absence-of-create matcher.
- `app_core/app/frontend/admin-panel/__tests__/InventoryValueLogsPage.test.jsx`
  — same.

## Files To Create

None.

## Test Plan

- Update the five existing Vitest files that query the translated text.
- RED first: change the expectations to English, run the admin-panel
  tests, confirm they fail against the current Russian UI.
- GREEN: translate the components/page copy, rerun the same tests.
- Run the full Vitest suite.
- Run `npm run format:check` and `npm run lint`.
- Optionally verify in a browser that each admin page contains no
  Cyrillic characters and the usual layout/interactions still work.

## Implementation Steps

1. Update the Vitest expectations to the intended English strings.
2. Run the admin-panel tests and confirm the expected RED failures.
3. Translate `AdminPanel.jsx` and `Pagination.jsx`.
4. Translate the four page components.
5. Re-run the admin-panel tests, then the full Vitest suite.
6. Run Prettier/ESLint and a browser Cyrillic sweep.
7. Mark the plan `implemented` with a summary.

## Verification

- `app_core`: `npx vitest run admin-panel` and `npm test`.
- `app_core`: `npm run format:check`, `npm run lint`.
- Browser on `/admin`: every route (`#item`, `#price-log`,
  `#user-inventory`, `#inventory-value-log`) has no Cyrillic text in the
  rendered DOM.
- `grep -P '[А-Яа-яЁё]'` over `app_core/app/frontend/admin-panel/` returns
  no matches outside this plan's own historical references (none should
  remain in source/tests).

## Risks

- Translating ARIA labels can silently break tests that query by role
  name; all affected expectations are updated in the same change.
- "Warm cache" is a deliberate improvement over the literal Russian
  "rebuild"; it matches the endpoint's actual behavior and existing
  English backend messages ("Catalog cache warmed").
- No runtime/data risk: only string literals change.

## Assumptions

- The admin panel is the only UI area with Russian copy; a repo-wide sweep
  confirms `app_core/app` and `app_fetcher/app` have no other Cyrillic
  strings.
- English is the desired copy language for every user-facing string in
  `app_core` for now.

## Applicable Styleguides

- `agent/styleguides/core/react-dashboard.md` — governs component copy
  placement/rendering, keeping tests under the island's flat
  `__tests__/` directory, and using `@testing-library` role/name queries
  for user-facing text. No new components or state are introduced.
- `agent/styleguides/git-commits.md` — commit message format for the
  resulting local commit.

## Completion Criteria

- No Russian user-facing strings remain under
  `app_core/app/frontend/admin-panel/`.
- All affected Vitest expectations use the English copy.
- Vitest, Prettier, and ESLint pass.
- The plan file is marked `implemented` with a summary.

## Implementation Summary

**Implemented**

- Translated the admin sidenav groups to "Catalog & Prices" /
  "Inventories".
- Translated pagination copy to "Showing X–Y of Z", "No records", and
  "per page".
- Translated all four resource pages' loading/error states, section
  headings, toolbar/selection labels, table headers, create-panel copy,
  row-action menus, ARIA labels, expand/sync/delete labels, and the
  "…and N more" inventory overflow marker.
- Cache actions read "Warm cache" / "Warm catalog cache", matching the
  actual backend behavior.
- Updated all five affected Vitest files to assert the English copy.

**Tests**

- RED: changed the Vitest expectations to English first; the admin-panel
  suite failed with 13 failures against the Russian UI.
- GREEN: after translating the components, `npx vitest run admin-panel`
  passed (14 files / 68 tests).

Commands actually executed:

- `npx vitest run admin-panel` — RED 13 failures, then GREEN 68 tests.
- `npm test` — 42 files / 255 tests passed after the final formatting.
- `bundle exec rspec` — 50 examples, 0 failures.
- `npm run format` / `npm run format:check` — clean.
- `npm run lint` — no errors (same pre-existing
  `react-hooks/exhaustive-deps` warning in `TrackedItems.jsx`).
- `grep -RIn -P '[А-Яа-яЁё]' app_core/app app_core/spec app_fetcher/app app_fetcher/spec`
  — no matches.

**Verification**

Browser on `/admin` after signing in: `#item`, `#price-log`,
`#user-inventory`, and `#inventory-value-log` all rendered with no
Cyrillic in `document.body.innerText` and no Cyrillic in any element
attributes (ARIA labels/titles/placeholders). The API-backed tables
showed their English error states in the preview because the worktree
preview origin is not in the fetcher's CORS allow-list; the full table
copy is covered by the Vitest assertions.

Temporary preview container and admin user were removed afterward.

**Deviations**

None.

**Remaining Issues**

None.
