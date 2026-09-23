# RSpec Conventions

## Purpose

For any class in `app_fetcher` or `app_core`, answer two questions before
a spec gets written: which RSpec level does it belong at (unit / request
/ system), and what gets stubbed vs. exercised for real (see Stubbing vs
Exercising). This is the single place that decision gets made, instead
of being re-derived — or guessed differently — per PR.

This governs testing *mechanics* that apply across layers (levels,
fixtures, stubbing, spec layout). It does not restate what an individual
domain styleguide's own "Rules" section says about the code under test
(e.g. `.claude/styleguides/fetcher/background-jobs.md`'s job-specific
rules on retries/queues/transactions) — those still apply on top of this.

## When to Use

Applies to every new or modified RSpec spec file in either app. Doesn't
cover Ruby/Sorbet style inside a spec beyond the one sigil exception
below (see `ruby-sorbet.md` + `rubocop-rails-omakase` for that), and
doesn't replace a domain styleguide's own testing expectations where one
exists.

## Structure

### The three levels

- **Unit spec** — one `RSpec.describe <Class>` per class. No `type:`
  metadata (type inference from file location is off in both apps'
  `rails_helper.rb`). File path mirrors the class's `app/`/`lib/` path
  under `spec/` (`app/parsers/steam/item_parser.rb` →
  `spec/parsers/steam/item_parser_spec.rb`;
  `lib/steam/bridge_token.rb` → `spec/lib/steam/bridge_token_spec.rb`).
  This is the default level — reach for it unless the class *is* an HTTP
  entry point or a multi-step browser journey.
- **Request spec** — `type: :request`, under `spec/requests/`, mirroring
  the controller's namespace (`Api::V1::InventoriesController` →
  `spec/requests/api/v1/inventories_spec.rb`). The only level used for
  every controller in either app — `app_fetcher`'s JSON API controllers
  and `app_core`'s HTML/session controllers alike. A request spec
  renders views and runs the full Rack middleware/session stack by
  default, with no extra setup (`get "/dashboard"; expect(response.body)
  to match(...)` just works) — it's strictly closer to production
  behavior than a `type: :controller` spec, which tests the controller
  in isolation and needs an explicit `render_views` call to render
  anything at all. `type: :controller` is not used for new specs in
  either app (see Rules and the Related ADR). A request spec that talks
  to the Steam API uses a **VCR cassette**, not a hand-written `WebMock`
  stub — see Stubbing vs Exercising.
- **System spec** — `type: :system`, Capybara-driven, under
  `spec/system/`. Reserved for a genuine multi-step browser journey a
  request spec can't observe on its own — a redirect chain through an
  external provider (Steam OpenID login), or JS-driven UI state (the
  React dashboard island, Turbo/Stimulus wiring). Doesn't exist yet in
  either app; this is where the first one goes.

### Layer → level mapping

| Layer / class kind | Level | Example |
|---|---|---|
| Parser (`app/parsers/**`) | Unit | `Steam::ItemParser` |
| Builder (`app/builders/**`) | Unit | `Steam::PriceLogBuilder` |
| DTO / response object (`lib/steam/response/**`) | Unit | `Steam::Response::Data::ItemPriceData` |
| API client (`lib/steam/client.rb`, `lib/steam/authenticator.rb`) | Unit, via WebMock-stubbed HTTP | `Steam::Client` |
| Sidekiq worker (`app/workers/**`) | Unit; real backing service only for the part of its job that *is* talking to that service | `PriceUpdateWorker` |
| Sidekiq scheduler (`app/schedulers/**`) | Unit, `Sidekiq::Testing.fake!` to assert enqueue | `PriceScheduler` |
| Model (`app/models/**`) | Unit | `Item`, `PriceLog` |
| Action (`app/actions/**`, `app_core`) | Unit | — |
| Plain `lib/` class | Unit | `Steam::BridgeToken` |
| JSON API controller (`app_fetcher`) | Request (`type: :request`) | `Api::V1::InventoriesController` |
| HTML/session controller (`app_core`) | Request (`type: :request`; views render by default) | `DashboardsController` |
| Multi-step browser journey | System (`type: :system`) | Steam OpenID login round-trip (none written yet) |

