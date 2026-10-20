---
status: implemented
app: core
goal: Auto-dismiss rendered flash toasts after a short delay instead of leaving them on screen until the next request
created: 2026-10-20
---

# Development Plan

## Goal

Make the flash toasts rendered by `shared/_flash.html.erb` disappear on
their own after a short delay, so a message shown after login/logout does
not stay pinned to the page for as long as the user remains there.

## Expected Behavior

**Normal behavior**

- A flash notice/alert still renders on the redirected page exactly as it
  does today (same copy, variant, `role`, fixed-position stack).
- After a short readable delay (5 seconds), each toast starts fading out
  and is removed from the DOM; an empty `.flash-stack` wrapper collapses
  and is not visible.
- The delay is defined once and carried by the rendered markup, not
  duplicated per page.
- The behavior is app-wide, because flash is rendered by
  `application.html.erb` and the controller is loaded by the layout.

**Edge cases**

- Several flash entries render several cards; each card dismisses itself
  independently on the same delay.
- Navigating to another page before the delay expires still works: the
  old page is discarded and the new page's flash (if any) starts its own
  timer.
- `prefers-reduced-motion: reduce` disables the fade transition; the card
  is still removed after the delay.
- A page with no flash loads no toast and no timer.
- If JavaScript fails to load, flash remains visible (graceful
  degradation: the current behavior, not a blank message).

**Behavior that must remain unchanged**

- Flash copy, notice/alert mapping, ARIA roles, blank filtering, and the
  no-flash empty wrapper behavior.
- Controller redirects, session writes, and admin inline `@error` handling.
- No server-side flash consumption/`flash.discard` change; the toast still
  naturally expires server-side on the next request.

## Applicable Styleguides

- `agent/styleguides/core/erb-interaction-patterns.md` — owns the flash
  toast and now documents the Stimulus auto-dismiss: controller/entrypoint
  locations, 5-second delay, fade-out + DOM removal, timer cleanup,
  reduced-motion handling, and the request-spec/Vitest split. This plan
  follows that amended rule.
- `agent/adr/core/erb-overlays-over-stimulus.md` — already names a timer
  as the genuine trigger for introducing Stimulus; this plan is that
  first case, so no new ADR is needed.
- `agent/styleguides/core/react-dashboard.md` — entrypoint naming,
  ESLint/Prettier, and Vitest conventions for the new frontend files
  (even though this is app chrome, not a React island).
- `agent/styleguides/ci-and-coverage.md` — run the verification through
  the Docker Compose CI override, including `vitest`.
- `agent/styleguides/rspec-conventions.md` — request-spec coverage for
  the rendered flash markup.

## Scope

### In Scope

- A small Stimulus controller that schedules auto-dismiss for each toast.
- A global Vite entrypoint that starts Stimulus and registers the
  controller, loaded from `application.html.erb`.
- Wiring the flash partial with `data-controller` / delay data.
- CSS for the fade-out state and empty-stack collapse.
- A Vitest unit test for the controller and a request-spec assertion that
  the partial is wired to it.
- Updating `agent/styleguides/core/erb-interaction-patterns.md` so the
  documented flash rule matches the new behavior.

### Out of Scope

- Manual close buttons, hover/focus pause, or a visible countdown.
- Moving flash rendering out of the layout, Turbo Streams, or per-page
  flash handling.
- Changing flash message copy, controller flows, or session behavior.
- Migrating the React islands to Stimulus or adding Turbo behavior.

## Implementation Approach

1. Add `@hotwired/stimulus` as an `app_core` npm dependency (the
   `stimulus-rails` gem is already present but the app has no importmap;
   Vite needs the npm package), updating `package.json` and
   `package-lock.json`.
2. Add `app/frontend/controllers/flash_controller.js`:
   - `static values = { delay: Number }` with a 5-second default;
   - on `connect`, schedule dismissal;
   - on timeout, add an `is-leaving` class, then remove the card after the
     CSS transition (with `disconnect` clearing pending timers).
3. Add `app/frontend/entrypoints/flash.js`: start a Stimulus
   `Application` and register the controller as `flash`. This is a global
   chrome entrypoint, not an island entrypoint.
4. Render `vite_javascript_tag "flash"` once in
   `app_core/app/views/layouts/application.html.erb` so every page using
   the layout gets the controller.
5. Add `data-controller="flash"` and
   `data-flash-delay-value="5000"` to each `.flash` card in
   `shared/_flash.html.erb`.
6. Add `.flash.is-leaving` transition styles plus
   `.flash-stack:empty { display: none; }` to `application.css`, keeping
   the reduced-motion guard covering the new transition.
