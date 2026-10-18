---
status: implemented
app: core
goal: Fix the admin login page's body frame/scrollbar, preserve the entered email after a failed login, and restore the admin panel's left sidebar layout
created: 2026-10-18
---

# Development Plan

## Goal

Fix three visible regressions in `app_core`'s admin UI: the login page's
page-wide white frame and unwanted vertical scrollbar, the login form
losing the entered email after a failed sign-in, and the admin panel
rendering its navigation above the page content instead of as a left
sidebar.

## Expected Behavior

**Normal behavior:**

- `GET /admin/session/new` fills the browser viewport exactly: no
  body-margin frame around the dark page and no vertical scrollbar when
  the content fits the viewport.
- Submitting wrong credentials re-renders the login form with the same
  error as today and keeps the entered email address in the email field;
  the password field stays empty.
- After signing in, `GET /admin` renders the topbar, then a two-column
  layout: the 216px sidenav on the left and the active resource page on
  the right, each occupying the full remaining viewport height.
- Switching between `#item`, `#price-log`, `#user-inventory`, and
  `#inventory-value-log` keeps the navigation on the left and the page
  content in the right-hand column.

**Edge cases:**

- An empty email field on the first login page render stays empty.
- An email containing characters that need HTML escaping is still
  rendered safely in the re-rendered form (Rails' normal attribute
  escaping).
- A short resource table does not leave the sidenav with a background
  that stops halfway down the viewport.

**Failure behavior:**

- Bad credentials still produce the existing
  `Invalid email or password` inline error with the existing
  `422 Unprocessable Content` status and unchanged JSON-format behavior.

**Behavior that must remain unchanged:**

- JSON login/logout behavior (`Admin::SessionsController#create`/
  `#destroy`, `Admin::BaseController#require_admin!`) is untouched.
- Admin panel routing, hash navigation, React page behavior, and all
  current request/Vitest expectations are untouched.
- Non-admin pages that already reset `body` via
  `shared/styles/tokens.css` keep their current appearance.

## Scope

### In Scope

- A page-level `body` reset for the plain ERB layout used by the admin
  login page.
- Retaining `params[:email]` when the login form re-renders after a
  failed sign-in.
- A flex layout on `.admin-shell` so the existing `.sidenav` and
  `.admin-main` sit side by side.
- Request-spec coverage for the retained email value.
- Logging the pre-existing admin-panel stylesheet/token deviation found
  during research in `agent/styleguides/fix_me.md` (not fixing it here).

### Out of Scope

- Redesigning the admin login page or panel.
- Sticky/fixed topbar or sidenav behavior.
- Responsive/mobile admin layout (still explicitly out of scope per
  `agent/plans/admin-panel-frontend.md`).
- Refactoring `admin-panel.css` to import `shared/styles/tokens.css` or
  moving its token definitions; that is a larger, separate cleanup.
- Any backend `Api::Admin::` or `app_fetcher` change.

## Implementation Approach

Research findings:

- `.admin-login` sets `min-height: 100vh` in
  `app_core/app/assets/stylesheets/application.css`, but that stylesheet
  never resets the browser's default `body { margin: 8px }` (unlike
  `shared/styles/tokens.css`, which every Vite island entrypoint imports
  but the plain admin login page does not). This produces both the white
  8px frame (default white `html` background showing through) and a
  `100vh + 16px` document that scrolls. Confirmed in a browser at a
  1000×700 viewport: `document.scrollHeight` was 716 and computed
  `body.margin` was `8px`.
- The login form uses `form_with url: ...` without a model. On a failed
  `create`, no object supplies the field value, so
  `form.text_field :email` renders empty. The failed request's
  `params[:email]` is available on the re-rendered view and can be
  passed back explicitly.
- `#admin-panel-root` is `display: flex`, but its only child,
  `.admin-shell`, is a plain block with no display rule. The sidenav and
  `.admin-main` therefore stack vertically inside it. Making
  `.admin-shell` itself the flex row (and letting it fill the root)
  restores the intended left-nav layout without changing the JSX.

The smallest fix keeps all changes in the existing files: one global
body reset in `application.css`, one explicit `value:` in the login
view, and one `.admin-shell` rule in `admin-panel.css`.

## Files To Modify

