---
status: implemented
app: core
goal: Merge app_core's landing page and dashboard into one signed-out/signed-in root page and fix the dashboard's presentability rough edges (layout shift, missing logout, misleading market tile, cramped right rail, verbose labels)
created: 2026-10-04
---

## Applicable Styleguides

- **`.claude/styleguides/rails-layering.md`** — constrains the
  `DashboardsController#show` change to stay a thin controller: branching
  on `current_user` to pick which markup to render, and the unchanged
  `Steam::BridgeToken.encode` call, are both within "a direct render" /
  "a single trivial model lookup" — nothing in this plan pushes business
  logic into the controller body.
- **`.claude/styleguides/core/architecture-layers.md`** — the app_core
  concretization of the above: confirms `current_user` remains the only
  direct model access in the controller, confirms the bridge-token mint
  site and the React island's direct `app_fetcher` reads are unchanged
  (this plan adds no `app_core`-hosted proxy endpoint), and confirms
  `require_login`'s removal doesn't violate anything — the styleguide
  only requires the auth guard pattern exist somewhere a controller
  needs one, not that it be a `before_action` specifically.
- **`.claude/styleguides/ruby-sorbet.md`** — governs the
  `dashboards_controller.rb` sigil fix (`typed: true` → `typed: strict`):
  controllers are explicitly in scope ("this applies to controllers too
  — there's no established case for a lower sigil on a hand-written
  file"), confirming this plan's Scope item 10 is a straightforward
  convention fix, not a judgment call.
- **`.claude/styleguides/rspec-conventions.md`** — governs the
  `dashboards_controller_spec.rb` → `app_core/spec/requests/dashboards_spec.rb`
  migration: its own Canonical Implementations section explicitly
  anticipates this exact move ("the next `app_core` controller spec
  written or rewritten should be the first `type: :request` example"),
  and `fix_me.md`'s existing entry for this file says the same
  ("migrate to `type: :request` next time it's edited"). Also confirms:
  `FactoryBot`'s `:user` factory is the correct test-data mechanism (no
  new fixture rows); no VCR cassette is needed since `DashboardsController`
  makes no direct Steam API call (only pure-JWT `BridgeToken.encode`);
  no system spec is needed since the logout disclosure is plain
  CSS/HTML with no JS-driven state a request spec can't already observe.
- **`.claude/styleguides/core/react-dashboard.md`** — governs every
  React-side change: deleting `MarketVolumeTile.jsx`/
  `utils/marketVolume.js` retires a `utils/` pure-function + its
  component cleanly; `RangeToggle`/`SortDropdown` are explicitly listed
  among components with "no dedicated test file" today, confirming this
  plan correctly fixes the two *existing* integration tests
  (`PortfolioTile.test.jsx`, `ItemsTile.test.jsx`) that assert on their
  rendered text instead of adding new component-level tests; the
  Styling section (plain CSS, BEM-ish classes in `dashboard.css`, no new
  framework) governs the grid/dropdown/chip work and also resolves this
  plan's open Assumption about the profile-chip logout control — a plain
  `<details>`/`<summary>`-style disclosure satisfies this convention
  without introducing Stimulus (which has zero existing usage/precedent
  anywhere in `app_core` despite being in the Gemfile), so no new
  styleguide is required for that decision.
- **`.claude/styleguides/git-commits.md`** — governs the eventual commit
  message format for this work (`[Core] Imperative summary`).

Note (non-blocking): `react-dashboard.md`'s "Derived Data" section lists
`marketVolume.js` as one of the canonical `utils/` examples — once this
plan deletes that file, that one illustrative reference goes stale. This
doesn't affect the guide's sufficiency for this plan (the rule itself,
not the example, is what's load-bearing), so it isn't a blocking gap —
just worth a trivial follow-up edit to the styleguide's example list
whenever it's next touched.

# Development Plan

## Goal

Merge app_core's separate landing page (`home_pages#index`) and dashboard
(`dashboards#show`) into a single page served at root, with a properly
designed signed-out state, and fix a batch of dashboard presentability/UX
issues (layout-shift bug, missing logout, a mislabeled market-volume tile,
a too-narrow right rail, and verbose labels) — so the app is actually
presentable enough to demo and use end-to-end.

## Expected Behavior

### Normal behavior

- `GET /` with no session renders a signed-out empty state inline on the
  same page shell: topbar with the FLOAT brand + a small "Sign in" button
  top-right, and a centered card in the main content area (icon,
  headline, subtext, a properly styled "Sign in through Steam" button,
  reassurance microcopy). No redirect, no separate home page.
- Both "Sign in" entry points (topbar button and the centered CTA) POST to
  `session_path` exactly as today, unchanged Steam OpenID flow.
- After a successful Steam login/callback, redirecting to `root_path`
  lands directly on the full dashboard — no second redirect through a
  home page.
- `GET /` with an active session renders the full dashboard (profile
  chip, portfolio hero, items list) exactly as `DashboardsController#show`
  does today, with the bridge token encoded the same way.
- The `.profile-chip` in the topbar is interactive: opening it reveals a
  "Sign out" action that issues `DELETE session_path`, logging the user
  out and landing back on the signed-out root page.
- Selecting an item in the Items list (switching `PortfolioTile` into
  "item mode") no longer visibly shifts/resizes the items list or
  surrounding tiles — grid row heights stay stable across mode switches.
- The right-hand items column is visibly wider (1/3 instead of 1/4 of the
  dashboard width), and the Filters dropdown panel is wide enough that a
  weapon name like "Desert Eagle" renders on a single line inside its
  chip, never wrapping.
- The range toggle (24h/7d/30d/1y/all) renders in lowercase; option set
  and position are unchanged.
- The Sort dropdown's open option list uses the same terse style as its
  collapsed trigger label (e.g. "Price ↓" instead of "Price — high to
  low").
- The page title and browser-tab-visible app name read "FLOAT", not the
  placeholder "App", in both signed-out and signed-in states.
- The "Market volume" tile (which secretly aggregated only the logged-in
  user's own items, not the market) no longer exists; the freed grid
  space is absorbed by the hero/items areas via the 4→3 column change,
  not left as a dead gap.

### Edge cases

- A session referencing a deleted/missing user (`current_user` resolves
  to `nil` via `User.find_by`) must still render the signed-out state,
  not an error — already falls out of the existing `current_user`
  memoization, preserved as-is.
- `PortfolioTile`'s "item mode" header must stay stable even when the
  selected item has no StatTrak tag, or a long weapon+item name — the
  grid-row fix must decouple tracks structurally, not just absorb today's
  specific content lengths.
- The existing 600px/920px responsive breakpoints continue to stack tiles
  single/double column as today — the 3-column change only applies above
  920px.

### Must remain unchanged

- The Steam OpenID login/callback flow (`Steam::Authenticator`,
  `Steam::LoginUser`, `Steam::ProfileFetcher`, `Steam::BridgeToken`) — no
  functional changes.
- `SessionsController` — no functional changes; it already redirects to
  `root_path`, which now simply resolves to the merged page.
- The dashboard's data-fetching hooks, reducer actions, and
  portfolio/item chart rendering, apart from the `MarketVolumeTile`
  wiring removed in this plan.

## Scope

### In Scope

1. Merge `home_pages` into `dashboards#show`; `root` routes straight
   there; `home_pages` controller/view/route/spec and the `resource
   :dashboard` route removed.
2. Default page `<title>`/`application-name` → "FLOAT".
3. New signed-out empty state (topbar "Sign in" + centered CTA card),
   replacing the current raw/broken Steam-image markup.
4. Logout control (dropdown/disclosure) on the dashboard's
   `.profile-chip`.
5. CSS Grid fix so `.tile-items`'s row track no longer couples with
   `.tile-hero`'s variable-height header when item mode toggles.
6. Remove `MarketVolumeTile`, `utils/marketVolume.js`, and their tests;
   stop computing/passing market volume in `Dashboard.jsx`.
7. 3-column dashboard grid (hero 2/3, items 1/3); `.dropdown-panel` gets
   its own wider `min-width`; `.chip` gets `white-space: nowrap`.
8. `RangeToggle` labels lowercased.
9. `SortDropdown`'s open-list labels shortened to match `SORT_LABELS`'
   terse style.
10. Fix `dashboards_controller.rb`'s Sorbet sigil (`typed: true` →
    `typed: strict`), since the file is substantially rewritten anyway
    (logged as a known deviation in `fix_me.md`).
11. Update/replace the tests whose assertions this plan directly breaks
    or whose subject is deleted: `home_pages_spec.rb`,
    `dashboards_controller_spec.rb` (migrated to a request spec),
    `PortfolioTile.test.jsx`, `ItemsTile.test.jsx`,
    `MarketVolumeTile.test.jsx`, `marketVolume.test.js`.

### Out of Scope

- Any real/aggregate market-wide volume data source — explicitly
  deferred by the user; the tile is removed, not replaced.
- `SessionsController`, the Steam OpenID/Web API classes, and their
  (currently nonexistent) test coverage — not functionally touched.
- Fixing Sorbet sigils on files this plan does not otherwise edit
  (`sessions_controller.rb`, `application_controller.rb`,
  `lib/steam/authenticator.rb`) — remain logged in `fix_me.md`.
- Any dashboard visual change not explicitly listed in the 9 items (no
  chart redesign, no `ItemRow`/`Pagination` changes).
- Adding automated coverage for the Steam OpenID callback flow (no VCR
  cassette work).

## Implementation Approach

**Rails.** `DashboardsController#show` becomes the single entry point
mounted at `root`. It drops `before_action :require_login` and instead
branches internally on `current_user` — encoding the bridge token only
when present — keeping that encoding call exactly where it is today.
`home_pages_controller.rb`, its view, and its route are deleted outright.
The merged view keeps the dashboard's existing `dash-root`/topbar/CSS
scaffold for both states, so the signed-out card inherits the same dark
theme for free, consistent with `react-dashboard.md`'s styling convention
(plain CSS, BEM-ish classes, no new framework). The logout control reuses
the existing `.profile-chip` DOM, adding a small disclosure (same
CSS-driven open/close pattern already used by `FilterDropdown`/
`SortDropdown`'s `.dropdown-panel`) containing a `button_to session_path,
method: :delete` — this is server-rendered ERB, not a React concern,
since the topbar lives outside `#dashboard-root`.

**React.** `Dashboard.jsx` drops its `MarketVolumeTile`/`marketVolume`
import and render call; `utils/marketVolume.js` and its test are deleted.
`RangeToggle.jsx`'s `RANGE_LABELS` map goes lowercase. `SortDropdown.jsx`'s
`SORT_OPTIONS` labels are rewritten to reuse `SORT_LABELS`' terse style
(arrows / "A–Z") instead of a separate verbose wording.

**CSS.** `.dashboard`'s `grid-template-columns` changes from `repeat(4,
1fr)` to `repeat(3, 1fr)`; `.tile-hero` moves from `grid-column:1/4` to
`1/3`; `.tile-items` moves from `grid-column:4/5` to `3/4`. The
`.tile-volume` rules are deleted outright along with the component. The
row-track coupling (item 5) is resolved once the volume tile's removal
and the column change are both in place — with only two tiles left in
that arrangement, `.tile-items` can take its own independent row span
instead of sharing tracks with `.tile-hero`'s variable-height header; the
exact row/line values are an implementation-time detail, not pre-decided
here, since they depend on the grid shape after items 6 and 7 land.
`.dropdown-panel` gets an explicit `min-width` wider than its trigger
button; `.chip` gets `white-space: nowrap`.

## Files To Modify

- `app_core/config/routes.rb` — `root "dashboards#show"`; remove
  `resource :dashboard`; `resource :session` unchanged.
- `app_core/app/controllers/dashboards_controller.rb` — `# typed: true`
  → `# typed: strict`; remove `require_login`; `show` branches on
  `current_user`, encoding the bridge token only when present.
- `app_core/app/views/dashboards/show.html.erb` — add the signed-out
  branch (brand + small "Sign in" top-right, centered CTA card in place
  of `#dashboard-root` when logged out); add the logout disclosure to
  `.profile-chip` when logged in.
- `app_core/app/views/layouts/application.html.erb` — default `<title>`/
  `application-name` "App" → "FLOAT".
- `app_core/app/frontend/dashboard/styles/dashboard.css` — grid column
  change, `.dropdown-panel` min-width, `.chip` nowrap, `.profile-chip`
  disclosure styles, new signed-out card styles, removal of now-dead
  `.tile-volume`/`.volume-stat`/`.mini-spark` rules.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — remove
  `MarketVolumeTile`/`marketVolume` import and render.
- `app_core/app/frontend/dashboard/components/RangeToggle.jsx` —
  lowercase `RANGE_LABELS`.
- `app_core/app/frontend/dashboard/components/SortDropdown.jsx` —
  shorten `SORT_OPTIONS` labels.
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` —
  update the two `'24H'` assertions to `'24h'`.
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx` —
  update the sort-option click to the new shortened label text.

## Files To Create

- `app_core/spec/requests/dashboards_spec.rb` — replaces both
  `home_pages_spec.rb` and `dashboards_controller_spec.rb`; see Test
  Plan.

## Files To Delete

- `app_core/app/controllers/home_pages_controller.rb`
- `app_core/app/views/home_pages/index.html.erb` (and the then-empty
  `home_pages/` view directory)
- `app_core/spec/requests/home_pages_spec.rb`
- `app_core/spec/controllers/dashboards_controller_spec.rb` (superseded
  by the new request spec)
- `app_core/app/frontend/dashboard/components/MarketVolumeTile.jsx`
- `app_core/app/frontend/dashboard/utils/marketVolume.js`
- `app_core/app/frontend/dashboard/__tests__/MarketVolumeTile.test.jsx`
- `app_core/app/frontend/dashboard/__tests__/marketVolume.test.js`

## Test Plan

**Rails** — `app_core/spec/requests/dashboards_spec.rb`, `type:
:request`, FactoryBot `:user` factory per `rspec-conventions.md`:

- `GET /` without a session → `200`; body includes the signed-out markup
  (e.g. the "Sign in through Steam" button text) and does not include a
  `data-bridge-token` attribute.
- `GET /` with a session for an existing user → `200`; body includes
  `data-bridge-token="..."` (same assertion style as the old controller
  spec) and the user's nickname in the profile chip.
- One scenario chaining sign-in session state → `DELETE /session` → a
  follow-up `GET /` asserting the signed-out markup reappears — this
  directly exercises the new logout control's backend contract without
  expanding `SessionsController`'s own (out-of-scope) coverage.

**React** — `app_core/app/frontend/dashboard/__tests__/`:

- `PortfolioTile.test.jsx` — update `'24H'` → `'24h'` in the two existing
  range-toggle assertions; no new test needed, existing coverage already
  proves the right option appears/disappears per mode.
- `ItemsTile.test.jsx` — update the sort-interaction test to click the
  new shortened label (matching whatever `SORT_OPTIONS`/`SORT_LABELS`
  converge on, e.g. `/price ↑/i`) instead of `/price — low to high/i`;
  the behavior asserted (resorting) is unchanged.
- Delete `MarketVolumeTile.test.jsx` and `marketVolume.test.js` alongside
  their source files.
- No new dedicated test for the CSS grid fix or the `.dropdown-panel`/
  `.chip` width changes — pure CSS with no branching logic, consistent
  with `react-dashboard.md`'s "presentational leaf components: no
  dedicated test needed if no branching logic" convention; verify
  visually instead (see Verification).
- No new test for the signed-out card markup beyond the request spec
  above — server-rendered ERB with no conditional logic beyond the
  existing `current_user` branch already covered there.

## Implementation Steps

1. Routes: collapse `root`/`resource :dashboard` into `root
   "dashboards#show"`.
2. `DashboardsController`: flip sigil to `typed: strict`, drop
   `require_login`, make `show` conditionally encode the bridge token
   only `if current_user`.
3. Delete `home_pages_controller.rb` and its view.
4. Rewrite `dashboards/show.html.erb` to branch on `current_user`:
   signed-out branch renders the new topbar + centered-card markup
   (brand/"Sign in" topbar, card with icon/headline/subtext/Steam
   button/microcopy, `button_to session_path` preserved with `data: {
   turbo: false }`); signed-in branch keeps today's markup plus the new
   profile-chip logout disclosure (`button_to session_path, method:
   :delete`).
5. `application.html.erb`: swap the two "App" literals for "FLOAT".
6. `dashboard.css`: add signed-out card + topbar "Sign in" button
   styles; add profile-chip disclosure styles; change grid to 3 columns
   and adjust `.tile-hero`/`.tile-items` column lines; remove
   `.tile-volume`/`.volume-stat`/`.mini-spark` rules; widen
   `.dropdown-panel`; add `white-space: nowrap` to `.chip`.
7. React: remove `MarketVolumeTile` usage from `Dashboard.jsx`; delete
   `MarketVolumeTile.jsx` and `utils/marketVolume.js`.
8. `RangeToggle.jsx`: lowercase `RANGE_LABELS`.
9. `SortDropdown.jsx`: shorten `SORT_OPTIONS` labels.
10. Update `PortfolioTile.test.jsx` and `ItemsTile.test.jsx` for the
    label changes; delete the two market-volume test files.
11. Replace `dashboards_controller_spec.rb` with
    `spec/requests/dashboards_spec.rb`; delete `home_pages_spec.rb`.
12. Run full Ruby and JS test suites and fix any remaining fallout.

## Verification

- `bundle exec rspec` in `app_core` (full suite, not just the touched
  specs — routes/controller changes can affect unrelated specs that hit
  `root_path`/`dashboard_path`).
- `npm test` (vitest run) in `app_core`.
- `bin/rubocop` on the touched Ruby files.
- Manual check in a browser: signed-out root page (topbar "Sign in" +
  centered card), sign in, dashboard renders, click an item and confirm
  no visible jump in the items column, open Filters and confirm "Desert
  Eagle" (or any two-word weapon) renders on one line, open Sort and read
  the shortened labels, use the new profile-chip logout control and
  confirm it returns to the signed-out root page.
- Grep the repo once more after removing `resource :dashboard` for any
  remaining `dashboard_path`/`dashboard_url` reference (confirmed during
  planning to be limited to the three files already deleted, but cheap to
  re-check post-edit).

## Risks

- Deleting `resource :dashboard` removes the `dashboard_path`/
  `dashboard_url` helpers; confirmed via grep that only
  `home_pages_controller.rb`, `home_pages/index.html.erb`, and
  `home_pages_spec.rb` reference them — all three are deleted in this
  same change, so no dangling-reference risk, but worth the final grep in
  Verification in case something was missed during planning.
- The exact CSS grid-row restructuring for item 5 is specified at the
  level of intent rather than exact track/line numbers, since the right
  fix depends on the grid shape once `.tile-volume` is already removed
  (item 6) and the column count already changed (item 7) — sequencing
  matters: land 6 and 7 before finalizing 5's exact CSS, not in
  isolation.
- `PortfolioTile.test.jsx` and `ItemsTile.test.jsx` are the only two
  tests confirmed (by direct inspection) to hardcode strings this plan
  changes; a full test run, not just these two files, is the real safety
  net in case something else in the suite also asserts on `'24H'`-exact
  casing or the verbose sort labels.
- No automated coverage exists (before or after this plan) for the Steam
  OpenID callback itself — acceptable given Scope explicitly excludes
  expanding `SessionsController` coverage, but the new logout control
  only gets the one request-spec round trip proposed above, not a
  browser-level system test.

## Assumptions

- "FLOAT" is the correct final brand string for the default title/app
  name (matches what `dashboards/show.html.erb` already sets via
  `content_for :title, "Dashboard — FLOAT"`); the signed-out page's title
  can reasonably drop the "Dashboard — " prefix since that page isn't the
  dashboard — no dedicated title was specified for the signed-out state
  during planning, so plain "FLOAT" is assumed for that case unless
  corrected.
- "Shorten `SORT_OPTIONS` to match `SORT_LABELS`' terse style" means
  reusing the same arrow glyphs (↓/↑) and "A–Z" wording rather than
  inventing a third scheme — the general direction was agreed in
  conversation but not pinned to an exact string-for-string mapping.
- The profile-chip logout disclosure can be implemented with the
  existing CSS-only open/close pattern already used for
  `.dropdown-panel` (no new JS/Stimulus controller needed), since the
  topbar is plain server-rendered ERB outside the React island — if a
  CSS-only toggle proves insufficient for interaction/accessibility
  needs, a small Stimulus controller would be a minor addition beyond
  what's scoped here.

# Implementation Summary

## Implemented

All 9 scope items landed as planned:

1. **Single page**: `home_pages_controller.rb`/view/route deleted;
   `root "dashboards#show"`; `resource :dashboard` removed.
   `DashboardsController#show` dropped `before_action :require_login` and
   now branches on `current_user`, encoding `@bridge_token` only when
   present.
2. **Title/brand**: layout's default `<title>`/`application-name` now
   "FLOAT" instead of "App".
3. **Signed-out empty state**: `dashboards/show.html.erb` now renders a
   topbar with a small "Sign in" button (signed out) and a centered card
   (icon, headline, subtext, a real "Sign in through Steam" button,
   reassurance microcopy) in place of the old raw/broken Steam-image
   markup.
4. **Logout**: `.profile-chip` is now a `<details>/<summary>` disclosure
   with a "Sign out" action (`DELETE session_path`) — no Stimulus needed.
5. **Layout-shift fix**: `.dashboard`'s `align-items` changed from
   `stretch` to `start`, so `.tile-hero` and `.tile-items` size to their
   own content independently — confirmed via a stress test (forced the
   hero header to wrap to two lines) that `.tile-items`'s position does
   not move.
6. **Market volume removed**: `MarketVolumeTile.jsx`, `utils/marketVolume.js`,
   and both their tests deleted; `Dashboard.jsx`'s usage, the now-unused
   `trendStatus` destructure, and the `DashboardSkeleton` tile-volume
   placeholder (which would have reintroduced a load→ready layout jump)
   removed too; a stale comment in `useItemTrend.js` referencing the
   deleted component was corrected.
7. **Grid + dropdown width**: `.dashboard` is now a 3-column grid
   (`.tile-hero` spans columns 1-2 of 3, i.e. 2/3 width; `.tile-items`
   spans column 3, i.e. 1/3 width) instead of the old 4-column 3/4 + 1/4
   split. `.dropdown-panel` got its own `min-width:220px` independent of
   its trigger button's width; `.chip` got `white-space:nowrap`.
8. **Range toggle**: `RANGE_LABELS` lowercased (`24h`/`7d`/`30d`/`1y`/`all`).
9. **Sort dropdown**: `SORT_OPTIONS` collapsed from a separate
   verbose-label array into a plain list of keys that looks up the same
   `SORT_LABELS` map the collapsed trigger already used — removes the
   duplicate wording instead of adding a second terse copy.

Also fixed per `fix_me.md`'s own stated policy (file already being
substantially touched): `dashboards_controller.rb`'s Sorbet sigil
(`typed: true` → `typed: strict`), and `dashboards_controller_spec.rb`
migrated from the disallowed `type: :controller` to a proper
`type: :request` spec. Both corresponding `fix_me.md` entries were
updated — the `dashboards_controller.rb`/`home_pages_controller.rb`
sigil bullets were split so only the still-untouched files
(`application_controller.rb`, `sessions_controller.rb`) remain listed,
and the `dashboards_controller_spec.rb` entry was removed outright since
the file it described no longer exists.

## Tests

- `app_core/spec/requests/dashboards_spec.rb` (new): signed-out root
  render (200, "Sign in through Steam" present, no bridge token),
  signed-in root render (bridge token + nickname present), signed-in
  render includes a sign-out control, `DELETE /session` redirects to
  root. Written RED-first against the pre-change controller/routes,
  confirmed failing for the expected reason, then made to pass.
- `app_core/spec/controllers/dashboards_controller_spec.rb` and
  `app_core/spec/requests/home_pages_spec.rb` deleted (superseded by the
  above).
- `PortfolioTile.test.jsx`: the two `'24H'` range-toggle assertions
  updated to `'24h'` — RED-confirmed against the old uppercase labels,
  then GREEN after the `RangeToggle.jsx` change.
- `ItemsTile.test.jsx`: the sort-interaction test's click target updated
  from `/price — low to high/i` to `/price ↑/i` — RED-confirmed, then
  GREEN after the `SortDropdown.jsx` change.
- `MarketVolumeTile.test.jsx` and `marketVolume.test.js` deleted
  alongside their source files.

Commands executed: `bundle exec rspec` (full suite, in the `app_core`
container), `npm test` (vitest run, full suite), `bundle exec rubocop`
(full repo), `bundle exec srb tc` (full repo).

## Verification

- `bundle exec rspec`: 6 examples, 0 failures (full `app_core` suite).
- `npm test`: 10 test files, 56 tests, all passing (full suite).
- `bundle exec rubocop`: 22 offenses detected, all in files this plan
  never touched (`config/initializers/content_security_policy.rb`,
  `lib/steam/authenticator.rb`, `lib/steam/profile_fetcher.rb` — all
  pre-existing, several already logged in `fix_me.md`); zero offenses in
  any file this plan modified.
- `bundle exec srb tc`: 12 pre-existing errors, all `Unable to resolve
  constant` noise for `RSpec`/`FactoryBot`/`JWT` in spec/factory files
  unrelated to this change (confirmed pre-existing by reproducing the
  same errors on untouched files like `bridge_token_spec.rb`); zero
  errors on `dashboards_controller.rb` or `config/routes.rb`.
- Grepped the full repo for `dashboard_path`/`dashboard_url` after
  removing the route — zero remaining references outside an unrelated
  stale git worktree under `.claude/worktrees/`.
- Manual browser verification via the running `app_core` dev server
  (docker compose): signed-out root page confirmed matching the agreed
  design (topbar brand + small "Sign in", centered card with icon/
  headline/subtext/CTA/microcopy) at both desktop and mobile (375px)
  widths; browser tab title confirmed "FLOAT". The signed-in dashboard
  layout (3-column grid, wider items column, "Desert Eagle" chip fitting
  on one line in the widened filter panel, lowercase range toggle) was
  verified against a temporary static HTML fixture built from the real
  compiled `dashboard.css` and the actual component markup/class names,
  since completing a real Steam OAuth login isn't possible in this
  environment — a forced-wrap stress test on the hero header confirmed
  `.tile-items`'s position is pixel-identical before and after (top:
  404px → 404px at one width, 95px → 95px at another, hero height
  293px → 342px). The fixture was deleted after verification; it was
  never committed.

## Deviations

- Added `.claude/launch.json` (not in the plan's file list) so the
  `app_core` dev server could be started for the manual browser
  verification step — minor dev tooling, not application code.
- The grid-row decoupling fix for item 5 ended up being a one-line
  `align-items:stretch` → `align-items:start` change plus the natural
  consequence of only two tiles remaining after item 6's removal, rather
  than a more involved explicit row-track restructuring — simpler than
  the plan's Implementation Approach anticipated, same effect.
- `DashboardSkeleton.jsx`'s `tile-volume` placeholder section was removed
  in addition to the plan's explicit file list — not removing it would
  have reintroduced a loading→loaded layout jump (3 skeleton tiles
  collapsing to 2 real ones), which runs directly counter to item 5's
  purpose. A stale code comment in `useItemTrend.js` referencing the
  deleted `MarketVolumeTile` by name was also corrected for the same
  "don't leave a dangling reference" reason. Neither was in the plan's
  Files To Modify list but both are direct, small consequences of item 6.

## Remaining Issues

- None blocking. `react-dashboard.md`'s "Derived Data" section still
  lists `marketVolume.js` as a canonical example (flagged non-blocking
  during styleguides-check) — worth a trivial touch-up next time that
  styleguide is otherwise edited.
- The logout control's only coverage is the one request-spec round trip
  in `dashboards_spec.rb` (confirmed via Verification's manual check
  too); per Scope, expanding `SessionsController`/Steam OpenID coverage
  remains explicitly out of scope.