7. Add `app/frontend/controllers/__tests__/flash_controller.test.js`
   using Vitest fake timers and a real Stimulus `Application`; assert the
   card gets the leaving class after the delay, is removed after the exit
   duration, and does not dismiss when the controller disconnects early.
8. Extend `app_core/spec/requests/sessions_spec.rb` to assert the
   rendered notice/alert markup is wired to the controller (the request
   spec cannot execute JS, so behavior stays in the Vitest test).
9. Update the flash section of
   `agent/styleguides/core/erb-interaction-patterns.md`: describe the
   Stimulus auto-dismiss, the 5-second default, DOM removal, and the
   Vitest + request-spec split; replace the old zero-JS MUST rule.

## Files To Modify

- `app_core/package.json`, `app_core/package-lock.json`
  - Add `@hotwired/stimulus`.
  - Reason: Vite must bundle the Stimulus runtime for the first
    controller.
- `app_core/app/views/layouts/application.html.erb`
  - Load `vite_javascript_tag "flash"` once.
  - Reason: flash is rendered app-wide from the layout, so its controller
    must load app-wide too.
- `app_core/app/views/shared/_flash.html.erb`
  - Add `data-controller` and delay value to each card.
  - Reason: connects the server-rendered toast to the controller without
    per-page JS.
- `app_core/app/assets/stylesheets/application.css`
  - Add the leaving transition, empty-stack collapse, and include the
    transition in the reduced-motion guard.
  - Reason: visual fade/cleanup belongs with the existing toast styles.
- `app_core/spec/requests/sessions_spec.rb`
  - Assert the flash cards expose the Stimulus wiring.
  - Reason: proves the layout/partial integration, which the JS unit test
    cannot.
- `agent/styleguides/core/erb-interaction-patterns.md`
  - Replace the no-auto-dismiss rule with the Stimulus timer rule.
  - Reason: the existing MUST would otherwise forbid the fix.

## Files To Create

- `app_core/app/frontend/controllers/flash_controller.js`
  - Responsibility: schedule per-card dismissal and remove the element
    after the exit transition.
  - Reason: the timer/removal behavior cannot be expressed reliably by
    CSS alone without leaving hidden content in the accessibility tree.
- `app_core/app/frontend/entrypoints/flash.js`
  - Responsibility: start Stimulus and register the flash controller.
  - Reason: the layout needs a single global JS entrypoint for chrome
    behavior, separate from the React island entrypoints.
- `app_core/app/frontend/controllers/__tests__/flash_controller.test.js`
  - Responsibility: verify timing, exit state, DOM removal, and timer
    cleanup with fake timers.
  - Reason: request specs cannot execute the timer; this is the behavior
    under test.

## Test Plan

Vitest (`app/frontend/controllers/__tests__/flash_controller.test.js`):

- Mount a `.flash` element with `data-controller="flash"` and a short
  delay; advance fake timers by the delay and assert `is-leaving` is
  added.
- Advance by the exit duration and assert the element is removed.
- Disconnect the controller/application before the delay and assert the
  element is not marked leaving after the delay (pending timers cleared).

RSpec (`app_core/spec/requests/sessions_spec.rb`):

- Existing notice/alert assertions additionally assert
  `data-controller="flash"` and the delay value on the card.
- Existing no-flash assertion stays unchanged.

## Implementation Steps

1. Add the Stimulus npm dependency and install it locally.
2. Write the failing Vitest test for the flash controller.
3. Implement `flash_controller.js`.
4. Implement the global Stimulus entrypoint.
5. Wire the partial and layout.
6. Add the CSS leaving/empty-stack rules.
7. Extend the request spec for the data attributes.
8. Update the interactive-patterns styleguide flash rule.
9. Run Vitest, the request specs, the full `app_core` suite, ESLint,
   Prettier, RuboCop, and Sorbet through the Docker Compose CI override.

## Verification

Through the root `docker compose -f docker-compose.yml -f
docker-compose.ci.yml` setup:

- `npm run test -- --run app/frontend/controllers/__tests__/flash_controller.test.js`
- `npm run test:coverage` (full frontend suite)
- `bundle exec rspec spec/requests/sessions_spec.rb`
- `bundle exec rspec` (full `app_core` suite)
- `npm run lint`
- `npm run format:check`
- `bundle exec rubocop` (changed Ruby/spec files)
- `bundle exec srb tc`
- Manual browser check through the dev stack: log in, log out, and force
  a failed login; each toast should disappear after ~5 seconds, and a
  normal page load should show none.

## Risks

- Adding a layout-wide Vite entrypoint means every response references
  it; the entrypoint must exist in the Vite manifest in development,
  test, and production. Verify request specs still render.
- Removing the element while a screen reader is announcing an alert could
  cut off the announcement; 5 seconds is long enough for the existing
  short messages. This is the same trade-off any auto-dismissing toast
  makes.
