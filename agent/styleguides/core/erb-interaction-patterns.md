---
description: Patterns for app_core's plain ERB views (outside the React island) — zero-JS disclosures and confirm overlays, plus the Stimulus-backed flash toast and when to reach for Stimulus at all.
---

# ERB Interaction Patterns (`app_core`)

## Purpose

`app_core`'s dashboard page is mostly the React island
(`app/frontend/dashboard/`, see `react-dashboard.md`), but its
surrounding chrome — topbar, sign-in/sign-out — is plain server-rendered
ERB outside that island. This file covers how that chrome gets
interactivity and transient state (a disclosure, a confirm-before-
destructive-action overlay, a flash message) without introducing a new
JS layer for something CSS already solves. See `agent/adr/core/erb-overlays-over-stimulus.md` for why
zero-JS is the default here instead of Stimulus.

Stimulus is introduced only for the one behavior CSS cannot express
cleanly: the flash toast's auto-dismiss timer. That controller lives
under `app/frontend/controllers/` and is registered by the single global
entrypoint described below. The zero-JS patterns remain the default for
everything else.

## When to Use

Applies to interactivity or transient server-rendered state needed in
`app_core`'s plain ERB views (the dashboard's topbar and anything else
outside `#dashboard-root`). Does not apply to the React island itself —
see `react-dashboard.md` for that.

Three zero-JS patterns below cover the interactions CSS expresses
completely: disclosures, confirm overlays, and rendering the flash toast
markup. The flash toast's auto-dismiss is the one case where a timer is
needed, so it is implemented with a Stimulus controller instead.

Reach for a Stimulus controller only when a zero-JS technique genuinely
cannot express the behavior — concretely: the behavior needs to sync
with something that isn't expressible as a CSS selector (a timer, a
network response, state shared across more than one disconnected part of
the page), or needs keyboard handling beyond what native focusable
anchors/elements give for free (Escape-key dismissal, a real focus trap).
Introducing Stimulus for that first genuine case is expected and correct
— these patterns aren't meant to be stretched past where they fit.

## Structure

### Simple disclosure — `<details>/<summary>`

For "click to reveal more content in place" with no confirm/cancel
semantics. `<summary>` is the trigger (style it directly, suppress the
default marker via `summary{ list-style:none; }` and
`summary::-webkit-details-marker{ display:none; }`), the rest of
`<details>`'s children are the revealed content.

### Confirm overlay — anchor-link `:target`

For "clicking this needs a confirm step before the real action fires,"
e.g. a destructive action like sign-out. Shape:

```erb
<a href="#<overlay-id>" class="...">...trigger content...</a>

<div id="<overlay-id>" class="confirm-overlay">
  <a href="#" class="confirm-overlay-backdrop" aria-hidden="true"></a>
  <div class="confirm-card">
    <p class="confirm-card-text">...confirmation copy...</p>
    <div class="confirm-card-actions">
      <a href="#" class="confirm-cancel">Cancel</a>
      <%= button_to real_path, method: :delete, data: { turbo: false }, class: "confirm-signout" do %>
        ...confirm label...
      <% end %>
    </div>
  </div>
</div>
```

```css
#<overlay-id>{ display:none; }
#<overlay-id>:target{ display:flex; position:fixed; inset:0; /* center .confirm-card */ }
```

The trigger is a plain anchor, never a `button_to`/form directly — the
only form in the whole pattern is the one real action inside the
confirmed card. The backdrop and Cancel link both dismiss via
`href="#"` (navigating to an empty fragment un-matches `:target`); no
JS is involved anywhere in this pattern.

### Flash messages — server-rendered toast

For messages that accompany a redirect (`notice:`/`alert:` on
`redirect_to`, most commonly after login/logout). Render them once,
from the application layout, through a shared partial:

```erb
<%# app/views/shared/_flash.html.erb, rendered from application.html.erb %>
<% messages = flash.to_h.select { |_, message| message.present? } %>
<% if messages.any? %>
  <div class="flash-stack">
    <% messages.each do |type, message| %>
      <% kind = type.to_s == "alert" ? "alert" : "notice" %>
      <div class="flash flash-<%= kind %>"
           role="<%= kind == "alert" ? "alert" : "status" %>"
           data-controller="flash"
           data-flash-delay-value="5000">
        <%= message %>
      </div>
    <% end %>
  </div>
<% end %>
```

