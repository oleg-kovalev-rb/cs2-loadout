---
description: Admin session authentication in app_core — AdminUser, session[:admin_user_id], Admin::BaseController gating, and Admin::BridgeToken — a second, structurally separate identity stack alongside the existing Steam-OAuth User flow.
---

# Admin Authentication (`app_core`)

See `.claude/adr/core/separate-admin-authentication.md` for why this is a
wholly separate stack rather than an extension of `User`/
`Steam::BridgeToken`. This file covers how code inside that stack is
written, once that decision is taken as given.

## Purpose

Give an internally-granted administrator identity its own home, parallel
to but never overlapping with the existing Steam-OAuth `User` stack. What
belongs here: `AdminUser` authentication, admin session gating, and
minting the bridge token `app_fetcher`'s `Api::Admin` namespace verifies.
What does not: anything about Steam identity, Steam OAuth, or the
existing per-player `Steam::BridgeToken` — those stay exactly as
documented in `.claude/styleguides/core/architecture-layers.md`.

## When to Use

Use this pattern for any controller, model, or `lib/` code whose access
should be gated by "is this an authorized administrator" rather than "is
this a particular Steam player." Not relevant to anything already
gated by `current_user`/`session[:user_id]` — that stays on the existing
stack unchanged. A new admin-facing resource controller (e.g. a future
`Admin::ItemsController` once the admin UI is built) belongs under
`Admin::BaseController`, not a standalone auth check.

## Structure

- `app/models/admin_user.rb` — `AdminUser < ApplicationRecord`, own table
  (`admin_users`), `has_secure_password`. No association or foreign key
  to `User`.
- `app/controllers/admin/base_controller.rb` — `Admin::BaseController <
  ApplicationController`, `before_action :require_admin!`. Every
  admin-facing controller other than the session controller itself
  inherits from this, not from plain `ApplicationController`.
- `app/controllers/admin/sessions_controller.rb` —
  `Admin::SessionsController < ApplicationController` (not
  `Admin::BaseController` — logging in can't require already being
  logged in, the same reason the existing `SessionsController` has no
  login guard on itself). `#new` renders the login form (email/password
  fields, submits to `admin_session_path`); `#create`/`#destroy` are
  format-aware (see Interface).
- `lib/admin/bridge_token.rb` — `Admin::BridgeToken`, a new `lib/admin/`
  domain folder, sibling to `lib/steam/`, not inside it (this is not
  Steam-domain code).
- `app/controllers/admin/panel_controller.rb` — the admin-side counterpart
  to `DashboardsController`: `Admin::PanelController < Admin::BaseController`
  (an ordinary admin-facing controller, nothing special beyond the
  `Admin::BaseController` inheritance every such controller already
  follows), `#show` mints `Admin::BridgeToken.encode(current_admin_user.id)`
  and renders the page hosting the mounted admin React island. See
  `architecture-layers.md` for where this fits in `app_core`'s overall
  layer map.
- Routes: `namespace :admin do resource :session, only: %i[new create
  destroy]; get "/", to: "panel#show" end` (route/helper names a starting
  proposal — see the development plan), mirroring the existing `resource
  :session` shape at the top level, extended with `new` now that there's
  a page to render it on.

## Interface

- `current_admin_user` (on `Admin::BaseController`): a single
  `AdminUser.find_by(id: session[:admin_user_id])` lookup, exposed as a
  `helper_method`, same shape as `ApplicationController#current_user`
  today.
- `require_admin!` (on `Admin::BaseController`, `before_action`): format-
  aware (`respond_to`) and halts the filter chain when `current_admin_user`
  is nil. `format.json` — unchanged from before any HTML admin page
  existed: renders `{ message: "Unauthorized" }` / `:unauthorized`.
  `format.html` — redirects to `new_admin_session_path` instead; no JSON
  body for a browser navigation. Never raises, either way.
- `Admin::SessionsController#create`: accepts `email`/`password` params;
  format-aware (`respond_to`). `format.json` — unchanged: on success sets
  `session[:admin_user_id]` and renders `{ message: "..." }` / `:ok`; on
  failure renders `{ message: "Invalid email or password" }` /
  `:unauthorized` — the same message regardless of whether the email
  exists, so the response never discloses which. `format.html` — on
  success sets `session[:admin_user_id]` and redirects to the panel root;
  on failure re-renders `#new` with `status: :unprocessable_content` and
  an inline `@error` the view displays (not Rails `flash` — see Rules for
  why).
