---
status: implemented
app: fetcher
goal: Add a catch-all rescue_from StandardError to app_fetcher's ApplicationController so unexpected failures (DB/infra errors) return the API's standard JSON error shape instead of a raw/empty 500
created: 2026-10-03
---

## Applicable Styleguides

- **`.claude/styleguides/fetcher/internal-api-controllers.md`** —
  governs the `rescue_from` addition itself. Its "Error Handling" section
  now documents the new third failure shape (`rescue_from StandardError`
  → `{ message: "Internal error" }` / `:internal_server_error`, required
  `Rails.logger.error` logging) and its MUST rule against a speculative
  per-action rescue/branch carries an explicit carve-out confirming this
  global catch-all is a different category, not a violation of that
  rule. Also constrains response shape generally (always an explicit
  hash + status symbol) and confirms the catch-all must never shadow
  `InventoriesController`'s existing `Steam::Client`/`response.success?`
  branch.
- **`.claude/styleguides/ruby-sorbet.md`** — governs the new private
  handler method: `# typed: strict` stays on the file, the method gets
  an explicit `sig { params(exception: StandardError).void }`, and
  (per its "Rescue at the end of the method body" convention)
  `rescue_from`'s handler is itself a plain method, consistent with how
  `authenticate_bridge_token!` is structured in the same file.
- **`.claude/styleguides/rspec-conventions.md`** — governs the new
  request-spec context: `type: :request` under
  `spec/requests/api/v1/inventory_values_spec.rb` (matching this app's
  only controller-spec pattern), stub set up via a `before` block per
  Example Structure, and assertions wrapped in `aggregate_failures`. Its
  "never stub the database" MUST NOT rule is why the plan stubs
  `current_steam_id` (an `ApplicationController` method) rather than an
  ActiveRecord call — no change to this styleguide was needed once the
  test target moved off the database entirely.

# Development Plan

## Goal

When an action in `Api::V1::` raises an exception that isn't already
handled by the action itself (today: infrastructure/DB-level failures —
e.g. a lost Postgres connection), `app_fetcher` responds with the same
JSON error shape every other error path already uses
(`{ message: "..." }` + an explicit status symbol) instead of today's
raw/empty 500 body, and logs the exception so it's not silently lost.

This is a narrow, single-purpose addition: one catch-all `rescue_from`,
nothing else. It does not add handling for exceptions that have no live
path in the code today (see Scope).

## Expected Behavior

- **Normal behavior (unchanged):** every existing endpoint, auth failure
  (missing/invalid/expired bridge token), and explicit business-failure
  branch (`Steam::Client` failure → `:bad_request`, unsupported period →
  `:bad_request`, refresh dedup → `:too_many_requests`, unknown
  `market_hash_name` → empty array) behaves exactly as it does today. The
  new `rescue_from` only ever fires for an exception that would otherwise
  have gone unhandled.
- **New failure behavior:** if an action raises any `StandardError`
  subclass that isn't rescued closer to its source (e.g.
  `ActiveRecord::ConnectionNotEstablished`, `PG::ConnectionBad`, or any
  other unexpected runtime error), the response is `render json: {
  message: "Internal error" }, status: :internal_server_error` — a
  generic, non-leaking message, not the exception's own message or
  backtrace.
