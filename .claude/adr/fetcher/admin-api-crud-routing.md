# `Api::Admin::` Uses Real RESTful CRUD Routing, Not Explicit Action Routes

## Status

Proposed

## Context

`.claude/styleguides/fetcher/internal-api-controllers.md` establishes that
`Api::V1::` routes are always declared explicitly (`get "inventories/me",
to: "inventories#show"`), "never a bare `resources :x`, since these
aren't CRUD resources" — every `Api::V1::` action is action-oriented
(fetch a price, refresh an inventory, read a trend), not a create/read/
update/delete lifecycle on an addressable record. `Api::Public::`
inherited the identical rule for the same reason (its one endpoint,
`#catalog`, is a filtered listing, not CRUD either).

`Api::Admin::` introduces this codebase's first genuinely CRUD-shaped
internal API resource: `Item` gets real create/read/update/destroy
actions on individual, id-addressed records, and `PriceLog`/
`UserInventory`/`InventoryValueLog` get read/destroy lifecycles on their
own records (nested under their owning resource). This is a materially
different shape from anything `Api::V1::`/`Api::Public::` have needed so
far, and the existing "never bare `resources :x`" rule's own stated
reason — "these aren't CRUD resources" — doesn't hold for it.

## Decision

`Api::Admin::` uses standard Rails RESTful routing (`resources :items`,
and nested `resources :price_logs, only: %i[index destroy]` under
`items`, `resources :inventory_value_logs, only: %i[index destroy]`
under `user_inventories`) for its genuine CRUD resources. Non-CRUD
actions on those same resources (`refresh_price`, `warm_cache` on
`items`; `sync`, `warm_cache` on `user_inventories`) stay explicit member
routes, the same shape `Api::V1::`/`Api::Public::` already use for all of
their actions.

This is a deliberate, scoped exception to `internal-api-controllers.md`'s
"never bare `resources :x`" rule, limited to this one namespace and
justified by this namespace's resources actually being CRUD — it does
not relax that rule for `Api::V1::`/`Api::Public::`, where it continues
to apply exactly as written.

## Alternatives Considered

### Alternative: explicit named routes for `Api::Admin::` too, mirroring `Api::V1::`/`Api::Public::` exactly

Keep every `Api::Admin::` route as a hand-written `get`/`post`/`patch`/
`delete ..., to: "..."` line, the same shape as the other two namespaces,
for consistency across all three.

Rejected because:

- `Api::Admin::Items` genuinely is a CRUD resource — hand-rolling five
  separate named routes per resource to avoid `resources` reproduces
  exactly what `resources` already generates correctly, for no benefit.
- The other two namespaces' rule exists *because* their endpoints aren't
  CRUD-shaped. Applying the same rule here would be following its letter
  past its own stated reason, not preserving what the rule actually
  protects against (route declarations that don't match a real resource
  lifecycle).
- Hand-maintained routes for genuine CRUD add surface area for a
  route/controller-action mismatch to go unnoticed, with no
  corresponding benefit `resources` doesn't already provide for real CRUD.

## Consequences

### Positive

- `Api::Admin::` routes read as standard, idiomatic Rails CRUD —
  immediately recognizable, no hand-maintained route list to keep in
  sync with the controller's actual actions.
- Named-route helpers (`admin_item_path`, etc.) come for free.

### Negative

- `Api::Admin::`'s routing shape diverges from its two sibling
  namespaces — a reader comparing all three `config/routes.rb` blocks
  won't find the same convention in all three, and needs this ADR to
  understand why.

### Risks

- If a future `Api::Admin::` resource turns out not to be genuine CRUD
  (a pure action-oriented admin endpoint with nothing resembling a
  create/read/update/destroy lifecycle behind it), it would be a mistake
  to force it into `resources` just because this namespace generally
  uses that shape. Decide per-resource when that comes up, not by
  reflexively following this namespace's general convention.

## Implementation Constraints

- `resources` (full or restricted via `only:`) is used only for an
  `Api::Admin::` resource that has an actual create/read/update/destroy
  lifecycle on an addressable record.
- Non-CRUD actions (`refresh_price`, `warm_cache`, `sync`) are declared
  as explicit member routes inside the relevant `resources` block, never
  as a bare top-level route mimicking `Api::V1::`'s style.
- Nesting stays one level deep, matching the actual data ownership
  (`PriceLog belongs_to :item`, `InventoryValueLog` scoped by
  `UserInventory`'s `steam_id`) — don't nest further than the data model
  itself does.
- A non-CRUD action with no single natural `:id` to key off — it operates
  on a client-supplied list (e.g. a bulk cache-warm across several ids)
  or on no identifying param at all (e.g. a catalog-wide action) — is a
  `collection` route, not a `member` route. This isn't a new exception to
  the decision above, just this ADR's routing vocabulary catching up to a
  case Rails' own `resources` DSL already distinguishes: `member` for
  one-`:id`-at-a-time actions, `collection` for everything else.
- A resource that's nested for its primary CRUD/identity purpose may
  *also* get a second, top-level, read-only route when there's a genuine
  cross-parent listing need (e.g. an admin UI page that browses the
  resource across every parent at once, not one parent at a time) — the
  nested route stays exactly as it was, unmodified; the flat one is
  additive, not a replacement. Unlike the genuine-CRUD resources this
  ADR's main Decision covers, this flat listing has no single addressable
  record of its own, so it's declared as an explicit route (`get
  "<resource>", to: "<resource>#global_index"`), the same style
  `Api::V1::`/`Api::Public::` already use for their own non-CRUD actions
  — not forced into `resources` just because the rest of this namespace
  generally prefers it. Dispatching to a distinct action name
  (`global_index`, not `index`) avoids colliding with the nested route's
  own `#index` on the same controller. This is decided per-resource, the
  same case-by-case posture as every other exception in this ADR, not a
  standing invitation to flatten every nested resource in this namespace
  "for consistency."

## Related

- `.claude/styleguides/fetcher/internal-api-controllers.md` — the
  "never bare `resources :x`" rule this ADR carves a scoped exception
  out of, for the specific reason that rule itself states.
- `.claude/styleguides/fetcher/public-api-controllers.md` — the second
  namespace that inherited the same rule unchanged, for contrast with
  why `Api::Admin::` doesn't.
- `.claude/adr/fetcher/public-api-namespace.md` — the precedent for why
  `Api::Admin::` gets its own base controller/`rescue_from` rather than a
  shared one; this ADR covers only the routing-shape question, not that
  one.
- `.claude/styleguides/fetcher/admin-api-controllers.md` — the
  styleguide this ADR backs.
- `.claude/plans/admin-panel-backend-foundation.md` — the development
  plan this decision unblocks.