- `Admin::SessionsController#new`: renders the login form, no auth guard
  (same reasoning as `#create`/`#destroy` already being on
  `ApplicationController`, not `Admin::BaseController` — see Structure).
- `Admin::SessionsController#destroy`: format-aware (`respond_to`).
  `format.json` — unchanged: clears `session[:admin_user_id]` and renders
  `{ message: "..." }` / `:ok`, idempotently. `format.html` — clears the
  session and redirects to `new_admin_session_path`, idempotently (same
  no-op-on-absent-session behavior either way).
- `Admin::PanelController#show`: mints
  `Admin::BridgeToken.encode(current_admin_user.id)` and renders the
  mounted-React-island page, gated by `Admin::BaseController`'s
  `require_admin!` like any other admin-facing controller — no interface
  beyond what that gating already provides.
- `Admin::BridgeToken.encode(admin_id)`: returns a JWT string, mirroring
  `Steam::BridgeToken.encode`'s exact shape (HS256, `exp`/`iat` claims),
  signed with `APP_ADMIN_BRIDGE_JWT_SECRET`, carrying an `admin_id` claim
  (not `steam_id`).

## Responsibilities

`Admin::BaseController`/`Admin::SessionsController` do session
management and a single-record lookup only. Anything beyond that (e.g.
rate-limiting login attempts, audit-logging admin actions) belongs in an
action under a future `app/actions/admin/`, mirroring how
`app/actions/steam/` holds `Steam::LoginUser` today — not inlined into
the controller. `Admin::BridgeToken` does JWT encoding only, no
persistence, no validation beyond what `JWT.encode`/`JWT.decode`
themselves do.

## Dependencies

One-directional, per `rails-layering.md`:

- `Admin::BaseController`/`Admin::SessionsController` depend on
  `AdminUser` only (a single lookup/authenticate call) — never on `User`,
  `session[:user_id]`, or anything from the Steam-OAuth stack.
- `Admin::BridgeToken` depends on nothing else in the app (external
  crypto only), same rule `lib/steam/` already follows.
- Nothing in the existing Steam-OAuth stack (`User`,
  `SessionsController`, `Steam::BridgeToken`, `lib/steam/`) may depend on
  anything in this one, or vice versa.

## Rules

### MUST

- Every admin-facing controller other than `Admin::SessionsController`
  inherits from `Admin::BaseController` — never gate admin access with an
  ad hoc check inlined in a specific controller.
- Use `session[:admin_user_id]` exclusively for admin identity. Never
  read or write `session[:user_id]` from any `Admin::` controller, and
  never read or write `session[:admin_user_id]` from any non-`Admin::`
  controller.
- `# typed: strict`, `extend T::Sig`, and a `sig` on every method, on
  every file in this stack, per `ruby-sorbet.md` — including controllers.
  The existing `SessionsController`/`ApplicationController` currently
  deviate from this (`typed: true` / no sigil at all, logged in
  `fix_me.md`); that is drift on existing files, not a precedent for new
  ones.
- `Admin::SessionsController#create`/`#destroy` and `require_admin!` are
  format-aware (`respond_to do |format| ... end`): `format.json` renders
  `{ message: "..." }` with an explicit status symbol, exactly as before
  this rule's revisit below — never a redirect for a JSON caller,
  regardless of how the HTML path behaves. `format.html` redirects (see
  Interface for exact targets). This supersedes this rule's original
  wording ("never a redirect... revisit once a real admin UI defines an
  actual redirect target") now that `Admin::PanelController`/the login
  page are that real admin UI — the supersession is additive (a new
  format branch), not a removal of the JSON guarantee the original rule
  protected.
- The login form's failure path (`Admin::SessionsController#create`,
  `format.html`) passes its error as an instance variable the `#new` view
  renders inline, not via Rails `flash` — this codebase sets `flash[:notice]`/
  `flash[:alert]` elsewhere (`SessionsController#callback`/`#destroy`) but
  no layout currently renders `flash` anywhere (confirmed drift, logged in
  `fix_me.md`, not fixed here — out of scope for this stack). Depending on
  `flash` here would silently produce the same never-displayed message;
  an explicit `@error` local sidesteps that pre-existing gap rather than
  building on top of it.
