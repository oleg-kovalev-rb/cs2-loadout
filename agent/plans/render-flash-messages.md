---
status: implemented
app: core
goal: Render the notice/alert flash messages set by the Steam login flow through a shared, styled, accessible layout partial instead of dropping them
created: 2026-10-19
---

# Development Plan

## Goal

Make `app_core` actually display the `flash[:notice]` / `flash[:alert]`
messages that `SessionsController#callback` and `#destroy` already set, by
rendering them from `application.html.erb` with a shared, accessible,
visually consistent flash component.

## Expected Behavior

**Normal behavior**

- A successful Steam callback (`Welcome, <nickname>!`) redirects to the
  dashboard as before, and the dashboard now shows that message.
- A failed Steam callback (`Login failed. Please try again.` or
  `Internal server error during login.`) redirects to the dashboard as
  before, and the dashboard now shows that message.
- Signing out (`Logged out.`) redirects to the dashboard as before, and
  the dashboard now shows that message.
- `notice` messages are presented as non-urgent status content
  (`role="status"`); `alert` messages are presented as urgent content
  (`role="alert"`), so assistive technology announces them appropriately.
- The message is visually consistent with the existing dark dashboard /
  admin palette: a compact toast card with a coloured accent, high
  contrast text, and a subtle entrance animation.
- The toast is fixed-position, so showing a flash does not push the page
  content down or shift the topbar.

**Edge cases**

- A request with no flash renders no flash container at all (no empty
  wrapper, no stray spacing).
- A flash entry with a blank/nil message is not rendered.
- More than one flash entry in the same request renders multiple cards in
  a vertical stack.
- Unknown flash keys are treated as notices rather than producing an
  unstyled/unsafe class name.
- Message bodies are HTML-escaped by ERB, exactly like any other
  user-derived text.
- `prefers-reduced-motion: reduce` disables the entrance animation.
- On narrow viewports the toast stays inside the viewport rather than
  overflowing off-screen.

**Behavior that must remain unchanged**

- `SessionsController#create`/`#callback`/`#destroy` redirect targets,
  status codes, session writes, rescue branches, and log messages.
- The admin login form keeps its inline `@error` on bad credentials — it
  re-renders the form in the same request, where an inline message next
  to the form is clearer than a redirected flash.
- No React island behavior or data flow changes.

## Applicable Styleguides

- `agent/styleguides/core/erb-interaction-patterns.md` — the flash
  pattern itself: layout-level shared partial, notice/alert role mapping,
  blank/no-flash handling, zero-JS constraint, token-based fixed-position
  styling, and request-spec coverage.
- `agent/styleguides/core/architecture-layers.md` — flash belongs to the
  shared ERB chrome (`shared/` partial rendered by the layout), not to a
  controller action or React island; no new layer is introduced.
- `agent/styleguides/rails-layering.md` — keeps `SessionsController`
  thin and unchanged; the work stays in rendering.
- `agent/styleguides/rspec-conventions.md` — request-spec level,
  explicit `type: :request`, stubbing only the `Steam::LoginUser`
  boundary, and example/granularity rules.
- `agent/styleguides/core/admin-authentication.md` — the admin login
  failure stays inline via `@error`; rendering flash app-wide must not
  change that flow.
- `agent/styleguides/ci-and-coverage.md` — verify through the
  Docker Compose setup CI uses rather than bare-host commands.

## Scope

### In Scope

- A shared flash partial rendered by the application layout, so every
  page using that layout gets flash support.
- Global flash styling in `app_core/app/assets/stylesheets/application.css`.
- Request-spec coverage for the Steam login/sign-out flows actually
  setting and rendering flash messages.
- Removing the now-resolved `application.html.erb` entry from
  `agent/styleguides/fix_me.md`.

### Out of Scope

- Converting the admin login failure path from inline `@error` to
  `flash`.
- Auto-dismiss, a close button, timers, Turbo Streams, or any JavaScript
  for flash behavior.
- Adding new flash keys/statuses, notifications for the React islands, or
  a flash API for `app_fetcher`.
- Changing any controller flow, message copy, or authentication logic.

## Implementation Approach

1. **Shared partial** — add
   `app_core/app/views/shared/_flash.html.erb`. It reads `flash`, skips
   blank messages, maps `alert` to alert styling/`role="alert"` and every
   other key (currently `notice`) to notice styling/`role="status"`, and
   renders a `.flash-stack` wrapper only when at least one message is
   present. This keeps the presentation in one place and mirrors the
   existing `shared/_topbar.html.erb` chrome-partial convention.