```css
.flash-stack {
  position: fixed;
  top: 84px;
  right: 24px;
  z-index: 60;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.flash-stack:empty {
  display: none;
}
.flash-notice {
  --flash-accent: var(--up, #3fb878);
}
.flash-alert {
  --flash-accent: var(--down, #f0546b);
}
```

The wrapper disappears entirely when there is no flash; several
messages stack vertically. The card itself is styled in
`application.css`, since it sits outside every React island and must
work on any page using the layout.

### Flash auto-dismiss — the one Stimulus timer

A toast that stays forever covers page content and is no longer a toast.
Each `.flash` card gets `data-controller="flash"` and a
`data-flash-delay-value` (currently 5000 ms). The controller fades the
card out, then removes it from the DOM; `.flash-stack:empty` collapses
the now-empty wrapper:

```js
// app/frontend/controllers/flash_controller.js
import { Controller } from '@hotwired/stimulus'

const DEFAULT_DELAY_MS = 5000
const EXIT_DURATION_MS = 180

export class FlashController extends Controller {
  static values = { delay: Number }

  connect() {
    this.scheduleDismissal()
  }

  disconnect() {
    this.clearTimers()
  }

  scheduleDismissal() {
    this.clearTimers()
    this.dismissTimeout = window.setTimeout(
      () => this.dismiss(),
      this.delayValue || DEFAULT_DELAY_MS,
    )
  }

  dismiss() {
    this.clearTimers()
    this.element.classList.add('is-leaving')
    this.removeTimeout = window.setTimeout(() => this.element.remove(), EXIT_DURATION_MS)
  }

  clearTimers() {
    window.clearTimeout(this.dismissTimeout)
    window.clearTimeout(this.removeTimeout)
  }
}
```

Stimulus is started once by a global chrome entrypoint, not by any React
island and not per page:

```js
// app/frontend/entrypoints/flash.js
import { Application } from '@hotwired/stimulus'
import { FlashController } from '../controllers/flash_controller'

const application = Application.start()
application.register('flash', FlashController)
```

The layout loads it once, next to the existing Vite tags:

```erb
<%= vite_javascript_tag "flash" %>
```

`application.css` supplies the exit state; the existing
`prefers-reduced-motion` block must disable this transition as well as
the entrance animation:

```css
.flash {
  transition: opacity 180ms ease, transform 180ms ease;
}
.flash.is-leaving {
  opacity: 0;
  transform: translateY(-6px);
}
```

The timer is a progressive enhancement: if JavaScript does not load, the
server-rendered message remains visible exactly as before.

## Rules

### MUST

- Use `<details>/<summary>` for a simple reveal-in-place disclosure with
  no confirm/cancel step.
- Use the anchor-link `:target` shape above for any confirm-before-
  destructive-action overlay — trigger is an `<a href="#id">`, never a
  direct-submit `button_to`/form.
- Keep the real action (`button_to`) as the only form in the pattern,
  placed inside the confirmed card — never duplicate it outside the
  overlay for convenience.
- Render flash exactly once, from `application.html.erb` via
  `shared/_flash.html.erb` — never add it per view.
- Map `alert` to `.flash-alert` with `role="alert"`, and every other key
  (currently `notice`) to `.flash-notice` with `role="status"`. Never
  interpolate an arbitrary flash key into a CSS class or ARIA attribute.
- Skip blank messages, and render no wrapper at all when there is no
  flash.
- Auto-dismiss every flash toast through the shared `flash` Stimulus
  controller, with the delay carried in `data-flash-delay-value` (5000 ms
  unless there is a reason to change it). Never leave a toast permanently
  on screen.
- Keep the dismissal timer and DOM removal in
  `app/frontend/controllers/flash_controller.js`; register it from the
  single global `app/frontend/entrypoints/flash.js` loaded by the layout,
  and clear both timers in `disconnect`.
