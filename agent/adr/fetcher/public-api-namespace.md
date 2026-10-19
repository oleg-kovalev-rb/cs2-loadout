# A Sibling `Api::Public::` Namespace for Unauthenticated Endpoints, With a Duplicated (Not Shared) Base Controller

## Status

Accepted — originally proposed for two namespaces (`Api::V1::`/
`Api::Public::`); re-affirmed when a third (`Api::Admin::`) reached this
ADR's own revisit trigger (see Consequences).

## Context

Every `app_fetcher` API endpoint to date lives under `Api::V1::` and is
authenticated by a bridge token minted by `app_core`
(`agent/styleguides/fetcher/internal-api-controllers.md`). That file is
explicit that this is deliberate, not incidental: its Purpose section
states the API "is not a public API — it has exactly one consumer,
`app_core`," and its Rules carry a MUST NOT against
`skip_before_action :authenticate_bridge_token!` specifically, reasoning
that "a genuinely public endpoint is a decision to make and document
explicitly, not a one-line opt-out on a controller."

The items-catalog feature
(`agent/plans/public-items-catalog-endpoint.md`) needs exactly that
genuinely-public endpoint: a read-only items listing usable by anonymous
visitors (a demo use case) as well as logged-in ones, with no bridge
token and no `app_core` involvement in the request path at all. This is
the first time any `app_fetcher` endpoint has needed to serve a caller
other than `app_core`, and the first time any endpoint has needed no
identity at all — `Api::V1::`'s entire interface (`current_steam_id` as
"the only source of the caller's identity") has no notion of "there is
no identity for this request," since every existing action is
authenticated by construction.

Separately, `Api::V1::BaseController` already carries a second,
independent concern beyond auth: a catch-all `rescue_from StandardError`
(`agent/plans/fetcher-base-controller-rescue-from.md`), logging and
rendering `{ message: "Internal error" }` / `:internal_server_error` for
any unhandled infra-level failure. A new, unauthenticated endpoint still
needs this same safety net — an unhandled DB error shouldn't produce a
different failure shape just because the endpoint happens to be public.

## Decision

Introduce `Api::Public::` as a new namespace, sibling to `Api::V1::`,
under `app/controllers/api/public/`. Its own
`Api::Public::BaseController < ::ApplicationController` carries no
authentication `before_action` at all — the absence of any identity
check is the entire point, not an opt-out of one. It independently
declares `rescue_from StandardError, with: :render_internal_server_error`,
with a handler identical in behavior to `Api::V1::BaseController`'s
(log via `Rails.logger.error`, render `{ message: "Internal error" }` /
`:internal_server_error`) — written again in the new class, not inherited
from a shared ancestor.

This duplicates roughly ten lines between the two namespace base
controllers. That is accepted deliberately: this project has already
taken the position, for `app/services/`, that a shared base
abstraction (a base-service/`Result` class) is deferred until there are
enough real members of a layer to show what the right shared shape
actually is, rather than guessed at from the first two. The same
reasoning applies here, with only two controller namespaces existing.
The explicit trigger to revisit: the moment a third namespace needs this
same error-handling shape, extract a shared `Api::BaseController` then,
informed by three real examples instead of two.

Every other `Api::V1::` convention — explicit `render json: { ... },
status: :symbol`; `{ message: "..." }` error bodies; the "exactly one
collaborator call per action" shape — carries over to `Api::Public::`
unchanged, for the same reason the error-handling shape does: both
namespaces are the same kind of thing (a small internal-to-this-app JSON
API), differing only in whether a caller must prove an identity first.

## Alternatives Considered

### Alternative: a shared `Api::BaseController` ancestor

`Api::BaseController < ActionController::API` holds the
`rescue_from`/handler; `Api::V1::BaseController < Api::BaseController`
adds the bridge-token `before_action`; `Api::Public::BaseController <
Api::BaseController` adds nothing further.

Rejected for now: with only two namespaces, both trivially simple
(~ten lines each), there isn't yet a second data point to confirm the
extraction is the *right* shared shape rather than just *a* shared shape
— the same situation this project already declined to guess at for
`app/services/`. Revisit per the Decision's explicit trigger.

### Alternative: per-controller `skip_before_action` opt-out on `Api::V1::`

Keep one namespace; mark the new catalog action as exempt from
`authenticate_bridge_token!` via `skip_before_action` on
`Api::V1::ItemsController` specifically.

Rejected outright: `internal-api-controllers.md` already has a MUST NOT
rule against exactly this, for the reason stated there — a public
endpoint is architecturally different from an authenticated one that
merely skips its check (no identity at all, different caching posture,
different threat model), and conflating the two in one controller tree
risks a future accidental regression (e.g. a global auth change that
doesn't notice the opt-out, or a reviewer who doesn't expect `Api::V1::`
to ever render for an anonymous caller).

### Alternative: one `ApplicationController`, conditional auth via a flag/route check

Keep a single base controller; have `authenticate_bridge_token!` itself
check something (a route default, an instance variable) to decide
whether to run.

Rejected: makes a request's auth posture something you trace through a
conditional at runtime rather than read directly off the class
hierarchy. "Is this endpoint public?" should be answerable by seeing
which `ApplicationController` a controller inherits from, not by reading
a branch.

## Consequences

### Positive

- A request's auth posture is visible structurally, from the class
  hierarchy alone — no conditional to trace, no flag to check.