- Timer cleanup must clear both the dismissal and removal timeouts, or a
  disconnected element could throw on removal.
- The first Stimulus controller adds a small JS layer to app chrome; keep
  it limited to this one concern and register it from the single global
  entrypoint.

## Assumptions

- A 5-second auto-dismiss delay is appropriate for the current short
  login/logout messages.
- No manual close control is required; the reported problem is that
  messages never go away, not that they cannot be dismissed early.
- JavaScript is available on the pages that render flash; without it, the
  existing persistent behavior remains.

## Completion Criteria

- Flash notices/alerts still render with unchanged copy, variant, and
  ARIA role.
- Each rendered toast fades out and is removed from the DOM after the
  configured delay.
- Multiple messages dismiss independently; the empty stack is invisible.
- Reduced-motion users get no transition but still get DOM removal.
- Request specs prove the markup wiring; Vitest proves the timer/removal
  behavior.
- The styleguide no longer forbids the implemented behavior.
- Relevant frontend lint/format/tests and Ruby specs/lint/type checks are
  green.

# Implementation Summary

## Implemented

- `app_core/package.json` / `package-lock.json` — added
  `@hotwired/stimulus` (the gem was already present, but this app uses
  Vite rather than importmap, so the runtime comes from npm).
- `app_core/app/frontend/controllers/flash_controller.js` — the `flash`
  Stimulus controller. It reads `data-flash-delay-value`, schedules
  dismissal (5000 ms default), adds `is-leaving` for the CSS fade, then
  removes the card after 180 ms. `disconnect` clears both timers.
- `app_core/app/frontend/entrypoints/flash.js` — global chrome
  entrypoint that starts Stimulus and registers the controller.
- `app_core/app/views/layouts/application.html.erb` — loads the entrypoint
  once through `vite_javascript_tag "flash"` for every layout page.
- `app_core/app/views/shared/_flash.html.erb` — each notice/alert card
  now carries `data-controller="flash"` and
  `data-flash-delay-value="5000"`.
- `app_core/app/assets/stylesheets/application.css` — added the
  `is-leaving` opacity/translate transition, hid an emptied
  `.flash-stack`, and disabled the new transition under
  `prefers-reduced-motion`.
- `agent/styleguides/core/erb-interaction-patterns.md` — replaced the
  no-auto-dismiss MUST rule with the Stimulus timer rule, including
  controller/entrypoint locations, progressive-enhancement expectation,
  timer cleanup, and the Vitest/request-spec split.
- `app_core/spec/requests/sessions_spec.rb` — notices and alerts now also
  assert the Stimulus wiring and delay attribute.

## Tests

- Added `app_core/app/frontend/controllers/__tests__/flash_controller.test.js`
  with three Vitest cases:
  - the card gets `is-leaving` after the configured delay;
  - the card is removed after the exit duration;
  - a disconnected controller does not dismiss a detached card.
- First Vitest run was RED (`Failed to resolve import
  "../flash_controller"`); after implementing the controller and
  entrypoint the file passed 3/3.
- Extended `app_core/spec/requests/sessions_spec.rb` to assert the partial
  is wired to the controller.

Commands executed:

- `npx vitest run app/frontend/controllers/__tests__/flash_controller.test.js`
- `npm test` — 53 files, 314 tests passed.
- `npm run lint` — no errors; one pre-existing warning in
  `app_core/app/frontend/tracked_items/TrackedItems.jsx`
  (`react-hooks/exhaustive-deps`), unrelated to this change.
- `npm run format:check` — all files pass.
- Docker Compose CI override, `app_core` service:
  - `bundle exec rspec spec/requests/sessions_spec.rb` — 5 examples, 0
    failures.
  - `bundle exec rspec` — 74 examples, 0 failures.
  - `bin/rubocop spec/requests/sessions_spec.rb` — no offenses.
  - `bundle exec srb tc` — no errors.

## Verification

- Request specs confirm the rendered notice/alert markup still has the
  expected copy, role, and now the Stimulus data attributes.
- Vitest confirms the actual timer behavior, exit state, DOM removal, and
  timer cleanup.
- The full `app_core` RSpec suite, RuboCop on the changed spec, Sorbet,
  frontend tests, lint, and format check are green.
- The Docker image was rebuilt with the new npm dependency, and the
  request specs resolved the `flash` Vite entrypoint successfully.
- Manual browser verification was not performed in this session.

## Deviations

None. The styleguide was amended before implementation, as the
styleguides-check gate required.

## Remaining Issues

- Auto-dismiss has no manual close control and does not pause on hover or
  focus; this matches the approved scope.
- If JavaScript fails to load, the toast stays visible, which is the
  intended progressive-enhancement fallback.