## Interface

Every spec file: `require "rails_helper"`, then `RSpec.describe`. No
Sorbet sigil comment (see Rules). Shared setup that more than one spec
file needs lives in `spec/support/*.rb` as a plain module, included via
`RSpec.configure { config.include Module, type: ... }` — see
`bridge_token_helper.rb` for the shape.

## Responsibilities

- **Unit level** owns exhaustive coverage of a class's own branches:
  empty/nil input, error/failure paths, every distinct business-logic
  branch. This is where edge cases belong — not bolted onto a request
  spec to reach them indirectly.
- **Request level** owns the boundary contract: auth, params, status
  codes, response/render shape, plus one representative happy-path flow.
  It is not responsible for re-proving business logic already covered at
  the unit level.
- **System level** owns only the slice of a flow that a request spec
  literally cannot observe (an external redirect chain, JS-driven UI
  state) — never used as a substitute for a request spec.

## Dependencies

- `WebMock` stubs the real outbound host
  (`stub_request(:get, %r{steamcommunity\.com/...})`) directly at the
  **unit** level, whenever a test needs a specific, synthetic response
  shape (nil field, `429`, malformed body). Never stub the client class
  itself (`Steam::Client`, `Steam::Authenticator`) — that tests against
  an invented contract instead of the real one.
- `VCR` cassettes stub the Steam API at the **request** level, recorded
  from a real response and replayed on later runs. `VCR` hooks into
  `WebMock` as its transport-level interceptor, so `WebMock` isn't
  bypassed, it's layered underneath.
- `Sidekiq::Testing.fake!` (configured once, globally, in
  `rails_helper.rb`) is used for anything that only *enqueues* work via
  `.perform_async` — no real Sidekiq-backed Redis connection needed to
  assert a job was queued.