2. **Layout** — render `shared/flash` at the start of `<body>` in
   `app_core/app/views/layouts/application.html.erb`. A layout-level
   render is what closes the actual bug for every current and future
   page, including admin pages, without remembering to add the partial to
   each view.
3. **Styling** — add the `.flash-stack` / `.flash` rules to
   `application.css` (loaded by the layout on every page). Use the
   existing palette values with token fallbacks, fixed top-right
   positioning below the topbar, a notice/alert accent variant, a
   reduced-motion guard, and a mobile breakpoint that spans the available
   width.
4. **Tests** — add a request spec that exercises the real controller
   boundary. Stub `Steam::LoginUser` only to drive the controller's
   success/failure branches; no outbound Steam HTTP is involved. Follow
   the redirect and assert the rendered message plus its
   status/alert role. Cover a notice and an alert so both variants are
   proven, and assert the flash markup is absent on a request with no
   flash.
5. **Fix-me cleanup** — delete the `application.html.erb` flash entry
   from `agent/styleguides/fix_me.md`, since this change resolves it.

## Files To Modify

- `app_core/app/views/layouts/application.html.erb`
  - Render `shared/flash` inside `<body>` before `yield`.
  - Reason: the layout is the one place every response shares, and the
    bug is precisely that this file never outputs `flash`.
- `app_core/app/assets/stylesheets/application.css`
  - Add the global flash stack/card styles.
  - Reason: plain ERB chrome styling lives in this manifest, not in a
    React island stylesheet; the partial must look right on every page
    using the layout.
- `agent/styleguides/fix_me.md`
  - Remove the resolved `application.html.erb` flash entry.
  - Reason: `implement-plan` requires an entry to be removed once its
    file is brought into compliance.

## Files To Create

- `app_core/app/views/shared/_flash.html.erb`
  - Responsibility: iterate the current flash, filter blank entries, and
    render accessible notice/alert toast cards.
  - Reason: keeps the layout tidy and gives the flash presentation a
    single shared home, just like the shared topbar partial.
- `app_core/spec/requests/sessions_spec.rb`
  - Responsibility: verify the login/sign-out flows end with the
    expected flash message rendered on the redirected page.
  - Reason: no request spec currently covers `SessionsController`, so
    the regression would otherwise remain untested.

## Test Plan

Add `app_core/spec/requests/sessions_spec.rb` (`type: :request`):

- `GET /session/callback` success: stub `Steam::LoginUser.call` to return
  a `User`, follow the redirect, and assert the body contains the
  `Welcome, <nickname>!` copy inside the notice styling and that the
  element exposes `role="status"`.
- `GET /session/callback` with `Steam::AuthError`: stub the action to
  raise, follow the redirect, and assert the `Login failed. Please try
  again.` copy inside the alert styling and that the element exposes
  `role="alert"`.
- `DELETE /session`: follow the redirect and assert `Logged out.` is
  rendered as a notice. This also exercises the destroy flow's flash.
- Assert the flash wrapper/cards are absent on a normal request with no
  flash (e.g. the existing dashboard GET, either in this spec or by
  extending `spec/requests/dashboards_spec.rb`).
- Keep each scenario as its own example; use an `aggregate_failures`
  block when an example needs more than three expectations.
- Stub `Steam::LoginUser` (the orchestration boundary) only in examples
  whose subject is controller flash behavior. Do not hand-write a Steam
  HTTP stub and do not exercise the real Steam API.

## Implementation Steps

1. Write the failing request spec for callback success, callback auth
   failure, sign-out, and the no-flash case.
2. Run it and confirm it fails because the messages are missing from the
   rendered response.
3. Add `shared/_flash.html.erb` with the filtered iteration, notice/alert
   mapping, and accessible roles.
4. Render the partial from `application.html.erb`.
5. Add the `.flash-stack` / `.flash` styles to `application.css`,
   including the notice/alert accents, mobile layout, and reduced-motion
   handling.
6. Re-run the request specs until green.
7. Remove the resolved entry from `agent/styleguides/fix_me.md`.
8. Run the app's relevant verification steps (specs, RuboCop, Sorbet,
   frontend format/lint if touched).

## Verification

From `app_core/` (or through the Docker Compose setup used by CI):

- `bundle exec rspec spec/requests/sessions_spec.rb spec/requests/dashboards_spec.rb`
- `bundle exec rspec` (full `app_core` suite)
- `bundle exec rubocop app_core/...` for the changed Ruby/spec files
  (the layout/partial/CSS are not Ruby, but the spec is)