- Keep auto-dismiss a progressive enhancement: the server-rendered
  message must still be readable if JavaScript never runs.

### SHOULD

- Reuse the existing color tokens (`--down`/`--down-soft` for
  destructive/danger, `--up`/`--up-soft` for positive/notice,
  `--accent`/`--accent-soft` for primary) rather than introducing new
  color literals for a new interactive element.
- Render flash as a fixed-position toast so showing a message doesn't
  shift the topbar or page content; keep it inside the viewport on
  narrow screens and honor `prefers-reduced-motion`.
- Remove the card from the DOM after its fade-out (rather than leaving an
  `opacity: 0` element behind) and collapse the emptied wrapper with
  `.flash-stack:empty { display: none; }`.
- Use flash only for messages that survive a redirect. Render errors for
  a same-request form re-render inline (e.g. the admin login's `@error`)
  instead.

### MUST NOT

- Don't introduce a Stimulus controller for something the zero-JS
  patterns above already express — see When to Use for the actual trigger
  condition, and the ADR for the full reasoning.
- Don't register the flash controller from a page/island entrypoint or
  add another global entrypoint just for it; the layout loads the one
  `flash` entrypoint for every page.
- Don't wire the timer with inline `<script>`/`onload` code in the view,
  and don't omit the `disconnect` cleanup.
- Don't add a manual close control without a separate decision; the
  current pattern owns dismissal through its timer alone.
- Don't rely on Escape-key dismissal or a focus trap for a `:target`
  overlay — it doesn't have either (see ADR Consequences). If a specific
  new need genuinely requires them, that's the signal to introduce
  Stimulus for that case, not to fake it in CSS.

## Testing

The zero-JS patterns stay at the project's existing request-spec level
(`rspec-conventions.md`): a request spec asserts the rendered markup
shape (e.g. the trigger is an anchor with the expected `href`, the real
`button_to` form is present somewhere in the response body with its
expected hidden `_method` field). For flash, follow the redirect and
assert the message text is present with the expected `role`/variant, the
`data-controller="flash"`/`data-flash-delay-value` wiring, and that a
request with no flash renders no wrapper.

The flash auto-dismiss behavior itself is JS-driven, so cover it at the
frontend test level: a Vitest test under
`app/frontend/controllers/__tests__/`, using fake timers and a real
Stimulus `Application`, asserting the card gets `is-leaving` after the
delay, is removed after the exit duration, and does not dismiss after the
controller disconnects early. A request spec cannot execute the timer, so
it proves wiring only; no system spec is needed.

## Canonical Implementations

- Confirm overlay: `app_core/app/views/dashboards/show.html.erb`'s
  sign-out confirm (`#signout-confirm`), styled in
  `app_core/app/frontend/dashboard/styles/dashboard.css`.
- Simple disclosure: none currently in the live tree — the dashboard's
  profile menu briefly used `<details>/<summary>` for this before being
  replaced by a directly-clickable icon (now the confirm-overlay case
  above). The next simple reveal-in-place need is the first live
  example of this pattern; follow Structure above rather than
  improvising a new shape.
- Flash messages: `app_core/app/views/shared/_flash.html.erb`, rendered
  from `app_core/app/views/layouts/application.html.erb`, with the toast
  styles in `app_core/app/assets/stylesheets/application.css` (first
  implementation: `agent/plans/render-flash-messages.md`).
- Flash auto-dismiss:
  `app_core/app/frontend/controllers/flash_controller.js` and
  `app_core/app/frontend/entrypoints/flash.js`, loaded by the layout;
  test in `app_core/app/frontend/controllers/__tests__/` (first
  implementation: `agent/plans/flash-auto-dismiss.md`).

## Related ADR

`agent/adr/core/erb-overlays-over-stimulus.md` — why zero-JS CSS is
the default here over Stimulus, and what the accepted trade-offs are.
Its Decision and Implementation Constraints name a timer as the genuine
trigger for the first Stimulus controller; the flash auto-dismiss above
is that case, so no additional ADR is needed.
