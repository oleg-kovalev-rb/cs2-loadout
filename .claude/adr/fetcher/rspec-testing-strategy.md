# RSpec Testing Strategy: Layer-to-Spec-Level Mapping

## Status

Accepted

## Context

Both `app_fetcher` and `app_core` use RSpec as their only hand-written
testing framework. (`app_core`'s Gemfile also pins `minitest`, but only
as a compatibility dependency for Rails 7.2's test runner — no
`app_core/test/` directory exists, and nothing is written against
minitest directly.)

What exists today is thin and inconsistent in "level":

- `app_fetcher` has exactly two specs, both `type: :request`
  (`spec/requests/api/v1/inventories_spec.rb`,
  `price_histories_spec.rb`), exercising controllers end-to-end
  (including real `WebMock`-stubbed Steam calls). Nothing tests
  `Steam::ItemParser`, `Steam::PriceLogBuilder`, `PriceUpdateWorker`,
  `ItemsListUpdateWorker`, or `PriceScheduler` directly — this exact gap
  is what's currently blocking `.claude/plans/price-update-pipeline-test-coverage.md`.
- `app_core` has one `type: :controller` spec with `render_views`
  (`spec/controllers/dashboards_controller_spec.rb`) and one plain unit
  spec for a `lib/` class (`spec/lib/steam/bridge_token_spec.rb`). No
  request specs and no system/feature specs exist, despite `capybara`
  already sitting in the Gemfile's `test` group, unused. `type:
  :controller` is a single-example precedent, not a deliberate,
  independently-confirmed choice — see Alternatives Considered for why
  it isn't extended into the standard going forward.

Nothing in the repo states, for a given kind of class (parser, builder,
worker/scheduler, model, controller, action, plain `lib/` class,
multi-step browser flow), which RSpec level it should get, what's
mocked vs. exercised for real, or when a heavier boundary/browser-level
spec is actually warranted instead of a narrow unit spec. Without that,
every new spec file re-decides this from scratch, and — concretely — the
price-update pipeline test-coverage work can't proceed consistently.

## Decision

Define a three-level test structure, mapped onto each app's actual
class kinds, plus one explicit rule for background jobs that don't fit
cleanly into either level:

1. **Unit spec** — the default level for any class that is not itself
   an HTTP entry point or a multi-step user journey: parsers, builders,
   DTOs/response objects, API clients, Sidekiq workers/schedulers,
   models, actions, and plain `lib/` classes. One `RSpec.describe
   <Class>` per class, no `type:` metadata, file path mirroring the
   class's `app/`/`lib/` path under `spec/`.

2. **Request spec** (`type: :request`) — the HTTP-entry-point boundary,
   for every controller in both apps: `app_fetcher`'s JSON API
   controllers (already the only pattern in use there) and `app_core`'s
   session/HTML-rendering controllers alike. A request spec renders
   views and runs the full Rack middleware/session stack by default,
   with no extra setup — strictly closer to production behavior than a
   `type: :controller` spec, which tests the controller in isolation and
   needs an explicit `render_views` call to render anything. This level
   asserts the boundary contract (auth, params, status codes,
   response/render shape) plus one happy-path flow — not exhaustive
   branch coverage of business logic, which belongs at the unit level.
   `app_core`'s one existing spec
   (`spec/controllers/dashboards_controller_spec.rb`) predates this
   decision and uses `type: :controller` — see Alternatives Considered
   for why that pattern isn't extended going forward.

3. **System/feature spec** (`type: :system`, Capybara) — reserved for
   the few journeys that genuinely cannot be observed without a
   browser: an external redirect chain (Steam OpenID login), or
   JS-driven UI state (the React dashboard island, Turbo/Stimulus
   wiring). None exist yet; this decision is what the first one should
   follow.

4. **Background jobs are a cross-cutting special case, not cleanly
   "unit" or "integration."** A Sidekiq worker/scheduler's own
   orchestration logic is tested at the unit level, using
   `Sidekiq::Testing.fake!` to assert `.perform_async` enqueue behavior
   without needing a live Sidekiq-backed Redis connection. But when a
   job's own documented responsibility is writing directly to a backing
   service — not through Sidekiq's queue, but as its actual output (e.g.
   `PriceUpdateWorker` writing to the `prices_stream` Redis Stream via
   `STREAM_REDIS_POOL`) — that spec uses a **real** connection and
   asserts against what was actually written. Mocking that specific call
   away would prove the code called a method, not that the integration
   works, which defeats the reason a Redis service is being added to CI
   in the first place.

5. **Test data is built with FactoryBot, not Rails fixtures.** New specs
   at any level construct their data via `FactoryBot` factories
   (`spec/factories/`), not by adding rows to `spec/fixtures/*.yml`.
   Factories express a scenario (a stale item, a price log exactly 25h
   old) inline at the point of use, with traits/sequences, instead of a
   committed YAML row a reader has to cross-reference. Existing fixture
   files (`items.yml`, `price_logs.yml`, `users.yml`) stay loaded for
   already-existing specs during a migration window — this decision
   governs new test data, it doesn't retroactively rewrite every spec
   that predates it (see Alternatives Considered and
   `.claude/styleguides/fix_me.md`).

6. **Request specs stub the Steam API via VCR cassettes; unit specs keep
   using `WebMock` directly.** A request spec (the HTTP-boundary level)
   uses a recorded VCR cassette instead of a hand-written
   `stub_request(...).to_return(...)` body, so the response shape
   asserted against is one Steam actually produced, not a hand-typed
   approximation that can silently drift from reality. A unit spec that
   needs to simulate a *specific* response shape a real cassette can't
   easily capture on demand — an empty/`success: 0` body, a `429`
   rate-limit, a malformed field — keeps using `WebMock`'s
   `stub_request` directly, since precise, synthetic control over the
   response is the point of that test. VCR itself hooks into `WebMock`
   as its transport-level interceptor (`c.hook_into :webmock`), so
   `WebMock` isn't replaced, it's layered under VCR at the request
   level and used directly at the unit level.

7. **Pack multiple expectations about the same scenario into one
   example, wrapped in an explicit `aggregate_failures do ... end`
   block, not the `it "...", :aggregate_failures do` metadata-tag
   form.** Every `it` pays real per-example overhead — transactional
   fixture/factory setup, a full Rack dispatch for a request spec, a
   browser round-trip for a system spec. Splitting one logical check
   into several single-expectation `it` blocks multiplies that overhead
   for no isolation benefit, since they're all asserting on the same
   call/state, not exercising independent scenarios. The explicit block
   form is required over the tag form because the tag aggregates
   failures across the *entire* example body — an unexpected exception
   raised during arrange/act gets folded into the same failure report as
   the assertions, muddying which part of the example actually broke.
   The block form keeps that boundary explicit: it wraps only the
   `expect` calls, not the arrange/act code that precedes them.

8. **Structure a stateful spec as arrange (`let`/`before`) → act (a
   named `subject`) → assert.** A `create(:item, ...)` or
   `stub_request(...)` call buried inline in an example body hides what
   the example depends on and can't be reused by a sibling example in
   the same `context`; naming it via `let`/`let!`/`before` separates
   "what's arranged" from "what's asserted" and lets every example in a
   `context` share the same setup. Naming the action under test via a
   `subject` avoids repeating `described_class.new.perform(...)` in
   every example body. This is deliberately not applied to pure-function
   specs with no persisted data or stub (e.g. `Steam::ItemParser`) —
   forcing the structure onto a one-line call adds indirection without
   buying anything.

## Alternatives Considered

### Alternative: Mock every external dependency (Redis, Steam API) in every spec, always

The classic strict-unit-isolation rule — never touch a real backing
service, only assert that a call happened.

Rejected because:

- For `PriceUpdateWorker`, the Redis Stream write is not incidental
  plumbing, it's the documented feature (see
  `.claude/adr/fetcher/price-updates-via-redis-stream.md`). A spec that
  mocks `redis.xadd` can't catch a schema drift, a serialization bug, or
  a connection-pool misconfiguration — exactly the class of regression
  CI's new Redis service exists to catch.

### Alternative: Boundary-only testing — request/system specs exercise everything, no direct unit specs

Rely on request specs (already `app_fetcher`'s only existing pattern) to
exercise parsers/builders/workers indirectly; skip direct specs for
them.

Rejected because:

- This is close to today's status quo, and it's exactly what has left
  five classes with zero direct coverage. Their edge cases (empty Steam
  responses, rate-limit errors, both `change_24h_cents` branches,
  scheduler filtering) aren't reachable/assertable through one or two
  request specs without turning each into a de facto integration test
  for several classes at once.
- `PriceScheduler` specifically isn't reachable through any HTTP
  endpoint at all — it's cron-triggered — so a boundary-only strategy
  has no way to test it whatsoever.

### Alternative: Keep Rails fixtures as the only test-data mechanism

Both apps already use fixtures exclusively (`items.yml`, `price_logs.yml`,
`users.yml`, `config.global_fixtures = :all`); an earlier draft of this
ADR kept them for exactly that reason — no new dependency, no second
mechanism to learn.

Rejected in favor of FactoryBot because:

- Fixtures are static and global: expressing a new edge case (an item
  updated 61 minutes ago vs. 59, a price log exactly 24h old vs. 23h)
  means adding another named row to a shared YAML file that every other
  spec in the suite also loads, whether it needs that row or not. A
  factory expresses the same scenario inline, at the point of use
  (`create(:item, updated_at: 61.minutes.ago)`), which is both easier to
  read in context and doesn't grow a shared file indefinitely as
  coverage expands.
- Sequences and traits make it straightforward to generate many
  structurally-similar-but-distinct records (e.g. `PriceScheduler`'s
  "multiple qualifying items" scenario) without hand-naming a fixture
  row per instance.
- The "no new dependency" argument was the strongest reason to keep
  fixtures, and it's a one-time cost (`factory_bot_rails` in both
  Gemfiles' `test` group) against an ongoing readability/maintenance
  cost that compounds as more specs are written.

### Alternative: Hand-written `WebMock` stubs for request specs too (status quo)

Keep using `stub_request(:get, ...).to_return(status:, body:, ...)` with
a manually-typed JSON body at the request level, as
`inventories_spec.rb`/`price_histories_spec.rb` do today, instead of
introducing VCR cassettes.

Rejected because:

- A hand-typed stub body is an assumption about Steam's response shape,
  frozen at the moment someone wrote it. If Steam adds, renames, or
  changes the type of a field, the stub keeps "passing" — it only
  reflects what the author believed the shape to be, not what the API
  actually returns. A VCR cassette is recorded from a real response, so
  the fixture data is authentic by construction; re-recording it is also
  the mechanism for deliberately checking whether Steam's shape has
  changed.
- This alternative is not rejected for unit specs — see Decision point
  6. Hand-written `WebMock` stubs remain the right tool when the test's
  entire point is a specific, synthetic response shape (a nil field, a
  429, a malformed body) that isn't practical to obtain via a recorded
  cassette on demand.

### Alternative: Keep `type: :controller` as `app_core`'s standard for HTML/session controllers

Extend the one existing precedent (`dashboards_controller_spec.rb`)
instead of switching to request specs, on the reasoning that it's
already an established pattern in this codebase.

Rejected because:

- A single spec file is a weak precedent to enshrine, not a second
  independent confirmation of a deliberate choice — nothing in the repo
  indicates `type: :controller` was chosen over `type: :request` for a
  reason specific to `DashboardsController`, as opposed to being the
  RSpec/Rails generator default at the time it was written.
- Controller specs are widely discouraged upstream: they exercise the
  controller in isolation, bypassing the Rack middleware/session stack a
  real request goes through, and only render a view if `render_views` is
  explicitly added — a request spec gets both correctly and for free.
  `app_core`'s controllers are exactly the session/auth-sensitive kind
  (`DashboardsController`, `SessionsController`) where exercising the
  real middleware/session stack matters most.
- Keeping it would mean writing new specs against a pattern this ADR
  simultaneously documents as worse than the alternative sitting right
  next to it in the same test suite (`app_fetcher`'s request specs) —
  worth the (small) cost of treating the existing file as a deviation to
  fix rather than a convention to extend.

## Consequences

### Positive

- Every class kind in either app now has an unambiguous "what level,
  what's mocked" answer before a spec is written, instead of each
  contributor improvising per PR.
- The `WebMock`/`Sidekiq::Testing`/real-Redis conventions are decided
  once, centrally, rather than re-litigated for every new worker or
  controller.
- The convention already scales to `app_core`'s still-mostly-untested
  `app/actions/`, `app/jobs/`, and the not-yet-written system specs
  without a second design pass.
- FactoryBot's traits/sequences and VCR's recorded-not-guessed response
  bodies make new edge-case coverage both easier to write and higher
  fidelity than the fixtures-plus-hand-typed-stub status quo.

### Negative

- Specs that touch a real Redis (per the job special-case rule) require
  a running Redis in every environment that runs the suite, not just
  CI — local dev now needs `docker compose up redis` (or an equivalent
  local Redis) to run `app_fetcher`'s full suite, where it previously
  didn't need one at all.
- `app_core/spec/controllers/dashboards_controller_spec.rb` is left as a
  known, logged deviation (see `.claude/styleguides/fix_me.md`) rather
  than migrated as part of this decision — this ADR settles the
  convention going forward, it doesn't retroactively fix every file that
  predates it. The same applies to existing fixtures and
  `inventories_spec.rb`/`price_histories_spec.rb`'s hand-written
  `WebMock` stubs — not migrated to FactoryBot/VCR as part of this ADR.
- Two new gems (`factory_bot_rails`, `vcr`) become required in both
  apps' `test` group before this decision can actually be exercised —
  not yet added to either Gemfile (see Implementation Constraints).
- VCR cassettes are new committed artifacts (`spec/cassettes/`) that
  need a re-recording discipline; without one they silently ossify into
  exactly the "frozen at time of writing" problem this decision rejected
  hand-written stubs for.

### Risks

- "Use a real backing service when it's the actual integration point"
  is a judgment call per class, not a mechanical rule — a future
  contributor could reasonably disagree on whether a given dependency
  counts as "the integration point" or "an incidental collaborator
  worth mocking." The companion styleguide's layer table is the
  concrete tie-breaker; extend that table for a new case rather than
  reinterpreting the principle ad hoc.
- No system/feature spec exists yet to validate that the `type: :system`
  / Capybara setup actually works end-to-end in `app_core` (an untested
  convention, not just an undocumented one) — treat the first system
  spec written against this decision as validation of it, not just
  application of it.
- A VCR cassette recorded today and never refreshed can drift from
  Steam's real current behavior just as silently as a hand-written stub
  would — VCR only solves "the shape was accurate once," not "the shape
  stays accurate forever." There's no automated re-recording trigger in
  this decision; re-recording is a manual, deliberate act.
- Steam's endpoints used today (`/market/priceoverview/`,
  `/inventory/...`) are unauthenticated/public, so cassette recordings
  carry no secrets currently — but VCR must still be configured to
  filter sensitive request/response data (headers, query params, tokens)
  from day one, so that an authenticated endpoint added later doesn't
  get its first cassette committed unfiltered by oversight.

## Implementation Constraints

- Spec directory layout mirrors `app/`/`lib/` structure 1:1 under
  `spec/` for unit specs (already true for
  `spec/lib/steam/bridge_token_spec.rb`); request specs live under
  `spec/requests/`, mirroring the controller's namespace; system specs
  (once they exist) live under `spec/system/`.
- `WebMock` always stubs the real outbound host
  (`stub_request(:get, %r{steamcommunity\.com/...})`) at the unit level,
  and remains VCR's transport-level hook at the request level — never
  stub `Steam::Client`/`Steam::Authenticator` directly, at any level.
- `Sidekiq::Testing.fake!` is configured once, globally, in each app's
  `rails_helper.rb` — not per-spec.
- A class writing to Redis directly as its own documented responsibility
  (not via Sidekiq's queue) gets a real Redis connection in its spec; a
  class that only enqueues work through Sidekiq does not need a real
  Sidekiq-backed Redis connection for that — these are two distinct
  Redis usages and must not be collapsed into a single "mock Redis" or
  "always use real Redis" blanket rule.
- Add `factory_bot_rails` and `vcr` to both apps' Gemfile `test` group —
  a prerequisite for this decision, not yet done. Factories live under
  `spec/factories/`, one file per model, named after the table
  (`spec/factories/items.rb` → `factory :item`). Cassettes live under
  `spec/cassettes/`, keyed automatically off the example's description
  via `:vcr` metadata (`VCR.configure { |c|
  c.configure_rspec_metadata! }`) rather than a manually-named
  `VCR.use_cassette` block.
- VCR record mode: `:once` locally (record if the cassette doesn't
  exist yet, replay otherwise), `:none` in CI (never attempt a live
  call — a missing cassette must fail loudly, not silently hit the real
  Steam API from a CI runner). Configure
  `c.allow_http_connections_when_no_cassette = false` so an unrecorded
  request fails instead of silently going out over the network.
- Existing fixtures and `inventories_spec.rb`/`price_histories_spec.rb`'s
  hand-written `WebMock` stubs are not retrofitted by this decision;
  they're logged in `.claude/styleguides/fix_me.md` as pre-existing and
  migrated opportunistically when those files are next touched.

## Related

- `.claude/styleguides/rspec-conventions.md` — the "how" companion to
  this "why"
- `.claude/adr/fetcher/price-updates-via-redis-stream.md` — why the
  Redis Stream integration exists and is worth testing for real
- `.claude/plans/price-update-pipeline-test-coverage.md` — the blocked
  plan that surfaced this gap
- `.claude/styleguides/fix_me.md` — where
  `dashboards_controller_spec.rb`'s `type: :controller` usage is logged
  as a deviation from this decision
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `price_histories_spec.rb`
- `app_core/spec/controllers/dashboards_controller_spec.rb`,
  `app_core/spec/lib/steam/bridge_token_spec.rb`
