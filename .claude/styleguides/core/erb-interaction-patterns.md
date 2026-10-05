---
description: Zero-JS interactivity patterns for app_core's plain ERB views (outside the React island) — disclosures and confirm overlays, and when to reach for Stimulus instead.
---

# ERB Interaction Patterns (`app_core`)

## Purpose

`app_core`'s dashboard page is mostly the React island
(`app/frontend/dashboard/`, see `react-dashboard.md`), but its
surrounding chrome — topbar, sign-in/sign-out — is plain server-rendered
ERB outside that island. This file covers how that chrome gets
interactivity (a disclosure, a confirm-before-destructive-action
overlay) without introducing a new JS layer for something CSS already
solves. See `.claude/adr/core/erb-overlays-over-stimulus.md` for why
zero-JS is the default here instead of Stimulus (present in the Gemfile,
unused anywhere in `app_core` today).

## When to Use

Applies to interactivity needed in `app_core`'s plain ERB views (the
dashboard's topbar and anything else outside `#dashboard-root`). Does
not apply to the React island itself — see `react-dashboard.md` for that.

Two named patterns below cover what's needed so far. Reach for a
Stimulus controller instead only when neither fits — concretely: the
behavior needs to sync with something that isn't expressible as a CSS
selector (a timer, a network response, state shared across more than
one disconnected part of the page), or needs keyboard handling beyond
what native focusable anchors/elements give for free (Escape-key
dismissal, a real focus trap). Introducing Stimulus for that first
genuine case is expected and correct — these patterns aren't meant to be
stretched past where they fit.

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

### SHOULD

- Reuse the existing color tokens (`--down`/`--down-soft` for
  destructive/danger, `--accent`/`--accent-soft` for primary) from
  `dashboard.css`'s custom-property block rather than introducing new
  color literals for a new interactive element.

### MUST NOT

- Don't introduce a Stimulus controller for something either pattern
  above already expresses — see When to Use for the actual trigger
  condition, and the ADR for the full reasoning.
- Don't rely on Escape-key dismissal or a focus trap for a `:target`
  overlay — it doesn't have either (see ADR Consequences). If a specific
  new need genuinely requires them, that's the signal to introduce
  Stimulus for that case, not to fake it in CSS.

## Testing

No dedicated test level beyond the project's existing request-spec
convention (`rspec-conventions.md`) — a request spec asserts on the
rendered markup shape (e.g. the trigger is an anchor with the expected
`href`, the real `button_to` form is present somewhere in the response
body with its expected hidden `_method` field). There's nothing
JS-driven to exercise, so no system spec is needed for either pattern.

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

## Related ADR

`.claude/adr/core/erb-overlays-over-stimulus.md` — why zero-JS CSS is
the default here over Stimulus, and what the accepted trade-offs are.