- A class that writes to Redis directly as its own documented
  responsibility (not via Sidekiq's queue — e.g. `STREAM_REDIS_POOL`)
  uses the real connection in its spec and asserts against what was
  actually written.
- `FactoryBot` factories (`spec/factories/`) are the standard test-data
  mechanism. Existing Rails fixtures (`spec/fixtures/*.yml`) stay loaded
  for already-existing specs during a migration window — see Rules.

## Stubbing vs Exercising

A quick-reference for "is this thing real or stubbed in a spec," at any
level:

| What | Stub it? | How |
|---|---|---|
| External HTTP — unit spec, specific/synthetic shape needed | Always stub | `WebMock` `stub_request` against the real host — never stub `Steam::Client`/`Steam::Authenticator` themselves |
| External HTTP — request spec, real API boundary | Always stub | A recorded VCR cassette (`spec/cassettes/`), not a hand-written stub body — see the Related ADR |
| The database (Postgres) | Never stub | Real records (via FactoryBot or existing fixtures), real queries, rolled back per-example via `use_transactional_fixtures` — true at every level, including request specs |
| Sidekiq's own job queue (`.perform_async`) | Stub | `Sidekiq::Testing.fake!` — assert on `<Worker>.jobs`, no real Sidekiq-backed Redis connection |
| A backing service that *is* the class's own responsibility (e.g. `STREAM_REDIS_POOL`/`prices_stream`) | Never stub | Real connection; assert against what was actually written |
| Plain in-memory objects with no I/O (DTOs, value objects, parser/builder inputs) | Never stub | Construct real instances directly — there's nothing to fake |

The rule of thumb behind the table: stub exactly the thing that crosses
a process/network boundary *and* isn't the subject of the spec. Never
stub the database, and never stub the one external call or write a spec
exists to verify — see MUST NOT below and the Related ADR.

## Example Granularity

Every `it` pays real per-example overhead — transactional fixture/factory
setup, a full Rack dispatch for a request spec, a browser round-trip for
a system spec. Splitting one logical check into several single-expectation
`it` blocks multiplies that overhead for no isolation benefit, since
they're all asserting on the same call/state, not exercising independent
scenarios. Reserve a new `it` for a genuinely different scenario or code
branch (see the Layer → level mapping and Responsibilities above);
different expectations about the *same* scenario belong in the *same*
example.

When an example ends up with more than 3 expectations, wrap those
expectations in an explicit `aggregate_failures do ... end` block — not
the `it "...", :aggregate_failures do` metadata-tag form. The block
wraps only the `expect` calls, not the arrange/act code (`let`
dereferences, the `subject` call, deriving a value to assert against)
that precedes them — see Example Structure below for that split. The
tag form aggregates failures across the *entire* example body, which
means an unexpected exception raised during setup or the action gets
folded into the same failure report as the assertions, muddying which
part of the example actually broke; the block form keeps that boundary
explicit. A failing run still reports every failing expectation inside
the block at once, instead of stopping at the first `expect` and forcing
a fix-rerun-fix cycle to find the rest.

## Example Structure

Once a spec creates persisted test data, stubs an external call, and/or
exercises a stateful action (the shape of most worker/scheduler specs),
structure it as arrange (`let`/`before`) → act (a named `subject`) →
assert, instead of building everything inline in the example body:

- **Test data via `let`/`let!`, not inline `create`/`create_list`.** A
  `create(:item, ...)` call buried in the middle of an example body
  hides what data the example depends on, and can't be reused by a
  sibling example in the same `context`. Name it
  (`let(:item) { create(:item, ...) }`) so every example in that
  `context` shares the same setup and a reader sees the test's fixtures
  listed alongside its description, not interleaved with assertions.
  Use `let!` instead of `let` when nothing in the example references
  the record before the action runs (e.g. `PriceScheduler`'s spec,
  where the scheduler queries `Item` directly rather than being handed
  an id) — plain `let` is lazy and won't exist in the DB yet when the
  action needs it to. When the record's own value *is* referenced while
  building the action (e.g. `item.id` passed into `perform`), plain
  `let` is enough — referencing it forces creation before the action
  runs.
- **Stubs via `before`, not inline `stub_request`.** Same reasoning: a
  `WebMock` `stub_request(...).to_return(...)` call is setup, not the
  behavior under test. Putting it in `before` separates "what's
  arranged" from "what's asserted," and lets every example in that
  `context` share one stub instead of repeating it.
- **The action under test via a named `subject`.** Give the call that
  exercises the class a name (`subject(:perform) {
  described_class.new.perform(item.id) }`) instead of repeating
  `described_class.new.perform(...)` in every example body. Examples
  then read as "arrange → call the named `subject` → assert."

```ruby
RSpec.describe PriceUpdateWorker do
  subject(:perform) { described_class.new.perform(item_id) }

  context "when the Steam API call succeeds" do
    let(:item_id) { item.id }
    let(:item) { create(:item, :without_price) }

    before do
      stub_request(:get, %r{steamcommunity\.com/market/priceoverview/})
        .to_return(status: 200, body: { success: true, lowest_price: "$38.45" }.to_json)
    end

    it "creates a price log" do
      perform
      item.reload

      aggregate_failures do
        expect(item.price_logs.count).to eq(1)
        # ...
      end
    end
  end
end
```

This doesn't replace the Example Granularity rule — an example with more
than 3 expectations still gets its assertions wrapped in
`aggregate_failures`, regardless of how tidy its arrange/act setup is.
Note where the block starts: after `perform` and `item.reload` (act),
not around them — see Example Granularity for why the tag form isn't
used.

Not every spec needs this: a pure-function unit spec with no persisted
data and no stub (e.g. `Steam::ItemParser`, `Steam::PriceLogBuilder`)
has nothing to extract — forcing `let`/`before`/`subject` onto a
one-line `described_class.parse(name)` call adds indirection without
buying anything. Reach for this structure once a spec has the setup to
justify it, not as a blanket rule for every spec file.

## Rules

### MUST

- Mirror the source file's path for unit and request specs
  (`app/X/y.rb` → `spec/X/y_spec.rb`, `lib/X/y.rb` → `spec/X/y_spec.rb`).
- Set explicit `type:` metadata on every request/system spec
  (`type: :request` / `:system`); no `type:` on unit specs. Type
  inference from file location is off in both apps — don't rely on it.
- No Sorbet sigil comment on spec files. `ruby-sorbet.md`'s "every
  hand-written file gets `# typed: strict`" rule doesn't apply here —
  its own "When to Use" section enumerates production code kinds
  (models, controllers, jobs, parsers/builders, `lib/` classes, actions)
  and doesn't include RSpec example files.
- At the unit level, stub the real outbound host via `WebMock`, never
  the internal client class, for any spec that would otherwise make a
  real external HTTP call.
- At the request level, use a VCR cassette for any spec that exercises
  a Steam API call, via `:vcr` metadata
  (`VCR.configure { |c| c.configure_rspec_metadata! }`) rather than a
  manually-named `VCR.use_cassette` block — the cassette name is derived
  from the example's description automatically.
- Build test data with `FactoryBot` factories (`create(:item, ...)` /
  `build(:item, ...)`), one factory file per model under
  `spec/factories/`, named after the table (`spec/factories/items.rb` →
  `factory :item`). Use traits/sequences to express a scenario inline
  rather than hand-naming a new fixture row.
- Use `Sidekiq::Testing.fake!` for any spec that triggers
  `.perform_async`; assert against `<Worker>.jobs`, not a real enqueue.
- When a class's own responsibility includes writing to Redis directly
  (not through Sidekiq), its spec uses the real connection and asserts
  the actual data written (e.g. `XRANGE` against a Stream) — don't mock
  that specific call away.
- Once an example has more than 3 expectations, wrap them in an
  explicit `aggregate_failures do ... end` block — not the
  `it "...", :aggregate_failures do` tag form (see Example Granularity).
- Once a spec creates persisted test data, extract each `create`/
  `create_list` call into a `let`/`let!` instead of inlining it in the
  example body (see Example Structure).
- Once a spec stubs an external call, extract the `stub_request` into a
  `before` block instead of inlining it in the example body (see
  Example Structure).
- Once a spec exercises a stateful action (a worker's `perform`, any
  method with side effects being asserted on), name it via a `subject`
  and call that from each example, instead of repeating the call inline
  (see Example Structure).

### SHOULD

- Prefer a unit spec over a request spec to exercise a class's edge
  cases (nil/empty/error branches); reserve request specs for scenarios
  that are genuinely about the boundary (auth, status codes,
  response/render shape).
- Reach for a system spec only when a request spec genuinely cannot
  observe the behavior (a real redirect chain, JS-driven state) — most
  `app_core` behavior doesn't need one.
- Minimize the number of `it` blocks: pack every expectation about the
  same scenario into one example instead of splitting them
  one-assertion-per-`it` (see Example Granularity). Reach for a new `it`
  because the *scenario* changed, not because you're asserting on a
  different field of the same result.

### MUST NOT

- Don't write a new `type: :controller` spec in either app. Request
  specs cover the same ground (including rendered-view assertions, with
  no `render_views` call needed) while exercising the real Rack
  middleware/session stack a controller spec bypasses — see the Related
  ADR. `app_core/spec/controllers/dashboards_controller_spec.rb`
  predates this convention and is a known deviation, not a second
  precedent to extend (see `.claude/styleguides/fix_me.md`).
- Don't mock away the one external call/write that is the actual subject
  of a spec (e.g. don't stub `STREAM_REDIS_POOL` in `PriceUpdateWorker`'s
  spec) — see Stubbing vs Exercising and the Related ADR for why that
  specifically defeats the point of testing it at all.
- Don't stub the database at any level — real records, real queries,
  transactional rollback, always (see Stubbing vs Exercising).
- Don't hand-write a `WebMock` `stub_request` body for a request spec's
  Steam API call — use a VCR cassette (unit specs are the exception; see
  Dependencies and Stubbing vs Exercising).
- Don't add a new row to `spec/fixtures/*.yml` for a new scenario — add
  a `FactoryBot` factory or trait instead. Existing fixture rows already
  referenced by other specs stay as-is until that spec is migrated (see
  `.claude/styleguides/fix_me.md`).
- Don't rely on `config.infer_spec_type_from_file_location!` — it's
  explicitly left off in both apps; state `type:` explicitly wherever it
  matters.
- Don't use the `it "...", :aggregate_failures do` metadata-tag form.
  Use an explicit `aggregate_failures do ... end` block wrapped around
  just the `expect` calls (see Example Granularity).

## Error Handling

Drive an "external call failed" scenario — at the unit level, via
`WebMock` — with a stub returning the actual failure shape Steam would
return (a `success: 0` JSON body for an empty/not-found response, an
HTTP `429`/`5xx` for a transport-level error), and let the production
error-handling code path run for real. This is exactly the kind of
synthetic, on-demand shape a VCR cassette can't easily produce, which is
why it stays a unit-level, `WebMock`-driven case even though the request
level otherwise uses cassettes (see Structure). Don't stub
`Steam::Client` to hand back a canned `Steam::Response` object directly
— that exercises an invented contract, not the one `Steam::Client`
actually produces (see
`.claude/styleguides/fetcher/steam-response-objects.md` for that
contract's shape).

## Interaction With Other Layers

```text
Unit spec (many, fast, exhaustive per-class edge cases)
    ↓ covers: parsers, builders, DTOs, clients, workers/schedulers,
      models, actions, plain lib/ classes
Request spec (few, boundary contract only)
    ↓ covers: auth, params, status/render shape, one happy path
System spec (fewest, browser-only journeys)
    ↓ covers: only what a request spec cannot observe
```

A background job (worker/scheduler) sits at the unit level for its own
orchestration logic, but a spec for one may still hit a real backing
service for the specific part of its responsibility that is a direct
integration point (see Dependencies/Rules) — it isn't purely "unit" in
the classic isolated sense, and that's intentional, not an inconsistency
to resolve away.

## Canonical Implementations

- Unit: `app_core/spec/lib/steam/bridge_token_spec.rb` (pure class, no
  Rails `type:`, no external I/O)
- Request: `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `app_fetcher/spec/requests/api/v1/price_histories_spec.rb`. `app_core`
  has no canonical request spec yet — its one existing controller spec
  (`spec/controllers/dashboards_controller_spec.rb`) predates this
  convention and uses `type: :controller`; see `fix_me.md`. The next
  `app_core` controller spec written or rewritten should be the first
  `type: :request` example.
- System: none yet — the first one should follow this guide and the
  Related ADR rather than improvise a new pattern.
- FactoryBot factory: `app_fetcher/spec/factories/items.rb`,
  `app_fetcher/spec/factories/price_logs.rb` (`factory_bot_rails` added
  to `app_fetcher`'s Gemfile `test` group). `app_core` has none yet —
  `factory_bot_rails` still needs adding to its Gemfile before its first
  factory. VCR cassette: none yet in either app — no request spec has
  needed one so far; `vcr` still needs adding to a Gemfile's `test`
  group before the first cassette (see the Related ADR's Implementation
  Constraints). `inventories_spec.rb`/`price_histories_spec.rb`
  (hand-written `WebMock` stubs) and `items.yml`/`price_logs.yml`/
  `users.yml` (fixtures) are the pre-existing, not-yet-migrated baseline
  — see `fix_me.md`.
- Example Structure (`let`/`before`/named `subject`):
  `app_fetcher/spec/workers/price_update_worker_spec.rb` — combines all
  three with an explicit `aggregate_failures` block around its
  assertions; also `items_list_update_worker_spec.rb`,
  `spec/schedulers/price_scheduler_spec.rb`.

## Related ADR

`.claude/adr/fetcher/rspec-testing-strategy.md` — why this three-level
structure was chosen over mocking every external dependency always, or
testing only at the HTTP boundary; why background jobs get an explicit
special-case rule instead of being forced into "unit" or "integration";
and why FactoryBot/VCR were chosen over fixtures/hand-written `WebMock`
stubs.