- Before rendering, the exception is logged via `Rails.logger.error` with
  enough detail to debug it (exception class, message, backtrace) — this
  replaces the default Rails middleware logging that is skipped once the
  exception is rescued inside the controller (see research finding #5).
- **Behavior explicitly NOT added:** no `rescue_from
  ActiveRecord::RecordNotFound`. No live path raises it today (the one
  `find_by` call already returns `nil` and is branch-handled) — adding it
  would be exactly the kind of defensive-rescue-for-something-that-can't-fail
  the fetcher internal-api-controllers styleguide prohibits. If a future
  change introduces a `find`/`find_by!` that can raise it, that's a
  separate, later decision.
- **Explicitly NOT added:** no external error-tracking integration
  (Sentry/Rollbar/etc). `Rails.logger.error` is the full extent of
  observability for this change.

## Scope

### In Scope

- One `rescue_from StandardError` (plus its handler method) added to
  `app_fetcher/app/controllers/application_controller.rb`.
- Logging the rescued exception via `Rails.logger.error`.
- A request-spec regression test proving the new behavior through one
  representative endpoint.

### Out of Scope

- `rescue_from ActiveRecord::RecordNotFound` (or any other specific
  exception class) — no live trigger exists today; see Expected Behavior.
- Any error-tracking/APM gem (Sentry, Rollbar, Honeybadger, etc.).
- Adding `public/500.html`/`422.html`/`404.html` or otherwise changing
  Rails' default `exceptions_app` behavior — the new `rescue_from`
  intercepts the exception before it ever reaches that fallback, for
  every `Api::V1::` action (the only actions this app has).
- Changing `app_core`'s client-side fetch/error handling
  (`useDashboardData.js` and sibling hooks only check `response.ok`
  today) — out of scope for this change, noted as a fact, not a problem
  to fix here.
- Updating `.claude/styleguides/fetcher/internal-api-controllers.md`'s
  Error Handling section to document the new catch-all — that
  reconciliation (the styleguide currently only documents the two
  existing failure shapes) happens in `styleguides-check`, not here.

## Implementation Approach

Add a single class-level `rescue_from StandardError, with:
:render_internal_server_error` to
`app_fetcher/app/controllers/application_controller.rb`, alongside a
private `render_internal_server_error(exception)` method that logs then
renders. This follows the same file's existing shape (a private method
handling a failure case, `extend T::Sig`, explicit `sig`) rather than
introducing a new concern/module — there is exactly one rescue handler in
this class today and this adds a second, both small enough to stay
inline.

