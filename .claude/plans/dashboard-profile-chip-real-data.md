---
status: implemented
app: core
goal: Wire STEAM_WEB_API_KEY so real Steam nickname/avatar actually display, and redesign the sign-out control from a click-to-reveal disclosure to a plain icon button
created: 2026-10-04
---

## Applicable Styleguides

- **`.claude/styleguides/core/react-dashboard.md`** — its "Styling"
  section (plain CSS classes in `dashboard.css`, BEM-ish naming, no new
  framework) governs the `.profile-chip`/`.avatar-img`/`.profile-signout`
  CSS changes. Its title scopes it to "the React dashboard island," but
  this same file (`dashboard.css`) already carries the ERB-rendered
  topbar's styles too (the prior `dashboard-single-page-polish` plan's
  styleguide-check already extended this same section to that exact
  topbar/profile-chip area with no objection) — a plain-CSS/BEM-ish
  discipline for one shared stylesheet, not a React-specific rule, so
  it applies here the same way.
- **`.claude/styleguides/rspec-conventions.md`** — confirms `create(:user,
  avatar_url: nil)` (an inline FactoryBot override) is exactly the
  established pattern ("use traits/sequences to express a scenario
  inline rather than hand-naming a new fixture row") for the two new
  `dashboards_spec.rb` examples.
- **`.claude/styleguides/git-commits.md`** — commit format for the
  eventual change (`[Core] ...`).

No styleguide governs ERB/remote-image rendering specifically, and none
is needed: `image_tag` is a built-in Rails helper (not a project
convention with alternatives to choose between), and the fallback logic
is a plain conditional matching the exact style already used one line
away for the nickname fallback (`current_user.nickname.presence ||
"Player"`) — there's no project-specific decision here a styleguide
would need to pin down consistently.

Confirmed during this check: `fix_me.md`'s two `profile_fetcher.rb`
entries (missing sigil, single-quoted requires) correctly stay out of
scope — this plan's Files To Modify list doesn't include that file.

# Development Plan

## Goal

Fix the dashboard topbar so a signed-in user sees their real Steam
nickname and avatar instead of the "Player" fallback and a letter-only
circle, and replace the sign-out disclosure (`<details>/<summary>`,
pill-bordered chip) with a plain, unstyled nickname+avatar and a small
icon-only sign-out button next to it.

## Expected Behavior

### Normal behavior

- With `STEAM_WEB_API_KEY` set to a real key, a fresh Steam login
  populates `nickname`/`avatar_url` on the `User` record (already true
  today via `Steam::LoginUser.call` — only blocked by the missing env
  var), and the topbar shows the real Steam display name and avatar
  image.
- The topbar's nickname/avatar area has no pill border or background —
  just the avatar and name sitting plainly in the topbar.
- A small icon-only button sits directly after the nickname; clicking it
  immediately signs the user out (no intermediate menu/reveal step).

### Edge cases

- `avatar_url` blank (API key missing, Steam API hiccup, or a user who
  signed in before the key existed and hasn't logged in again yet) →
  falls back to today's letter-circle (`.avatar`, first letter of
  nickname, or "?").
- `nickname` blank → falls back to "Player" exactly as today — unchanged.
- A user who already has a stale/blank `nickname`/`avatar_url` from
  before the key was wired up gets corrected automatically on their
  *next* login — `Steam::LoginUser.call` already overwrites both
  unconditionally `if profile`; no backfill job or migration needed.

### Must remain unchanged

- `Steam::ProfileFetcher`/`Steam::LoginUser`/`Steam::Authenticator` —
  zero code changes; the bug is the env var never reaching the process,
  not the Ruby logic.
- The sign-out mechanism itself (`button_to session_path, method: :delete,
  data: { turbo: false }`) — only its visual presentation and trigger
  (icon click vs. disclosure-then-click) changes.
- `docker-compose.yml`'s existing three required vars
  (`APP_FETCHER_PUBLIC_URL`, `APP_BRIDGE_JWT_SECRET`, plus `fetcher_worker`/
  `app_fetcher`'s own vars) — untouched.

## Scope

### In Scope

1. Document `STEAM_WEB_API_KEY` in `.env.example` (same per-var comment
   style as the existing three: what it's for, where it's used, how to
   obtain one).
2. Add `STEAM_WEB_API_KEY` to `docker-compose.yml`'s `app_core` service
   environment block — **as an optional var, not the hard-required
   `${VAR:?...}` pattern the other three use**. `Steam::ProfileFetcher`
   is already written to degrade gracefully on a missing key
   (`return nil if api_key.empty?`) — login still works without it, just
   without real profile data. Copying the `:?` required-syntax would make
   `docker compose up` hard-fail for anyone who hasn't registered a
   Steam Web API key yet, which is a meaningfully bigger ask than the
   other three vars (two are self-generated secrets, one's an internal
   URL) and would contradict the code's own intentional soft-dependency
   design. Plain `${STEAM_WEB_API_KEY}` interpolation (empty string if
   unset, no error) is the correct match for that design.
3. Render the real avatar in `dashboards/show.html.erb`: `image_tag
   current_user.avatar_url` when present, falling back to the existing
   letter-circle markup when blank.
4. Redesign the sign-out control: remove `.profile-menu`
   `<details>/<summary>`; `.profile-chip` loses its pill
   border/background (plain flex row); add a small icon-only sign-out
   button (hand-rolled inline SVG, matching `Chevron`'s house style in
   `FilterDropdown.jsx`/`SortDropdown.jsx`) positioned right after the
   nickname, same `button_to session_path, method: :delete` as today,
   with `aria-label="Sign out"`.
5. New test coverage in `dashboards_spec.rb` for the avatar `<img>` vs.
   fallback-circle branch.

### Out of Scope

- `Steam::ProfileFetcher`/`Steam::LoginUser`/`Steam::Authenticator` code
  changes — the two pre-existing `fix_me.md` entries on
  `profile_fetcher.rb` (missing sigil, single-quoted requires) stay as
  logged, untouched, since this task doesn't otherwise edit that file.
- Any backfill job/migration for users who logged in before the key
  existed — covered by the existing re-populate-on-every-login behavior.
- Enabling/configuring `content_security_policy.rb` — it's fully
  commented-out boilerplate today, so there's no active `img-src`
  restriction to work around. Not touched.
- Actually obtaining a real `STEAM_WEB_API_KEY` value — that requires
  the user to register one at https://steamcommunity.com/dev/apikey and
  add it to their own `.env`; this plan only wires the plumbing.

## Implementation Approach

**Env var.** `.env.example` gets a new documented block for
`STEAM_WEB_API_KEY`, following the existing per-var comment convention.
`docker-compose.yml`'s `app_core` service environment block gets
`STEAM_WEB_API_KEY: ${STEAM_WEB_API_KEY}` — deliberately *not* the
`:?`-required form used by the other three vars, per the reasoning in
Scope item 2.

**Avatar.** In the topbar markup, replace the unconditional letter-circle
with a conditional: `image_tag current_user.avatar_url, alt: ..., class:
"avatar-img"` when `current_user.avatar_url.present?`, else the existing
`<span class="avatar">` letter-circle. `image_tag` is the established
Rails helper for a remote image in this codebase (same technique the
now-deleted `home_pages/index.html.erb` used for the Steam sign-in
button image). New `.avatar-img` CSS mirrors `.avatar`'s existing
26×26px/`border-radius:50%`/`flex-shrink:0` sizing so the two are
visually interchangeable, with `object-fit:cover` since a real Steam
avatar image isn't guaranteed to be perfectly square at every size Steam
serves.

**Sign-out control.** Drop the `<details class="profile-menu">` wrapper
entirely. `.profile-chip` becomes a plain `display:flex; align-items:center;
gap:8px` row (no border/background/border-radius). A new small icon
button sits as a sibling right after `.profile-name`, reusing the
existing `button_to session_path, method: :delete, data: { turbo: false
}` call with `aria-label: "Sign out"` and a hand-rolled inline SVG
(simple door/arrow "exit" glyph, ~14px, `stroke="currentColor"` so it
inherits `--text-muted`/`--text` the same way `Chevron` does) as its
content instead of the text "Sign out" — the `aria-label` attribute
still puts the literal string `"Sign out"` into the rendered HTML, so
`dashboards_spec.rb`'s existing `expect(response.body).to
include("Sign out")` assertion keeps passing unmodified; the
`_method=delete` hidden field assertion is untouched since the
`button_to` call itself doesn't change its method/path. Styles for
`.profile-menu`/`.profile-menu-panel`/`.profile-menu-signout` are
deleted and replaced with one small `.profile-signout` icon-button rule.

## Files To Modify

- `.env.example` — document `STEAM_WEB_API_KEY`.
- `docker-compose.yml` — add `STEAM_WEB_API_KEY: ${STEAM_WEB_API_KEY}` to
  the `app_core` service's environment block.
- `app_core/app/views/dashboards/show.html.erb` — conditional
  `image_tag`/letter-circle for the avatar; replace the
  `<details>/<summary>` sign-out disclosure with a plain `.profile-chip`
  row + icon-only sign-out button.
- `app_core/app/frontend/dashboard/styles/dashboard.css` — remove
  `.profile-chip`'s pill border/background; remove
  `.profile-menu`/`.profile-menu-panel`/`.profile-menu-signout`; add
  `.avatar-img` and `.profile-signout`.
- `app_core/spec/requests/dashboards_spec.rb` — add the avatar
  present/blank scenarios.

## Files To Create

None.

## Test Plan

In `dashboards_spec.rb`'s existing `"when signed in"` describe block
(`let(:user) { create(:user) }`, which per `spec/factories/users.rb`
already defaults `avatar_url` to a non-blank URL):

- New example: with the default factory user (non-blank `avatar_url`),
  `GET /` response body includes an `<img` tag whose `src` matches the
  user's `avatar_url`.
- New example: with `let(:user) { create(:user, avatar_url: nil) }`,
  response body does *not* include an `<img` tag for the avatar and
  still includes the letter-circle fallback markup (e.g. the
  `class="avatar"` span with the nickname's first letter).
- No change needed to the existing `"includes a sign-out control"`
  test — verify after implementation that it still passes unmodified
  (it asserts on `"Sign out"` substring and the delete-method hidden
  field, both still present via `aria-label` and the unchanged
  `button_to` call).

## Implementation Steps

1. `.env.example`: add the `STEAM_WEB_API_KEY` doc block.
2. `docker-compose.yml`: add `STEAM_WEB_API_KEY: ${STEAM_WEB_API_KEY}`
   to `app_core`'s environment.
3. Write the two new `dashboards_spec.rb` examples (avatar present /
   blank) against the *current* view (RED — no `<img>` exists yet).
4. `dashboards/show.html.erb`: add the conditional avatar `image_tag`/
   fallback; replace the disclosure with the plain chip + icon
   sign-out button.
5. `dashboard.css`: strip `.profile-chip`'s pill styling; delete
   `.profile-menu*` rules; add `.avatar-img`/`.profile-signout`.
6. Run the full spec suite, confirm the two new examples pass (GREEN)
   and the existing `"includes a sign-out control"` example still
   passes unmodified.
7. Manual verification (see Verification) since no real Steam login is
   available in this environment.

## Verification

- `bundle exec rspec` (full `app_core` suite).
- `bin/rubocop` on touched Ruby files (none this time — only ERB/CSS/
  YAML/env file, rubocop doesn't lint those).
- Manual check in a browser: signed-in dashboard (via the existing
  `allow_any_instance_of(ApplicationController).to
  receive(:current_user)`-style stub used in specs isn't available
  live, so — same limitation as prior plans — verify via a temporary
  static fixture built from the real `dashboard.css`, covering: chip
  with no border/background, avatar image rendering at the right size/
  shape next to a fallback-letter-circle comparison, and the icon
  sign-out button's size/spacing/hover state.
- Confirm `docker compose up app_core` still starts cleanly with
  `STEAM_WEB_API_KEY` absent from `.env` (proving it's genuinely
  optional, not a new hard requirement that would break the existing
  dev setup).

## Risks

- Copying the other three vars' `${VAR:?...}` hard-required syntax for
  `STEAM_WEB_API_KEY` would be a real regression — it would make
  `docker compose up` refuse to start for anyone without a Steam Web API
  key, which is a much higher bar than this app has ever required to
  simply run. Explicitly using plain `${STEAM_WEB_API_KEY}` interpolation
  avoids this; confirmed via Verification's docker-compose-still-starts
  check.
- The user still needs to supply their own real key and sign in again
  before they'll see their own real nickname/avatar — this plan fixes
  the plumbing, not their personal `.env`.
- A Steam avatar image can be non-square at some sizes Steam serves;
  `object-fit:cover` on a fixed 26×26 box handles this, but wasn't
  visually confirmed against a *real* Steam avatar image in this
  environment (no real login available) — only against a placeholder
  image URL in the manual fixture.

## Assumptions

None — every open question from research was resolved by reading the
actual code.

# Implementation Summary

## Implemented

- `.env.example`: documented `STEAM_WEB_API_KEY`, same per-var
  comment-block style as the other three, noting it's optional and
  linking https://steamcommunity.com/dev/apikey.
- `docker-compose.yml`: added `STEAM_WEB_API_KEY: ${STEAM_WEB_API_KEY}`
  to `app_core`'s environment — deliberately plain interpolation, not
  the `${VAR:?...}` hard-required form the other three vars use.
- `dashboards/show.html.erb`: replaced the `<details class="profile-menu">`
  disclosure with a plain `.profile-group` (profile-chip + icon button).
  `.profile-chip` now conditionally renders `image_tag
  current_user.avatar_url, class: "avatar-img"` when present, falling
  back to the existing letter-circle `<span class="avatar">` when blank.
  The sign-out `button_to` moved out of a menu panel to a direct sibling
  icon button (hand-rolled inline SVG door+arrow glyph, matching the
  `Chevron` house style), with `aria: { label: "Sign out" }`.
- `dashboard.css`: `.profile-chip` lost its pill border/background
  (plain flex row); added `.profile-group` (holds chip + icon button
  together so `.topbar`'s `justify-content: space-between` doesn't
  misplace a third item — the exact bug class fixed in the earlier
  Filters-badge fix); added `.avatar-img` (same 26×26/circular sizing as
  `.avatar`, `object-fit: cover`); added `.profile-signout` (24×24 icon
  button, subtle `--text-faint` color, hover background); removed
  `.profile-menu`/`.profile-menu-panel`/`.profile-menu-signout`.

## Tests

- `dashboards_spec.rb`, within the existing `"when signed in"` block:
  one new example asserting the response body includes an `<img
  src="...">` matching the factory user's (non-blank by default)
  `avatar_url`; one new nested context with `create(:user, avatar_url:
  nil)` asserting no `.avatar-img` tag appears and the letter-circle
  fallback is still present.
- Written RED-first (confirmed 1 failure — the avatar-present example,
  for the expected reason: no `<img>` existed in the pre-change view —
  the avatar-blank example passed immediately since the letter-circle
  was already the only thing ever rendered), then GREEN after the view
  change.
- Existing `"includes a sign-out control"` example verified to still
  pass unmodified — the `aria-label="Sign out"` attribute satisfies its
  `include("Sign out")` assertion, and the unchanged `button_to
  method: :delete` call satisfies the `_method=delete` assertion.

Commands executed: `bundle exec rspec spec/requests/dashboards_spec.rb`
(RED, then GREEN), `bundle exec rspec` (full suite), `bundle exec
rubocop` (full repo).

## Verification

- `bundle exec rspec`: 8 examples, 0 failures (full `app_core` suite;
  was 6 before this plan's 2 new examples).
- `bundle exec rubocop`: same 22 pre-existing offenses as before, all in
  files this plan didn't touch; zero in `.env.example`,
  `docker-compose.yml`, or the ERB/CSS files this plan did touch (rubocop
  doesn't lint those file types anyway).
- Confirmed the key architectural point from the plan directly, not just
  by code review: running `docker compose run --rm app_core bundle exec
  rspec ...` with `STEAM_WEB_API_KEY` absent from `.env` printed
  `The "STEAM_WEB_API_KEY" variable is not set. Defaulting to a blank
  string.` as a **warning** and proceeded normally — it did not refuse
  to start, proving the plain-interpolation choice over the
  hard-required `:?` form was correct.
- Manual check via the running `app_core` dev server: real signed-out
  page screenshot unaffected (confirms no regression). For the
  signed-in topbar (no real Steam login available in this environment),
  built a temporary static fixture from the real compiled `dashboard.css`
  with two rows — a real fetched Steam CDN avatar image (confirmed via
  `img.complete`/`img.naturalWidth` in-page, not just visually — the
  network request returned `200` and the image genuinely decoded) and
  the no-avatar letter-circle fallback — both rendered with no pill
  border, and the new icon-only sign-out button correctly positioned
  immediately after the nickname. Fixture deleted after verification,
  never committed.

## Deviations

None — implementation matched the plan exactly, including the
plain-vs-required env var interpolation choice.

## Remaining Issues

- The user still needs to obtain a real `STEAM_WEB_API_KEY` from
  https://steamcommunity.com/dev/apikey, add it to their own `.env`
  (gitignored, not touched by this change), and sign in again — their
  existing `User` row will be corrected automatically on that next login
  via `Steam::LoginUser.call`'s existing unconditional overwrite, no
  further action needed beyond that.
- Same non-blocking `react-dashboard.md` stale-example note carried over
  from prior plans still stands (unrelated to this change).
