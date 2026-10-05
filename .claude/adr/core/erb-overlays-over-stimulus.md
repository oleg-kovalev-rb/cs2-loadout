# Zero-JS CSS Overlays for ERB-View Interactions, Not Stimulus

## Status

Accepted

## Context

`app_core`'s dashboard page is mostly the React island
(`app/frontend/dashboard/`), but its surrounding chrome — the topbar,
sign-in/sign-out — is plain server-rendered ERB
(`app/views/dashboards/show.html.erb`), outside the island entirely.
That chrome has needed small interactive moments more than once now: a
profile menu that briefly used a `<details>/<summary>` disclosure, and
now a sign-out action that needs a confirm-before-destructive-action
step (don't sign out on the first stray click).

`stimulus-rails` and `turbo-rails` are both in the Gemfile — standard
`rails new` defaults — but neither has ever actually been used anywhere
in `app_core`: there is no `app/javascript/controllers` directory, no
`data-controller` attribute, nothing. Every time this topbar has needed
interactivity so far, the question "do we finally reach for Stimulus, or
is there a simpler way" has had to be re-answered from scratch, with no
written precedent to point to.

## Decision

Default to zero-JS CSS techniques for interactivity in `app_core`'s
plain ERB views (outside the React island): `<details>/<summary>` for
simple disclosures, and anchor-link-driven `:target` overlays for
confirm/dismiss patterns where a destructive action needs an
intermediate step. Reach for a Stimulus controller only when a zero-JS
technique genuinely cannot express the needed behavior — e.g. syncing
visual state with something that isn't expressible as a CSS selector
(a timer, a network response, state shared across more than one
disconnected DOM subtree), or requiring keyboard handling beyond what
native focusable elements give for free.

Concretely, for a confirm-before-destructive-action pattern: the
triggering element is `<a href="#overlay-id">`, not a button that fires
the action directly. The overlay is `<div id="overlay-id">`, hidden by
default and shown via `#overlay-id:target`, containing a backdrop that
is itself a full-size `<a href="#">` (click-outside dismisses by
navigating the fragment away) and a card with a `Cancel` link
(`href="#"`, same dismissal) plus the real action's `button_to`.

## Alternatives Considered

### Alternative: A Stimulus controller for the confirm overlay

Write a small `signout_confirmation_controller.js`, toggle a class on
click, listen for outside-click and Escape to close it.

Rejected because:

- It would be the first Stimulus controller ever written in `app_core`,
  for a need a long-standing, zero-dependency CSS technique already
  solves completely. Introducing a new JS layer's worth of plumbing
  (controller registration, the `app/javascript/controllers` directory,
  deciding import-map vs. bundled setup) is a much bigger footprint than
  the actual problem — don't sign out on a stray click — requires.
- Every other interactive moment this topbar has needed so far has been
  solved with zero JS; there was no forcing requirement here that
  Stimulus uniquely satisfies.

### Alternative: Keep `<details>/<summary>` for this too

Reuse the exact disclosure pattern the profile menu briefly used,
instead of introducing a second zero-JS technique (`:target`).

Rejected because:

- A disclosure is the wrong interaction shape for "confirm before a
  destructive action." The user explicitly did not want a reveal-then-
  click flow for sign-out (that's what the profile menu was, and it was
  removed) — they want the icon directly clickable, gated by a
  confirmation step, not a menu to open first. `:target` naturally
  expresses "clicking this opens an overlay somewhere else in the page,"
  which is a better match for a modal-style confirm than `<details>`'s
  "expand in place" model.

## Consequences

### Positive

- No new JS dependency, no new build-pipeline surface, no Stimulus
  controller registration to maintain, for interactivity this small.
- Two deliberate, named zero-JS techniques now exist
  (`<details>/<summary>`, `:target` overlay) instead of each new need
  re-deriving an approach from nothing.

### Negative

- A `:target` overlay has no Escape-key dismissal and no focus trap —
  real, accepted limitations, not oversights. Opening it also adds a
  URL-fragment history entry, so the browser back button closes the
  overlay rather than navigating away from the dashboard.
- Two different zero-JS techniques (`<details>`, `:target`) exist
  side-by-side for different interaction shapes — a contributor has to
  know which one fits a new need rather than reaching for one universal
  tool.

### Risks

- If a future need genuinely requires Escape-key handling, a focus trap,
  or state synced with something outside pure CSS selectors, forcing it
  into a `:target` overlay anyway (instead of finally introducing
  Stimulus for that specific case) would produce an inaccessible,
  over-stretched hack. This ADR's Decision explicitly carves out that
  case as the trigger to introduce Stimulus for the first time, not a
  reason to avoid it forever.

## Implementation Constraints

- A new simple disclosure in an ERB view (outside the React island)
  uses `<details>/<summary>`.
- A new confirm-before-destructive-action or modal-style overlay in an
  ERB view uses the `:target` pattern described in Decision — trigger
  anchor, hidden-by-default overlay `div`, backdrop-as-anchor, Cancel
  link, same dismissal mechanism (`href="#"`) for both.
- The first genuine need for Escape-key dismissal, a focus trap, or
  state synced with something outside CSS selectors is the trigger to
  introduce `app_core`'s first Stimulus controller — not a reason to
  keep stretching the zero-JS pattern past where it fits.

## Related

- `.claude/styleguides/core/erb-interaction-patterns.md`
- `app_core/app/views/dashboards/show.html.erb` — confirm-overlay
  canonical implementation
- `.claude/plans/dashboard-signout-confirm-overlay.md` — the plan this
  ADR unblocks
