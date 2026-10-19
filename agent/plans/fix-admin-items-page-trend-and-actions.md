---
status: implemented
app: fetcher+core
goal: Fix the admin ItemsPage 24h trend display, remove the dead edit control and its unused backend update endpoint, and handle row-action failures without unhandled rejections.
created: 2026-10-19
---

# Development Plan

## Goal

Make the admin panel's Item page truthful and self-consistent: show the 24h
change as a percentage with a proper `up`/`down`/`flat` direction (zero is
flat, never growth), remove the non-functional edit button together with
the backend `update` action it would have called, and surface failures from
row-level mutations inline instead of leaving rejected promises unhandled.

## Expected Behavior

### 24h change column

- The column renders a percentage, not a raw cent amount, computed from
  `current_price_cents` and `change_24h_cents` using the same formula as
  `ItemCatalogSerializer`:
  `base = current_price_cents - change; percent = base.nil? || base.zero? ? 0 : change / base * 100`.
- Direction comes from `shared/utils/trend.js`'s `trendDirection(pct)`:
  - positive → `▲`, `up` class, e.g. `▲ 2.0%`;
  - negative → `▼`, `down` class, e.g. `▼ 1.7%`;
  - exactly zero, absent, or not computable → `flat`: a muted em dash
    (`—`), no arrow, and neither `up` nor `down`.
- The header makes the unit explicit (`24ч, %`).
- Percentages use one decimal place, matching the other islands' item rows.

### Row actions

- The `✎` button and its `Редактировать …` accessible name are removed from
  `ItemsPage`; row actions contain only the `⋯` menu
  (`Обновить цену сейчас` / `Удалить`).
- The backend no longer exposes `PATCH /api/admin/items/:id`.
  `Api::Admin::ItemsController#update`, `#update_params`, and the route are
  removed. The remaining Item routes are `index`, `show`, `create`,
  `destroy`, `refresh_price`, `warm_cache`, `bulk_warm_cache`, and
  `warm_catalog_cache`.
- A request to `PATCH /api/admin/items/:id` is unroutable, proving the
  endpoint is gone rather than merely unused.

### Mutation failures

- `handleDelete`, `handleRefreshPrice`, `handleWarmCatalogCache`, and
  `handleBulkWarmCache` catch rejected `adminSend` calls.
- A failure renders an inline alert within the resource (not a toast or
  `alert()`), preserves the current list/page/selection state, and does not
  produce an unhandled promise rejection.
- A subsequent mutation attempt clears the previous action error.
- `handleCreateSubmit` keeps its existing inline error inside the create
  panel; create success also clears any stale row-action error.

### Must remain unchanged

- Creating an item, deleting a row, refreshing a price, warming catalogs,
  pagination, selection, and the `⋯` menu behavior all keep their current
  request shapes and success behavior.
- `Api::Admin::ItemsController#index`/`show`/`create`/`destroy` and the
  admin bridge-token auth behavior are untouched.
- Other admin pages are out of scope.

## Scope

### In Scope

- `app_core/app/frontend/admin-panel/pages/ItemsPage.jsx` trend rendering,
  edit-button removal, and mutation error handling.
- A small pure frontend helper for the percentage calculation, with unit
  tests.
- `app_core/app/frontend/admin-panel/styles/admin-panel.css` for the inline
  action-error placement, if a new class is needed.
- `app_fetcher/config/routes.rb` and
  `app_fetcher/app/controllers/api/admin/items_controller.rb` removal of the
  update action/route.
- `app_fetcher/spec/requests/api/admin/items_spec.rb` removal of the PATCH
  success case.
- Documentation that currently describes Item as full CRUD with an update
  endpoint (`agent/styleguides/fetcher/admin-api-controllers.md` and the
  routing ADR `agent/adr/fetcher/admin-api-crud-routing.md`).

### Out of Scope

- Implementing inline item editing.
- Adding any new editable Item fields or a new update endpoint.
- Fixing mutation error handling on the other admin pages.
- Changing the admin API's `change_24h_cents` shape or adding a
  `change_24h_percent` field to `Admin::ItemSerializer`.
- Historical plan files under `agent/plans/` (they record past work and are
  not living documentation).

## Implementation Approach

### Percentage derivation

Add a pure helper in the admin panel's `utils/` layer (following
`react-dashboard.md`'s derived-data rule) rather than inlining the formula
in the render body. It takes the two raw cent values and returns a number:

```js
changePercent(currentPriceCents, changeCents)
```

It is null-safe: absent current price or a zero base yields `0`, matching
`ItemCatalogSerializer`'s existing semantics. This keeps the admin page
consistent with the public catalog without changing the admin API response.

`ItemsPage` then derives `pct`, `direction`, `arrow`, and the display string
from the helper and `trendDirection`. A flat row renders the em dash instead
of an arrow + `0.0%`.

### Edit endpoint removal