- `app_core/app/assets/stylesheets/application.css` — add a `body`
  reset (`margin: 0`, dark background) before the `.admin-login` rules so
  the login page has no white frame and no extra 16px of scroll height.
  Reason: this is the only stylesheet loaded by the plain admin login
  page.
- `app_core/app/views/admin/sessions/new.html.erb` — pass
  `value: params[:email]` to the email field. Reason: preserve the
  entered address when the controller re-renders after bad credentials.
- `app_core/app/frontend/admin-panel/styles/admin-panel.css` — add an
  `.admin-shell { display: flex; flex: 1; min-width: 0; }` rule next to
  `#admin-panel-root`. Reason: make the existing sidenav and main content
  lay out as a left sidebar + content row.
- `app_core/spec/requests/admin/sessions_spec.rb` — assert that the email
  field keeps `admin@example.com` after a failed HTML login, and that the
  password is not echoed back. Reason: lock in the bug fix.
- `agent/styleguides/fix_me.md` — add one core-scope entry recording
  that `admin-panel/styles/admin-panel.css` duplicates the shared
  font/token block and that `entrypoints/admin-panel.jsx` does not import
  `shared/styles/tokens.css`, contrary to `react-dashboard.md`'s
  "one shared tokens stylesheet per island entrypoint" rule. Reason:
  research surfaced a pre-existing deviation; the convention says log it
  rather than silently fixing or ignoring it.

## Files To Create

None.

## Test Plan

- Extend `app_core/spec/requests/admin/sessions_spec.rb`'s
  `POST /admin/session (format.html)` failure example (or add a sibling
  example) to assert:
  - the response body includes the submitted email in the email input's
    `value` attribute;
  - the response body does not include the submitted wrong password in a
    `value` attribute.
- Keep all existing JSON and HTML login specs passing unchanged.
- Not add a Vitest test for the pure CSS layout change: Vitest/jsdom does
  not load `admin-panel.css`, so a test there would only assert class
  names, not the layout. Verify the layout in a real browser instead
  (see Verification).
- Not add a request spec for the CSS body reset for the same reason;
  verify it in a real browser.

## Implementation Steps

1. Add the `body` reset to
   `app_core/app/assets/stylesheets/application.css`.
2. Add `value: params[:email]` to the email field in
   `app_core/app/views/admin/sessions/new.html.erb`.
3. Add the `.admin-shell` flex rule to
   `app_core/app/frontend/admin-panel/styles/admin-panel.css`.
4. Extend the failed HTML login request spec to cover the retained email
   and absent password echo.
5. Add the admin-panel token/styles deviation entry to
   `agent/styleguides/fix_me.md`.
6. Run the relevant specs, RuboCop/Prettier where applicable, and verify
   both pages in the running browser.

## Verification

- `app_core`: `bundle exec rspec spec/requests/admin/sessions_spec.rb`
  and the rest of the request suite.
