---
status: implemented
app: core
goal: Recolor the dashboard's sign-out icon as a danger action and gate it behind a zero-JS confirm overlay instead of signing out on first click
created: 2026-10-04
---

## Applicable Styleguides

- **`.claude/styleguides/core/erb-interaction-patterns.md`** (new, created
  to unblock this plan) — governs the entire confirm-overlay mechanism:
  the trigger must be a plain `<a href="#signout-confirm">` (never a
  direct-submit form), the overlay shape (backdrop-as-anchor, Cancel
  link, both dismissing via `href="#"`), and confirms Stimulus is
  explicitly not warranted here per its "When to Use" section (no need
  to sync state outside CSS selectors, no Escape-key/focus-trap
  requirement was asked for).
- **`.claude/adr/core/erb-overlays-over-stimulus.md`** (new, companion to
  the above) — the "why": zero-JS CSS is the default for ERB-view
  interactivity in `app_core` until a need genuinely can't be expressed
  that way; documents the accepted trade-offs (no Escape/focus-trap,
  URL-fragment history entry) this plan's Risks section already named.
- **`.claude/styleguides/core/react-dashboard.md`** — its "Styling"
  section (plain CSS, BEM-ish naming, reuse semantic color tokens)
  governs the `.profile-signout` recolor to `--down`/`--down-soft` and
  the new overlay/card CSS — same extension to this ERB-side stylesheet
  already established in prior plans this session.
- **`.claude/styleguides/rspec-conventions.md`** — governs the new
  request-spec assertion (plain regex/substring check on rendered HTML,
  no new spec level or stubbing needed).
- **`.claude/styleguides/git-commits.md`** — commit format for the
  eventual change (`[Core] ...`), and confirms the new styleguide/ADR
  commit together with this implementation under one `[Core]` commit
  per the "Task-Scoped Styleguides, ADRs, and Plans" section, not a
  separate `AI WorkFlow` commit.

# Development Plan

## Goal