Remove `update` from the `resources :items` `only:` list and delete the
controller action plus its private params method. Remove the PATCH request
spec.

### Mutation error state

Add a page-level `actionError` state. Each row/bulk mutation clears it,
awaits `adminSend`, performs its existing success action/refetch, and sets
`actionError` in `catch`. Render it as an inline `role="alert"` element near
the resource header. Keep `createError` separate so create validation
messages remain inside the create form.

## Files To Modify

- `app_core/app/frontend/admin-panel/pages/ItemsPage.jsx` — import
  `trendDirection`, derive percent/direction, render the flat/up/down cell,
  change the header to `24ч, %`, remove the `✎` button, add `actionError`
  handling to the mutation handlers, and clear stale action errors on
  create.
- `app_core/app/frontend/admin-panel/utils/change.js` — new pure
  `changePercent` helper.
- `app_core/app/frontend/admin-panel/__tests__/change.test.js` — unit tests
  for the helper.
- `app_core/app/frontend/admin-panel/__tests__/ItemsPage.test.jsx` — cover
  positive/negative/flat percentage rendering, absence of the edit button,
  and inline errors for delete/refresh/bulk/catalog failures.
- `app_core/app/frontend/admin-panel/styles/admin-panel.css` — only if the
  inline action alert needs its own placement class; reuse the existing
  error styling otherwise.
- `app_fetcher/config/routes.rb` — drop `update` from `resources :items`.
- `app_fetcher/app/controllers/api/admin/items_controller.rb` — remove
  `#update` and `#update_params`.
- `app_fetcher/spec/requests/api/admin/items_spec.rb` — remove the PATCH
  success spec.
- `agent/styleguides/fetcher/admin-api-controllers.md` — update the
  Item/full-CRUD, update-validation, error-handling, and canonical-example
  references to reflect that Item has no update action.
- `agent/adr/fetcher/admin-api-crud-routing.md` — update the
  create/read/update/destroy wording to describe Item's actual lifecycle.

## Files To Create

- `app_core/app/frontend/admin-panel/utils/change.js` — one pure
  percentage-derivation function; needed so the formula is tested once and
  not embedded in JSX.
- `app_core/app/frontend/admin-panel/__tests__/change.test.js` — unit tests
  for that helper.

## Test Plan

### Frontend (Vitest + Testing Library)

- `change.test.js`: normal positive/negative changes; zero change; missing
  change; missing current price; zero base (current price equals the
  change) all return the expected number without throwing.
- `ItemsPage.test.jsx`:
  - positive change (`current_price_cents: 1245`, `change_24h_cents: 25`)
    renders `▲ 2.0%` with the `up` class;
  - negative change renders `▼ …%` with the `down` class;
  - zero change renders `—` with no arrow and neither `up` nor `down`;
  - the edit button (`Редактировать …`) is absent, while the `⋯` menu still
    works;
  - a failed DELETE shows the server message inline and keeps the row;
  - a failed `refresh_price` shows the message inline;
  - failed bulk/catalog cache actions show the message inline and do not
    clear the selection on bulk failure.

### Backend (RSpec request spec)

- Existing Item request specs remain green for index/show/create/destroy and
  the cache actions.
- The PATCH success example is removed.

## Implementation Steps

1. Add `utils/change.js` with `changePercent` and its unit test.
2. Update `ItemsPage` to use `changePercent` + `trendDirection`, render the
   percent cell with flat handling, and rename the header.
3. Remove the `✎` button from the row actions.
4. Add `actionError` state and try/catch to all four mutation handlers;
   render the inline alert and clear stale errors on subsequent attempts.
5. Add the frontend regression tests for trend rendering, edit-button
   absence, and mutation failures.
6. Remove `update` from the Item route and delete the controller action and
   `update_params`.
7. Update the backend request spec by removing the PATCH success example.
8. Amend `admin-api-controllers.md` and the routing ADR so they no longer
   claim Item has an update endpoint.
9. Run formatting, linting, frontend tests, backend specs, and the
   route-related checks.

## Verification

- `app_core`: `npm run test` for the admin-panel suite (or the whole Vitest
  suite), `npm run lint`, `npm run format:check`.
- `app_fetcher`: `bundle exec rspec spec/requests/api/admin/items_spec.rb`,
  plus RuboCop and Sorbet for the touched Ruby files.
- Confirm `PATCH /api/admin/items/:id` is absent from `bin/rails routes`.
- Confirm the full admin Item flow still works: list loads, create works,
  delete works, refresh-price works, bulk/catalog cache actions work, and a
  forced failure shows the inline alert.

## Risks

- Removing the backend `update` action is a public-API shape change, but the
  endpoint has no caller in `app_core` (the only admin client) and the user
  explicitly requested its removal.
- Changing the 24h cell from cents to percent changes what operators see;
  the formula and flat handling must match the public catalog so the two
  views do not disagree.
