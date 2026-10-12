# A Separate `AdminUser` Identity, Session, and Bridge Token Instead of Extending `User`

## Status

Proposed

## Context

`app_core` has exactly one identity/auth stack today: `User`, authenticated
via the Steam OpenID handshake (`Steam::Authenticator`,
`Steam::ProfileFetcher`), with `session[:user_id]` set on successful
login and a short-lived `Steam::BridgeToken` (an HS256 JWT carrying a
`steam_id` claim, signed with `APP_BRIDGE_JWT_SECRET`) minted per
dashboard render so the browser's React island can call `app_fetcher`
directly. Any visitor can become a `User` row by completing Steam login —
it is a self-service signup path, not an internally-granted one.

An admin panel needs a second kind of access: an operator-granted
credential, unrelated to owning any particular Steam account, used to
manage `Item`/`PriceLog`/`UserInventory`/`InventoryValueLog` data in
`app_fetcher` through a new `Api::Admin` namespace there. This data has no
notion of "which player is asking" the way `Api::V1` does — the caller's
identity only needs to answer "is this an authorized administrator,"
nothing else.

## Decision

Introduce `AdminUser` as a wholly separate model, authenticated with
email + password (`has_secure_password`), with its own session key
(`session[:admin_user_id]`) and its own bridge-token class
(`Admin::BridgeToken`, a new `lib/admin/` domain folder — not
`lib/steam/`, since none of this is Steam-domain code), signing with its
own secret (`APP_ADMIN_BRIDGE_JWT_SECRET`) and carrying its own claim
(`admin_id`, not `steam_id`).

`AdminUser` has no foreign key, association, or shared table with `User`.
`Admin::BridgeToken` shares no code with `Steam::BridgeToken` beyond
incidental JWT mechanics (HS256, `exp`/`iat` claims) — it is a sibling
implementation, not a shared base class or a parameterized variant of the
existing one. An `AdminUser` row is created only through an internal,
deliberate action (e.g. a console/seed step) — never as a side effect of
any public-facing request path.

## Alternatives Considered

### Alternative: an `is_admin` boolean column on `User`

Rejected because:

- It conflates two incompatible authentication models in one row: `User`
  authenticates via a passwordless Steam OpenID handshake; admin access
  needs a credential an operator can grant and revoke independent of
  owning a specific Steam account. There is no clean way to "be the
  admin" without also "owning this particular Steam identity," which is
  the wrong coupling — admin access should survive a Steam account
  becoming inaccessible, and should never be grantable by a player simply
  owning the right Steam account.
- Any visitor can create a `User` row today by logging in — `is_admin`
  would sit on a table whose row-creation path is, by design, open to the
  public. Keeping admin-granting power on that table means defending a
  flag against a path that was never meant to need that defense, instead
  of the flag simply not existing where the public path can reach it.
- A compromised or shared Steam account would directly grant admin
  rights, with no independent credential to rotate without also
  disrupting that user's ordinary Steam-login access.

### Alternative: a shared bridge-token payload with an added `admin` claim

Keep one `Steam::BridgeToken` class and one secret; mint a token with an
extra `admin: true` claim for admin requests, verified by the existing
`authenticate_bridge_token!` in `app_fetcher`.

Rejected because:

- A single shared secret means a leak compromises both identity types at
  once, with no way to rotate one without rotating the other.
- The same verification code path (`authenticate_bridge_token!`) would
  need conditional branching on the presence of the admin claim. This
  project already rejected the equivalent shape at the namespace level —
  `.claude/adr/fetcher/public-api-namespace.md` chose a separate
  `Api::Public::` namespace specifically so "a request's auth posture is
  visible structurally, from the class hierarchy alone — no conditional
  to trace, no flag to check," rather than a `skip_before_action`-style
  opt-out on `Api::V1::`. Branching one layer down, inside token
  verification instead of namespace selection, reintroduces exactly the
  pattern that ADR rejected, just moved.

## Consequences

### Positive

- Two independently rotatable secrets and credential types — compromising
  one does not compromise the other.
- Creating an `AdminUser` is always a deliberate, internal action, never a
  side effect of the public Steam-login path.
- A request's identity type is visible from which model/token class is
  involved (`User`/`Steam::BridgeToken` vs. `AdminUser`/
  `Admin::BridgeToken`), not from a conditional flag buried in a shared
  row or payload.

### Negative

- A second password-based credential type to provision and eventually
  support (password reset has no Steam-OAuth equivalent to lean on) —
  out of scope for this decision, to be addressed when that need
  actually arises.
- Structural duplication between the two session/bridge-token stacks
  (two session keys, two base controllers, two token classes). Accepted
  deliberately, for the same reason this project already accepted
  duplication between `Api::V1::ApplicationController` and
  `Api::Public::ApplicationController`'s `rescue_from` — too few examples
  today to guess at the right shared shape.

### Risks

- If a future, genuinely shared concern emerges between the two stacks
  (e.g. identical session-timeout handling), extracting it prematurely
  from only two examples risks guessing the wrong shared shape — the
  same risk this project already named for `Api::V1`/`Api::Public`'s
  duplicated `rescue_from`. Treat this the same way: wait for a real
  third example before extracting anything.

## Implementation Constraints

- `AdminUser`: own table (`admin_users`), own `password_digest` column
  via `has_secure_password`. No association or foreign key to `users`.
- `session[:admin_user_id]` must never be read or written anywhere
  `session[:user_id]` is read or written, and vice versa.
- `Admin::BridgeToken` lives at `app_core/lib/admin/bridge_token.rb` (a
  new `lib/admin/` domain folder), not under `lib/steam/` — it is not
  Steam-domain code, per `core/architecture-layers.md`'s own allowance
  for "a new `lib/<domain>/`" alongside `lib/steam/`.
- `Admin::BridgeToken` signs with `APP_ADMIN_BRIDGE_JWT_SECRET` (a secret
  distinct from `APP_BRIDGE_JWT_SECRET`) and carries an `admin_id` claim
  (not `steam_id`).
- `Api::Admin::ApplicationController#authenticate_admin_bridge_token!` in
  `app_fetcher` must require the `admin_id` claim's presence explicitly,
  not merely that the token decodes — cheap defense-in-depth on top of
  the secret already being different.

## Related

- `.claude/styleguides/core/admin-authentication.md` — the styleguide
  this ADR backs, covering the concrete conventions (session gating,
  response shapes, file structure) beyond the identity-separation
  decision made here.
- `.claude/adr/fetcher/public-api-namespace.md` — the precedent this
  decision's "Alternatives Considered" section draws on, for why a
  conditional flag on a shared path was rejected in favor of a
  structurally separate one.
- `.claude/styleguides/core/architecture-layers.md` — the existing
  single-identity layer map this ADR introduces a second, parallel stack
  alongside.
- `.claude/plans/admin-panel-backend-foundation.md` — the development
  plan this decision unblocks.