Make the topbar's sign-out icon visually read as a destructive action
(light red, using the codebase's existing `--down` tokens), and require
an explicit confirm step before the actual sign-out fires, so a stray
click doesn't immediately end the session.

## Expected Behavior

### Normal behavior

- `.profile-signout` is red at rest (not just on hover) — `color:
  var(--down)`, hover background `var(--down-soft)`.
- Clicking the icon opens a small centered confirm overlay ("Sign out of
  FLOAT?" + Cancel / Sign out), not an immediate `DELETE /session`.
- Clicking "Cancel", or clicking anywhere on the dimmed backdrop outside
  the confirm card, closes the overlay with no session change.
- Clicking the confirm card's "Sign out" button performs the real
  `DELETE /session` exactly as today (same controller action, same
  redirect to the signed-out root).

### Edge cases

- Works with JavaScript fully disabled — the whole mechanism is a CSS
  `:target` selector keyed off a URL fragment, not a script.
- Browser back button after opening the overlay closes it (the fragment
  navigation is a real history entry) — acceptable, not a bug, but
  worth knowing: this is unlike a JS modal that wouldn't touch history.

### Must remain unchanged

- `SessionsController#destroy` — zero changes; the confirm card's
  button still submits the exact same `button_to session_path, method:
  :delete, data: { turbo: false }`.
- No Stimulus/JS is introduced anywhere in `app_core` — this stays
  consistent with the ERB topbar's zero-JS approach so far.

## Scope

### In Scope

1. `.profile-signout` color change to `--down`/`--down-soft`.
2. A `:target`-based confirm overlay: the icon becomes `<a
   href="#signout-confirm">`; a new `#signout-confirm` block holds a
   full-bleed backdrop link (`href="#"`, dismiss-by-click-outside), a
   confirm card with a "Cancel" link (`href="#"`) and the real
   `button_to ..., method: :delete` button.
3. One new request-spec assertion confirming the icon is a plain anchor
   (`href="#signout-confirm"`), not something that directly wraps/
   triggers the delete form.

### Out of Scope

- Any Stimulus controller, `<dialog>` element, or other JS-driven modal
  — a zero-JS CSS overlay fully satisfies "requires a confirm step
  before signing out," and introducing JS/Stimulus for this would be
  this codebase's first use of it for something a known CSS technique
  already solves.
- Escape-key dismissal and focus-trapping — real, known limitations of
  the zero-JS approach (see Risks), not implemented here since they'd
  require JS; not requested by the user beyond "guard against stray
  clicks," which click-outside + explicit Cancel already satisfies.
- Any change to `SessionsController`, routes, or the underlying sign-out
  mechanism itself.

## Implementation Approach

In `dashboards/show.html.erb`, replace the current `button_to`-wrapped
icon with `<a href="#signout-confirm" class="profile-signout"
aria-label="Sign out">` holding the same SVG. Immediately after
`.profile-group` (still inside the `current_user` branch, as a sibling —
not nested inside `.topbar`'s flex row, so it doesn't disturb the
existing two-child `justify-content: space-between` layout fixed in the
earlier Filters-badge work), add:

```erb
<div id="signout-confirm" class="confirm-overlay">
  <a href="#" class="confirm-overlay-backdrop" aria-hidden="true"></a>
  <div class="confirm-card">
    <p class="confirm-card-text">Sign out of FLOAT?</p>
    <div class="confirm-card-actions">
      <a href="#" class="confirm-cancel">Cancel</a>
      <%= button_to session_path, method: :delete, data: { turbo: false }, class: "confirm-signout" do %>
        Sign out
      <% end %>
    </div>
  </div>
</div>
```

CSS: `#signout-confirm{ display:none; }` by default;
`#signout-confirm:target{ display:flex; position:fixed; inset:0; ... }`
shows it as a full-viewport flex container centering `.confirm-card`
over the dimmed backdrop. The backdrop anchor and Cancel anchor both use
`href="#"` — navigating to an empty fragment un-matches `:target`,
hiding the overlay again, with no JS.

`.profile-signout` keeps its existing size/position/hover transition
rules, just changes `color`/hover `background` to the `--down` tokens.

## Files To Modify

- `app_core/app/views/dashboards/show.html.erb` — icon becomes an
  anchor; add the `#signout-confirm` overlay markup.
- `app_core/app/frontend/dashboard/styles/dashboard.css` — recolor
  `.profile-signout`; add `.confirm-overlay`, `.confirm-overlay-backdrop`,
  `.confirm-card`, `.confirm-card-text`, `.confirm-card-actions`,
  `.confirm-cancel`, `.confirm-signout`.
- `app_core/spec/requests/dashboards_spec.rb` — add the new anchor-not-
  direct-trigger assertion.

## Files To Create

None.

## Test Plan

In `dashboards_spec.rb`'s existing `"when signed in"` block:

- New example: response body matches `/<a[^>]+href="#signout-confirm"/`
  — confirms the icon is a plain anchor into the confirm overlay, not a
  direct-submit control.
- No change needed to the existing `"includes a sign-out control"`
  example — confirmed during research that the real `button_to` form
  (with its `"Sign out"` text and `_method=delete` hidden field) still
  always renders in the page markup, just inside the now-CSS-hidden-
  until-`:target` overlay, so both of its existing assertions keep
  passing against the same rendered HTML as before.

## Implementation Steps

1. Write the new anchor-assertion test in `dashboards_spec.rb` (RED — it
   fails against the current icon, which is a `button_to` form, not an
   anchor).
2. `dashboards/show.html.erb`: change the icon to `<a
   href="#signout-confirm">`; add the `#signout-confirm` overlay block.
3. `dashboard.css`: recolor `.profile-signout`; add the overlay/card
   styles.
4. Run the full spec suite — confirm the new example passes (GREEN) and
   the existing sign-out-control example still passes unmodified.
5. Manual verification (see Verification) — click-to-open, backdrop-
   click-to-close, Cancel-to-close, confirm-to-actually-sign-out.

## Verification

- `bundle exec rspec` (full `app_core` suite).
- `bundle exec rubocop` (no Ruby files touched this time, but run for
  completeness).
- Manual check in a browser: since no real Steam login is available in
  this environment, use the same temporary-static-fixture technique as
  prior plans (built from the real compiled `dashboard.css`) to click
  through: icon → overlay opens; click backdrop → closes; click Cancel →
  closes; (not actually submitting the real delete, to avoid needing a
  live session — confirm its markup/attributes are correct instead).

## Risks

- No Escape-key dismissal and no focus trap — genuine limitations of a
  `:target`-only overlay with no JS. Acceptable here since nothing in
  this codebase has ever had either (this is the first overlay of any
  kind in `app_core`'s ERB views), and the user's actual ask (don't
  sign out on a stray click) is fully satisfied by click-outside +
  explicit Cancel.
- Opening the overlay adds a `#signout-confirm` history entry; pressing
  the browser back button closes it instead of navigating away from the
  dashboard. This is a real, slightly unusual interaction but not a
  functional bug — flagging it so it isn't mistaken for one during
  review.
- The confirm overlay is the first interactive component in this ERB
  topbar beyond the (now-removed) `<details>` disclosure — no existing
  styleguide governs overlay markup conventions, confirmed during
  research; styleguides-check should explicitly decide whether this
  warrants a new minimal styleguide or is still small enough to stand on
  established CSS/Rails precedent alone.

## Assumptions

None — every fact needed was confirmed by reading the actual code
during research.

# Implementation Summary

## Implemented

- `dashboards/show.html.erb`: the sign-out icon is now `<a
  href="#signout-confirm" class="profile-signout" aria-label="Sign
  out">` instead of a `button_to`. Added the `#signout-confirm` overlay
  (backdrop `<a href="#">`, confirm card with a `Cancel` link and the
  real `button_to session_path, method: :delete` button) immediately
  after `.profile-group`, following `erb-interaction-patterns.md`'s
  canonical shape exactly.
- `dashboard.css`: `.profile-signout` recolored to `var(--down)` at
  rest, `var(--down-soft)` on hover (was `--text-faint`/`--surface`).
  Added `.confirm-overlay` (`display:none` by default,
  `:target{ display:flex; position:fixed; inset:0; }`),
  `.confirm-overlay-backdrop`, `.confirm-card`, `.confirm-card-text`,
  `.confirm-card-actions`, `.confirm-cancel`, `.confirm-signout`.

## Tests

- `dashboards_spec.rb`: new example asserting the icon renders as
  `<a href="#signout-confirm" ... aria-label="Sign out">` rather than a
  direct-submit form. Written RED-first (confirmed failing against the
  pre-change `button_to`-wrapped icon), then GREEN after the view change.
- Existing `"includes a sign-out control"` example verified to still
  pass unmodified — the real `button_to` (with its `"Sign out"` text and
  `_method=delete` hidden field) still always renders in the page body,
  now inside the confirm card.

Commands executed: `bundle exec rspec spec/requests/dashboards_spec.rb`
(RED, then GREEN), `bundle exec rspec` (full suite), `bundle exec
rubocop` (full repo).

## Verification

- `bundle exec rspec`: 9 examples, 0 failures (full `app_core` suite;
  was 8 before this plan's 1 new example).
- `bundle exec rubocop`: same 22 pre-existing offenses as before, none
  in files this plan touched (CSS/ERB aren't linted by rubocop anyway).
- Manual check via the running `app_core` dev server using a temporary
  static fixture (no real Steam login available in this environment):
  confirmed the icon renders light red at rest; clicking it opens the
  confirm overlay via real `:target` CSS (not simulated — an actual
  click navigated the URL fragment and the browser's own `:target`
  match showed the overlay); clicking "Cancel" closed it
  (`location.hash` empty afterward); clicking the backdrop also closed
  it (same hash-clearing behavior) — both confirmed via real clicks
  through the preview browser, not just visual inspection. Did not
  click the actual "Sign out" button in the fixture (no live session to
  safely sign out of in this environment) — its markup/attributes were
  verified via the request spec instead. Fixture deleted after
  verification, never committed.

## Deviations

None — implementation matched the plan and `erb-interaction-patterns.md`
exactly.

## Remaining Issues

None blocking. Per the ADR's own Implementation Constraints: the first
genuine need for Escape-key dismissal, a focus trap, or state synced
with something outside CSS selectors is the trigger to introduce
`app_core`'s first Stimulus controller — not something to retrofit onto
this pattern speculatively now.
