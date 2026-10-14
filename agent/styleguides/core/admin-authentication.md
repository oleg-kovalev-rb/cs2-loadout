---
description: Admin session authentication in app_core — AdminUser, session[:admin_user_id], Admin::BaseController gating, and Admin::BridgeToken — a second, structurally separate identity stack alongside the existing Steam-OAuth User flow.
---

# Admin Authentication (`app_core`)

See `agent/adr/core/separate-admin-authentication.md` for why this is a
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
documented in `agent/styleguides/core/architecture-layers.md`.

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
  login guard on itself).
- `lib/admin/bridge_token.rb` — `Admin::BridgeToken`, a new `lib/admin/`
  domain folder, sibling to `lib/steam/`, not inside it (this is not
  Steam-domain code).
- Routes: `namespace :admin do resource :session, only: %i[create
  destroy] end`, mirroring the existing `resource :session` shape at the
  top level.

## Interface

- `current_admin_user` (on `Admin::BaseController`): a single
  `AdminUser.find_by(id: session[:admin_user_id])` lookup, exposed as a
  `helper_method`, same shape as `ApplicationController#current_user`
  today.
- `require_admin!` (on `Admin::BaseController`, `before_action`): renders
  `{ message: "Unauthorized" }` / `:unauthorized` and halts the filter
  chain when `current_admin_user` is nil. Never raises.
- `Admin::SessionsController#create`: accepts `email`/`password` params;
  on success sets `session[:admin_user_id]` and renders `{ message: "..."
  }` / `:ok`; on failure renders `{ message: "Invalid email or password"
  }` / `:unauthorized` — the same message regardless of whether the email
  exists, so the response never discloses which.
- `Admin::SessionsController#destroy`: clears `session[:admin_user_id]`
  and renders `{ message: "..." }` / `:ok`, idempotently (succeeds even if
  no admin session existed).
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
- `Admin::SessionsController#create`/`#destroy` render `{ message: "..."
  }` with an explicit status symbol — never a redirect. There is no admin
  UI page yet to redirect to, and a JSON response keeps the action
  directly testable on status + body alone. Revisit this rule once a real
  admin UI defines an actual redirect target.
- `require_admin!` failures render `{ message: "Unauthorized" }` /
  `:unauthorized`, matching this project's established cross-app error
  body shape (`{ message: "..." }`) even though this is the first JSON
  response `app_core` has ever rendered.
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

- Missing/expired admin session (`require_admin!`) → `{ message:
  "Unauthorized" }` / `:unauthorized`.
- Bad login credentials (`Admin::SessionsController#create`) → `{
  message: "Invalid email or password" }` / `:unauthorized` — identical
  message whether the email doesn't exist or the password is wrong.
- Logout (`#destroy`) never fails — clearing an already-absent session
  key is a no-op, not an error.

## Testing

General RSpec mechanics (request-spec structure, `FactoryBot`) are
governed by `agent/styleguides/rspec-conventions.md`; this section only
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

## Canonical Implementations

None yet — this is the first styleguide-governed implementation of this
stack. The first ones should go at `app_core/app/models/admin_user.rb`,
`app_core/app/controllers/admin/base_controller.rb`,
`app_core/app/controllers/admin/sessions_controller.rb`, and
`app_core/lib/admin/bridge_token.rb`. Update this section once those
exist.

## Related ADR

`agent/adr/core/separate-admin-authentication.md`