- `Admin::ItemSerializer` still emits only cents; percent is derived from
  those two values on the client. If the API later adds a percent field,
  `changePercent` should be replaced by that field rather than kept as a
  second source of truth.

## Assumptions

- "Remove the endpoint on the backend" means the Item `update` action and
  its PATCH route, not `show`/`create`/`destroy` or the cache/refresh actions.
- A flat 24h change should render as a muted em dash, consistent with the
  item-row rule that a flat trend shows no delta badge.
- The other admin pages' mutation error handling is separate follow-up work,
  not part of this bug fix.

## Applicable Styleguides

- `agent/styleguides/core/react-dashboard.md` — constrains the percentage
  derivation placement (`utils/`, not inline JSX), the `trendDirection`
  flat rule and muted `—` table cell, the new "Mutation Failure Handling"
  section (catch, inline error, preserve page state, form-scoped vs
  page-level errors), and the Vitest/Testing Library test structure.
- `agent/styleguides/fetcher/admin-api-controllers.md` — constrains the
  narrowed `resources :items, only: %i[index show create destroy]` route
  and the controller-action removal.
- `agent/styleguides/rspec-conventions.md` — constrains the request-spec
  change (removing the PATCH example).
- `agent/styleguides/ruby-sorbet.md` — applies to the remaining
  `app_fetcher` controller edits (no new sigs needed for deleted methods;
  keep the file `typed: strict` and consistent).
- `agent/styleguides/git-commits.md` — `[Scope] Imperative summary` commit
  format for the implementation commit.
- `agent/styleguides/ci-and-coverage.md` — run the checks through the
  docker-compose setup the repo's CI uses.

## Completion Criteria

- The Item page never renders `▲` or a green class for a zero change.
- The 24h column shows a percentage with an explicit `%` header unit.
- No dead edit button remains, and no PATCH item route exists.
- Delete/refresh/cache failures are caught and shown inline.
- The new frontend and backend tests pass, and the touched files pass the
  lint/format/type checks.

## Implementation Summary

### Implemented

- Added `admin-panel/utils/change.js`'s `changePercent`, matching
  `ItemCatalogSerializer`'s derivation against the previous price.
- `ItemsPage` now renders the 24h change as a percentage using
  `trendDirection`: `▲`/`up`, `▼`/`down`, or a muted `—` for flat. The
  column header is `24ч, %`.
- Removed the dead `✎` edit button from the Item row actions.
- Added page-level `actionError` handling to delete, refresh-price, bulk
  cache-warm, and catalog cache-warm handlers; create continues to use its
  form-scoped `createError`. Errors render inline with `role="alert"` and do
  not discard the list, page, or selection.
- Removed the backend Item update action, its `update_params`, and the
  `update` route. The obsolete PATCH request spec was removed.
- Amended `admin-api-controllers.md`, `react-dashboard.md`, and
  `admin-api-crud-routing.md` to match the new route set, flat-row
  rendering, and mutation failure rules.

### Tests

Added `admin-panel/__tests__/change.test.js` (6 helper cases) and expanded
`ItemsPage.test.jsx` with positive/negative/flat trend rendering, removed
edit-button coverage, and delete/refresh/bulk/catalog failure coverage.
Removed the old PATCH success example from
`spec/requests/api/admin/items_spec.rb`.

Commands actually run:

- `app_core: npm run test` — targeted run first (RED then GREEN), then the
  full suite.
- `app_core: npm run lint`
- `app_core: npm run format:check`
- `app_fetcher: bundle exec rspec spec/requests/api/admin/items_spec.rb`
- `app_fetcher: bundle exec rspec spec/requests/api/admin`
- `app_fetcher: bin/rubocop app/controllers/api/admin/items_controller.rb config/routes.rb spec/requests/api/admin/items_spec.rb`
- `app_fetcher: bundle exec srb tc`
- `app_fetcher: bin/rails routes` (checked the admin Item route set)

### Verification

- Full Vitest suite: 43 files, 267 tests passed.
- Admin request specs: 56 examples, 0 failures.
- ESLint: 0 errors (one pre-existing `react-hooks/exhaustive-deps` warning
  in `tracked_items/TrackedItems.jsx`, untouched by this change).
- Prettier: all matched files use the project style.
- RuboCop: 3 inspected files, no offenses.
- Sorbet: no errors.
- `bin/rails routes` shows Item `GET`/`POST`/`DELETE` and the member/
  collection actions, with no `PATCH /api/admin/items/:id`.

### Deviations

- The existing stale route lists for nested
  `price_logs`/`inventory_value_logs` were also corrected in
  `admin-api-crud-routing.md` while updating the same decision text.
- Verification required freeing space on the `/home` filesystem (npm cache
  and Docker builder cache cleanup); no repository files were affected.

### Remaining Issues

- None for this change. Mutation error handling on the other admin pages
  remains separate follow-up work, as scoped out in the plan.