- `bundle exec srb tc`
- `npm run format:check` only if any frontend JS/CSS under Vite is
  touched — this plan touches only `app/assets`, not the React
  stylesheets, so it is expected to be unaffected.
- Manual check in the browser: sign-in success, sign-in failure, and
  sign-out each show exactly one toast; a normal page load shows none.

## Risks

- A fixed toast can overlap page content at the top right. Position it
  below the topbar and keep the card compact; it is transient/short-
  lived, and the layout must not be shifted by it.
- The Flash hash may contain keys beyond `notice`/`alert` in the future;
  the partial must default safely rather than interpolating arbitrary
  keys into CSS classes.
- `follow_redirect!` request specs depend on the redirected page
  rendering successfully (the dashboard needs `APP_FETCHER_PUBLIC_URL`),
  which the existing request specs already rely on.
- A layout-level flash partial adds markup to the admin login/panel
  pages too. Their current flows set no flash, so the partial must render
  nothing when flash is empty; this is explicitly tested.

## Assumptions

- An inline toast is preferable to an in-flow banner for this app because
  it avoids moving the dashboard/topbar and works uniformly from the
  shared layout.
- `notice`/`alert` remain the only flash keys in use for the Steam login
  flow; unknown keys are defensively treated as notices.
- No auto-dismiss is required: a flash naturally disappears on the next
  request, and adding a timer/close control would introduce JavaScript
  or a CSS-only interaction that this small fix does not need.

## Completion Criteria

- Login success, login failure, and logout messages are visible on the
  redirected page.
- Notice and alert messages are visually distinct and expose the correct
  ARIA role.
- No flash renders nothing at all.
- The existing controller redirects, messages, and admin inline-error
  behavior are unchanged.
- New request specs fail without the layout/partial change and pass with
  it.
- The `fix_me.md` entry for the layout is removed.
- Relevant specs, RuboCop, and Sorbet are green.

# Implementation Summary

## Implemented

- `app_core/app/views/shared/_flash.html.erb` — new shared flash
  partial. It filters blank messages, renders `.flash-notice` /
  `role="status"` for `notice` (and any non-`alert` key) and
  `.flash-alert` / `role="alert"` for `alert`, and renders nothing when
  there is no flash.
- `app_core/app/views/layouts/application.html.erb` — renders the shared
  flash partial once at the start of `<body>`, so every page using the
  layout now displays flash messages.
- `app_core/app/assets/stylesheets/application.css` — added the global
  fixed-position toast styles: notice/alert accents, existing palette
  tokens with fallbacks, mobile width handling, entrance animation, and
  a `prefers-reduced-motion` opt-out.
- `agent/styleguides/fix_me.md` — removed the resolved
  `application.html.erb` flash entry.
- `agent/styleguides/core/erb-interaction-patterns.md` — added the flash
  toast pattern and its rules/testing guidance.
- `agent/styleguides/core/admin-authentication.md` — replaced the stale
  "no layout renders flash" rationale with the durable same-request
  form-error reason.

## Tests

- Added `app_core/spec/requests/sessions_spec.rb` covering:
  - successful callback → `Welcome, Oleg!` notice with `role="status"`;
  - rejected callback → `Login failed. Please try again.` alert with
    `role="alert"`;
  - sign-out → `Logged out.` notice with `role="status"`;
  - a request with no flash renders no `.flash-stack`.

Commands executed (through Docker Compose, `app_core` container,
`RAILS_ENV=test`, CI dummy env values):

- `bundle exec rspec spec/requests/sessions_spec.rb` — first run failed
  with the expected missing-flash assertions (RED), final run: 4
  examples, 0 failures.
- `bundle exec rspec` — 43 examples, 0 failures.
- `bundle exec rubocop spec/requests/sessions_spec.rb` — 1 file, no
  offenses.
- `bundle exec srb tc` — no errors.

## Verification

- The new request specs prove both notice and alert variants render on
  the redirected page, and that a flash-less request renders no wrapper.
- Full `app_core` RSpec suite is green.
- RuboCop and Sorbet are green.
- Frontend lint/format was not run because the change does not touch
  `app/frontend/`; the new CSS lives in the Propshaft manifest.
- Manual browser verification was not performed in this session.

## Deviations

None.

## Remaining Issues

- The toast intentionally has no dismiss/auto-hide control (zero-JS
  rule); it disappears on the next request. This is recorded in
  `agent/styleguides/core/erb-interaction-patterns.md` rather than left
  implicit.