- `Api::V1::`'s existing MUST NOT rule (no per-controller auth opt-out)
  stays intact and unambiguous; the public case is handled by a
  different namespace entirely, not an exception carved into the
  existing one.
- Each base controller stays small enough to audit in full at a glance.

### Negative

- ~ten lines of `rescue_from`/handler duplicated between the two base
  controllers today.
- If a third namespace with the same error-handling need appears before
  this is revisited, the duplication grows to three copies rather than
  being caught at two.

### Risks

- A future contributor could "DRY" the two base controllers on sight
  without checking whether a third real case exists yet, undoing the
  deliberate wait-for-the-third-example reasoning here. This ADR's
  explicit revisit trigger (Decision) is the guard against that — cite it
  before extracting.

### Update: Third-Namespace Trigger Reached (`Api::Admin::`)

The revisit trigger named above and in Implementation Constraints fired
when `Api::Admin::` (see `agent/plans/admin-panel-backend-foundation.md`,
`agent/styleguides/fetcher/admin-api-controllers.md`) needed the
identical `rescue_from StandardError`/handler shape `Api::V1::`/
`Api::Public::` already have. Extracting a shared `Api::BaseController`
was explicitly considered at this point and declined — each of the three
base controllers' `before_action` differs in a way that isn't
`rescue_from`-related (no auth at all for `Api::Public::`, a per-player
bridge token for `Api::V1::`, an admin bridge token for `Api::Admin::`),
so a shared base would only ever be sharing the `rescue_from`/handler
itself — still the same ~ten lines this ADR already accepted as the cost
of waiting for real examples, now tripled rather than doubled. This is a
recorded, deliberate re-affirmation of the original decision, not an
oversight — if a fourth namespace reaches this same point, decide afresh
there rather than treating this note as a standing exemption.

### Update: Namespace Base Controllers Renamed

The namespace base controllers were later renamed from
`Api::*::ApplicationController` to `Api::*::BaseController`, and each now
inherits the app-wide, namespace-neutral
`ApplicationController < ActionController::API` rather than inheriting
`ActionController::API` directly. This is a naming/ancestry cleanup, not
a reversal of the shared-`Api::BaseController` decision above: the common
`ApplicationController` carries no auth or rescue behavior, and each
namespace `BaseController` still declares its own `before_action` and
`rescue_from` handlers independently. The rejected abstraction was a
shared `Api::BaseController` holding shared error-handling behavior, not
a behaviorless Rails-level common ancestor.

## Implementation Constraints

- `Api::V1::BaseController < ::ApplicationController`, its own file at
  `app_fetcher/app/controllers/api/v1/base_controller.rb` — player
  bridge-token `before_action`, its own `rescue_from StandardError`, and
  its own `rescue_from Api::V1::UnsupportedParamError`.
- `Api::Public::BaseController < ::ApplicationController`, its own
  file at `app_fetcher/app/controllers/api/public/base_controller.rb`.
  No `before_action` for authentication of any kind.
- `Api::Admin::BaseController < ::ApplicationController`, its own file
  at `app_fetcher/app/controllers/api/admin/base_controller.rb` — admin
  bridge-token `before_action`, its own `rescue_from StandardError`, and
  its own `rescue_from ActiveRecord::RecordNotFound`.
- `rescue_from StandardError, with: :render_internal_server_error`
  declared independently on `Api::Public::BaseController`, with a
  handler matching `Api::V1::BaseController`'s behavior exactly
  (same log call shape, same rendered body/status) — copy the method,
  do not require/include/inherit it from the `Api::V1::` class.
  Rendering/status-symbol/error-body conventions otherwise match
  `internal-api-controllers.md`'s existing Interface/Error Handling
  sections verbatim — not restated in the new styleguide, just
  cross-referenced.
- Keep `Api::BaseController` (a shared namespace ancestor holding the
  `rescue_from`/handler) unextracted. The third-namespace trigger already
  fired and was declined (see Consequences); a fourth namespace should
  decide afresh rather than inherit this as a standing exemption. The
  behaviorless top-level `ApplicationController` ancestor introduced by
  the rename is not that abstraction.

## Related

- `agent/styleguides/fetcher/internal-api-controllers.md` — the
  existing `Api::V1::` namespace this one is a sibling to, and whose own
  MUST NOT rule (no per-controller auth opt-out) is why this is a new
  namespace rather than an exception on the existing one.
- `agent/styleguides/fetcher/public-api-controllers.md` — the
  styleguide this ADR backs, covering `Api::Public::`'s concrete
  conventions (query-param handling, response shape) beyond the
  namespace/base-controller decision made here.
- `agent/adr/fetcher/cross-scenario-service-layer.md` — the closest
  precedent for this ADR's "introduce a new, small, duplicated thing
  rather than guess at a shared abstraction from too few examples"
  reasoning style, and the source of the base-service/`Result`-class
  deferral this decision explicitly draws on.
- `agent/plans/fetcher-base-controller-rescue-from.md` — the plan that
  put `rescue_from StandardError` on `Api::V1::BaseController` in
  the first place; this ADR gives `Api::Public::` the same safety net
  independently.
- `agent/plans/public-items-catalog-endpoint.md` — the plan this
  decision unblocks.
- `agent/styleguides/fetcher/admin-api-controllers.md` — the third
  namespace (`Api::Admin::`) whose introduction reached this ADR's
  revisit trigger; see Consequences for the recorded outcome.
- `agent/plans/admin-panel-backend-foundation.md` — the plan that
  introduced that third namespace.