- Downcase `AdminUser#email` before validation/save (e.g. a
  `before_validation` callback) so uniqueness is effectively
  case-insensitive without a database-level `citext`/functional index.
- `Admin::BridgeToken.encode` mirrors `Steam::BridgeToken.encode`'s shape
  exactly (HS256, `exp`/`iat`), signed with `APP_ADMIN_BRIDGE_JWT_SECRET`,
  claim name `admin_id`.
- Uncomment `gem "bcrypt", "~> 3.1.7"` in `app_core/Gemfile` — required
  for `AdminUser#has_secure_password`; it is not needed anywhere else in
  `app_core` today.

### MUST NOT

- Don't add an `is_admin`/role column to `User`, and don't add an admin
  claim to the existing `Steam::BridgeToken` payload — see the Related
  ADR for why.
- Don't put `AdminUser` lookup or password-check logic directly in
  `Admin::BaseController` beyond the single `find_by` call — anything
  more (e.g. lockout after failed attempts) belongs in an action, once
  there is actual logic beyond "look up by id."
- Don't place `Admin::BridgeToken` under `lib/steam/` — it is not
  Steam-domain code, even though it mirrors `Steam::BridgeToken`'s shape.

## Error Handling

- Missing/expired admin session (`require_admin!`) → `format.json`: `{
  message: "Unauthorized" }` / `:unauthorized`. `format.html`: redirect to
  `new_admin_session_path`, no body to speak of.
- Bad login credentials (`Admin::SessionsController#create`) →
  `format.json`: `{ message: "Invalid email or password" }` /
  `:unauthorized` — identical message whether the email doesn't exist or
  the password is wrong. `format.html`: re-render `#new`,
  `:unprocessable_content`, same identical-message rule via `@error`.
- Logout (`#destroy`) never fails either format — clearing an
  already-absent session key is a no-op, not an error.

## Testing

General RSpec mechanics (request-spec structure, `FactoryBot`) are
governed by `.claude/styleguides/rspec-conventions.md`; this section only
adds what's specific to this stack.

- Request specs live under `app_core/spec/requests/admin/` (e.g.
  `sessions_spec.rb`), `type: :request`, matching this project's
  controller→request-spec default mapping.
- `AdminUser` validations/`has_secure_password` behavior is a unit spec
  under `app_core/spec/models/admin_user_spec.rb` (no `type:` metadata).
- `Admin::BridgeToken` gets a unit spec under
  `app_core/spec/lib/admin/bridge_token_spec.rb`, mirroring
  `bridge_token_spec.rb`'s existing two cases exactly (claim + TTL
  round-trip; wrong-secret rejection via `JWT::VerificationError`).
- Use a `FactoryBot` factory (`spec/factories/admin_users.rb`) for test
  `AdminUser` records — no fixture, per `rspec-conventions.md`.
- Format-aware actions get coverage for both formats in the same spec
  file: a `format.json` example asserting the pre-existing JSON behavior
  is unchanged (regression proof, not just new-behavior proof), plus
  `format.html` examples for the new redirect/re-render paths (success
  redirect target, failure re-render status + inline error, `require_admin!`'s
  redirect-to-login for an unauthenticated HTML request).
- `Admin::PanelController` gets its own request spec
  (`app_core/spec/requests/admin/panel_spec.rb`): unauthenticated request
  redirects to login; authenticated request renders `200` with a
  non-blank bridge token present in the response body.

## Canonical Implementations

- `app_core/app/models/admin_user.rb`
- `app_core/app/controllers/admin/base_controller.rb`
- `app_core/app/controllers/admin/sessions_controller.rb` — the
  pre-existing JSON-only `create`/`destroy` shape; the format-aware
  `respond_to` version, `#new`, and the login view are not yet
  implemented as of this amendment.
- `app_core/lib/admin/bridge_token.rb`
- `Admin::PanelController` and the `app/frontend/admin-panel/` React
  island: not yet implemented — first implementation lands via
  `.claude/plans/admin-panel-frontend.md`. Update this section once that
  plan is implemented.

## Related ADR

`.claude/adr/core/separate-admin-authentication.md`