- `app_core`: `bundle exec rubocop` on changed Ruby/spec files (or the
  app's normal lint target).
- `app_core`: `npm run format:check` and `npm run lint` if any frontend
  JS/JSX is touched (this plan touches only CSS, so confirm the CSS does
  not break those checks; no JS change expected).
- Browser at `http://localhost:3000/admin/session/new`:
  - viewport fills the window with no white edge;
  - `document.documentElement.scrollHeight` equals the viewport height
    when content fits;
  - submitting a known-bad password keeps the typed email and clears the
    password.
- Browser at `http://localhost:3000/admin` (signed in):
  - sidenav is a left column, main content sits to its right;
  - switching each nav link keeps that layout.

## Risks

- A global `body { margin: 0 }` in `application.css` also applies to
  island pages. Those pages already receive the same reset from
  `shared/styles/tokens.css`, so no visual change is expected; if load
  order ever changes, the rule is still the same value.
- The admin panel currently redefines fonts/tokens locally; this plan
  deliberately does not unify that, to keep the bug-fix diff small.
  The deviation is logged in `fix_me.md` instead.

## Assumptions

- The reported white frame/scrollbar is caused by the default `body`
  margin rather than browser zoom or OS scrollbar styling; confirmed via
  computed styles in the running app.
- The intended admin panel layout is the left sidebar shown in the
  original admin-panel plan/design; the screenshots show it stacked,
  which matches the missing `.admin-shell` flex rule.

## Applicable Styleguides

- `agent/styleguides/core/admin-authentication.md` — governs the
  format-aware HTML login failure path (inline `@error`,
  `:unprocessable_content`) and the request-spec coverage for it; this
  plan only adds value retention to the existing re-render, not a new
  response shape or auth rule.
- `agent/styleguides/core/react-dashboard.md` — governs the
  `admin-panel/` island's own stylesheet placement (`styles/admin-panel.css`)
  and the rule that pure CSS layout changes are verified in a browser
  rather than asserted in jsdom/Vitest; the login page's plain-ERB global
  `body` reset stays in `application.css` because it is outside every
  island and is the only stylesheet the login page loads.
- `agent/styleguides/rspec-conventions.md` — the request-spec level for
  both HTML controllers, `aggregate_failures do ... end` when an example
  has more than three expectations, and rendered-view assertions at the
  request boundary.
- `agent/styleguides/git-commits.md` — commit message format for
  `implement-plan`'s commits.

## Completion Criteria

- The three reported behaviors are fixed.
- The failed-login email retention has request-spec coverage.
- The layout and viewport behavior are verified in a real browser.
- The pre-existing admin-panel token/styles deviation is recorded in
  `fix_me.md`.
- The plan file's `status` is updated by `styleguides-check` and
  `implement-plan`.

## Implementation Summary

**Implemented**

- Added a `body { margin: 0; background: #0c111b; }` reset to
  `app_core/app/assets/stylesheets/application.css`, removing the 8px
  white frame and the extra 16px of document height on the admin login
  page.
- Passed `value: params[:email]` to the login view's email field so a
  failed HTML login re-renders with the entered address (password still
  cleared).
- Added `.admin-shell { display: flex; flex: 1; min-width: 0; }` to
  `app_core/app/frontend/admin-panel/styles/admin-panel.css`, restoring
  the left sidenav + right content layout.
- Logged the pre-existing admin-panel CSS/token deviation in
  `agent/styleguides/fix_me.md` instead of expanding scope.

**Tests**

- RED: extended
  `app_core/spec/requests/admin/sessions_spec.rb`'s bad-credentials
  example to assert the email is retained and the password is not echoed;
  it failed against the old view.
- GREEN: after the view change, the example and the whole
  `app_core` RSpec suite pass.

Commands actually executed:

- `docker run ... bundle exec rspec spec/requests/admin/sessions_spec.rb`
  — 11 examples, 0 failures.
- `docker run ... bundle exec rspec` — 50 examples, 0 failures
  (with `APP_BRIDGE_JWT_SECRET`, `APP_ADMIN_BRIDGE_JWT_SECRET`, and
  `APP_FETCHER_PUBLIC_URL` set and `node_modules` mounted for Vite's test
  build).
- `docker run ... bundle exec rubocop app/controllers/admin/sessions_controller.rb spec/requests/admin/sessions_spec.rb`
  — no offenses.
- `npm run format:check` — clean.
- `npm run lint` — no errors (one pre-existing `react-hooks` warning in
  `tracked_items/TrackedItems.jsx`, unrelated).
- `npm test` — 42 files / 255 tests passed on the final run (one
  unrelated `TrackedItems` timing failure occurred on the first run and
  passed on immediate rerun and on the full rerun).

**Verification**

- Browser, `/admin/session/new` at 1119×837: `body.margin` is `0px`,
  `scrollHeight` equals `innerHeight` (837), dark background reaches the
  viewport edges, no frame/scrollbar.
- Browser, bad credentials: error displays, email stays filled,
  password empty, page still has no extra scroll.
- Browser, signed-in `/admin` at 1119×837: `.admin-shell` computes to
  `display: flex`; sidenav occupies `x=0..217`, main content
  `x=217..1104`, both full height; switching to `#price-log` keeps the
  same geometry.
- Temporary preview container/admin user used for browser verification
  were removed afterward.

**Deviations**

- None from the plan. The full RSpec suite required the same runtime env
  vars CI supplies; the first run without them failed for unrelated
  missing-secret reasons, then passed with them set.

**Remaining Issues**

- The logged admin-panel token/stylesheet deviation remains a separate
  cleanup (the shared token block is scoped to `.dash-root`, so it needs a
  scoping decision before the admin entrypoint can import it).