`rescue_from` is registered once, globally, on `ApplicationController` —
every `Api::V1::` controller inherits it automatically, matching how
`authenticate_bridge_token!`'s `before_action` already applies globally
(per `internal-api-controllers.md`: "applies `before_action
:authenticate_bridge_token!` globally, not opt-in per controller").

No new classes, modules, or abstractions — this is deliberately the
smallest change that satisfies the requirement (one `rescue_from` + one
handler method).

## Files To Modify

- **`app_fetcher/app/controllers/application_controller.rb`**
  - Add `rescue_from StandardError, with: :render_internal_server_error`
    as a class-level declaration (alongside `before_action
    :authenticate_bridge_token!`).
  - Add a private `sig { params(exception: StandardError).void }` method,
    `render_internal_server_error(exception)`, that:
    1. Logs via `Rails.logger.error` — exception class, message, and
       backtrace (e.g. `"#{exception.class}: #{exception.message}\n#{exception.backtrace&.join("\n")}"`).
    2. Renders `{ message: "Internal error" }` with `status:
       :internal_server_error`.
  - Reason: single place every `Api::V1::` controller inherits from;
    matches the existing pattern of handling auth failures in this same
    file.

- **`app_fetcher/spec/requests/api/v1/inventory_values_spec.rb`**
  - Add a new `context` under the existing `GET /api/v1/inventory_values`
    describe block that stubs `current_steam_id` (an
    `ApplicationController` instance method, not a model/DB call) to
    raise a generic `StandardError`, and asserts the response.
  - Reason: this is a boundary-contract concern (status code, response
    shape) — exactly what `rspec-conventions.md` says request specs own —
    and it isn't re-testing `InventoryValuesController`'s own business
    logic. Stubbing `current_steam_id` (rather than
    `InventoryValueLog.where`, the first approach considered) avoids
    stubbing the database, which `rspec-conventions.md` prohibits "at any
    level ... always" — see Risks. `app_core/spec/requests/home_pages_spec.rb`
    already stubs the equivalent method on its own `ApplicationController`
    (`allow_any_instance_of(ApplicationController).to
    receive(:current_user).and_return(...)`), so this isn't a novel
    pattern in this codebase, just the `and_raise` counterpart of an
    existing one.

## Files To Create

None. No new classes, concerns, or spec files are needed for a
single-method addition to an existing controller.

## Test Plan

Single new request-spec context, added to
`app_fetcher/spec/requests/api/v1/inventory_values_spec.rb` (`type:
:request`, matching every other controller spec in this app — see
`rspec-conventions.md`'s layer→level mapping).

- **Scenario:** a valid bridge token (so the request reaches the action),
  but `current_steam_id` itself raises a generic `StandardError` once
  inside the action — stubbed via `allow_any_instance_of
  (Api::V1::InventoryValuesController).to
  receive(:current_steam_id).and_raise(StandardError, "boom")` in a
  `before` block, per the Example Structure convention. This exercises
  the `rescue_from` purely as "some unhandled `StandardError` escaped an
  action," without depending on which specific line raised it — matching
  the catch-all's actual contract (it doesn't branch on exception
  source).
- **Assertions** (wrapped in `aggregate_failures`, per convention):
  - `response` has HTTP status `:internal_server_error`.
  - `JSON.parse(response.body)["message"]` equals `"Internal error"` —
    not the stubbed exception's own message ("boom"), proving the
    handler doesn't leak exception details.
  - `Rails.logger` received `.error` at least once (set up via `allow
    (Rails.logger).to receive(:error)` before the request, asserted with
    `have_received(:error)` after) — proving the exception isn't silently
    swallowed.
- No change needed to existing passing contexts in that file or the
  other two controller specs — the catch-all must not alter any
  already-passing status/response-shape assertion (auth failures,
  `:bad_request` branches, `:too_many_requests`, empty-array branches all
  stay green).

## Implementation Steps

1. Write the new request-spec context in `inventory_values_spec.rb` first
   (TDD) — confirm it fails with the current raw/unhandled-exception
   behavior (RSpec/Rails will surface the stubbed `StandardError`
   uncaught, failing the example with an error rather than a clean
   assertion failure).
2. Add `rescue_from StandardError, with:
   :render_internal_server_error` and the private handler method to
   `application_controller.rb`.
3. Run the new spec; confirm it passes.
4. Run the full `app_fetcher` request-spec suite
   (`spec/requests/api/v1/*_spec.rb`) to confirm no existing
   status/response-shape assertion regressed — in particular, that
   `Steam::Client` failure branches (`:bad_request`) and auth failures
   (`:unauthorized`) are unaffected, since those still render directly
   from within the action/`before_action` and never reach the new
   `rescue_from`.
5. Run `srb tc` (Sorbet type check) against `app_fetcher` — the file is
   `# typed: strict`, so the new method needs an explicit `sig`.

## Verification

- `bundle exec rspec spec/requests/api/v1/` (app_fetcher) — full green,
  including the new context.
- `srb tc` in `app_fetcher` — no new type errors.
- `bin/rubocop` (or whatever the project's configured linter invocation
  is) on the modified controller/spec files.
- Manual spot-check: temporarily point `app_fetcher`'s DB config at an
  unreachable host and hit any `Api::V1::` endpoint with a valid bridge
  token to confirm a real `PG::ConnectionBad`/similar is caught and
  rendered as `{ message: "Internal error" }` / 500 — optional, since the
  stubbed request spec already exercises the same code path, but useful
  as a one-time sanity check given there's no error-tracking gem to catch
  a mistake in production.

## Risks

- **Over-broad catch:** `rescue_from StandardError` is the top of nearly
  the entire Ruby exception hierarchy used in practice. If a future
  action-specific `rescue`/explicit branch is removed or a new action is
  added without one, failures that should get a specific, meaningful
  status code will instead silently fall through to a generic 500. This
  is the standard tradeoff of any catch-all and is accepted here per the
  user's explicit decision to scope this to "unexpected" errors only.
- **Stubbing `current_steam_id` to raise** is a test-only simulated
  failure, not a naturally-occurring one (unlike the JWT tests, which
  trigger their `rescue` branch with genuinely malformed/expired tokens).
  This is unavoidable given there is no live trigger for an unhandled
  infra-level error today. An earlier version of this plan stubbed
  `InventoryValueLog.where` instead — rejected during `styleguides-check`
  because it's a literal ActiveRecord/database call, and
  `rspec-conventions.md` prohibits stubbing the database "at any level
  ... always" with no carve-out for this scenario. Stubbing
  `current_steam_id` (an `ApplicationController` method, not a model/DB
  call) avoids that conflict entirely rather than requiring a styleguide
  exception.
- **Styleguide tension:** `internal-api-controllers.md`'s existing "don't
  add a defensive rescue/branch for something that can't fail" rule reads
  as potentially in conflict with adding any new rescue at all. This plan
  takes the position that an infra-level catch-all (scoped to exceptions,
  not business-logic branches) is a different category from a
  speculative per-action branch — but this distinction needs to be made
  explicit in the styleguide itself during `styleguides-check`, not
  silently assumed.

## Assumptions

- "Internal error" (exact string) is an acceptable generic message body;
  no existing convention dictates specific wording for a 500 (the
  existing styleguide only documents `:unauthorized` and `:bad_request`
  message shapes). `styleguides-check` or the user may prefer different
  wording.
- `Rails.logger.error` output reaching stdout/the configured log
  destination in production (per `config/environments/production.rb`'s
  `ActiveSupport::TaggedLogging.logger(STDOUT)`) is sufficient
  observability for this change, per the user's explicit "pока только
  логи" decision.

## Completion Criteria

- `rescue_from StandardError` added to `ApplicationController`, rendering
  `{ message: "Internal error" }` / `:internal_server_error` and logging
  via `Rails.logger.error`.
- New request-spec context passes; full `app_fetcher` request-spec suite
  and `srb tc` stay green.
- No `rescue_from ActiveRecord::RecordNotFound` or error-tracking gem
  added.
- Plan reviewed against styleguides in `styleguides-check` before
  implementation.

---

# Implementation Summary

## Implemented

- `app_fetcher/app/controllers/application_controller.rb`: added
  `rescue_from StandardError, with: :render_internal_server_error` and a
  private `sig`'d `render_internal_server_error(exception)` method that
  logs the exception (class, message, backtrace) via `Rails.logger.error`
  and renders `{ message: "Internal error" }` with
  `status: :internal_server_error`. Exactly as specced — no other files
  touched besides the test.

## Tests

- `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb`: new
  context "when an unhandled error escapes the action" — stubs
  `current_steam_id` via `allow_any_instance_of
  (Api::V1::InventoryValuesController)` to raise a generic
  `StandardError`, asserts `:internal_server_error`, the generic
  (non-leaking) `"Internal error"` body, and that `Rails.logger.error`
  was called.
- TDD followed: confirmed RED first (test failed with the raw
  `StandardError: boom` escaping the action, matching today's
  unhandled-exception behavior), then GREEN after adding `rescue_from`.

Commands executed:

- `docker compose exec app_fetcher bundle exec rspec spec/requests/api/v1/inventory_values_spec.rb -e "unhandled error"` — RED, then GREEN after the implementation step.
- `docker compose exec app_fetcher bundle exec rspec spec/requests/api/v1/` — full request-spec suite.
- `docker compose exec app_fetcher bundle exec rspec` — full app_fetcher suite.
- `docker compose exec app_fetcher bin/rubocop app/controllers/application_controller.rb spec/requests/api/v1/inventory_values_spec.rb`
- `docker compose exec app_fetcher bundle exec srb tc`
- Baseline comparison (`git stash` the two changed files, re-run) for both the pre-existing spec failure and `srb tc`'s error count, to confirm neither was introduced by this change.

## Verification

- New spec: **1 example, 0 failures** (after GREEN).
- `spec/requests/api/v1/`: **47 examples, 0 failures**.
- Full app_fetcher suite: **128 examples, 1 failure** —
  `spec/caching/user_inventory_cache_spec.rb:18` ("writes them to the
  cache"), a cache-key-version mismatch unrelated to this change.
  Confirmed pre-existing: reproduces identically with this change's two
  files stashed out. Not touched — out of scope for this plan.
- `bin/rubocop` on both changed files: **no offenses**.
- `srb tc`: **97 errors**, identical count to the pre-change baseline
  (confirmed via stash-and-rerun); the only errors touching
  `application_controller.rb` are pre-existing "Unable to resolve
  constant `JWT`" ones at the (now shifted-by-one) `JWT.decode`/`rescue
  JWT::...` lines — not the new method. No new type errors introduced.

## Deviations

None from the finalized plan. (The plan's own history already records
one deviation resolved earlier, during `create-dev-plan`/
`styleguides-check`: the test stubs `current_steam_id` instead of
`InventoryValueLog.where`, to avoid conflicting with
`rspec-conventions.md`'s "never stub the database" rule — see Risks
above.)

## Remaining Issues

- Pre-existing, unrelated: `spec/caching/user_inventory_cache_spec.rb`'s
  cache-key-version failure and the 97 `srb tc` errors — both predate
  this change and are out of scope here.
- Per Scope, intentionally not done as part of this change: no
  `rescue_from ActiveRecord::RecordNotFound`, no error-tracking gem
  (Sentry/Rollbar/etc).
