---
status: implemented
app: fetcher
goal: Add unit-test coverage for the price-update pipeline (ItemParser, PriceLogBuilder, PriceUpdateWorker, ItemsListUpdateWorker, PriceScheduler) and enable Redis in app_fetcher's CI so Redis-dependent logic is actually exercised
created: 2026-09-19
---

# Development Plan

## Goal

Add direct unit-test coverage for the five components that make up
`app_fetcher`'s price-update pipeline — `Steam::ItemParser`,
`Steam::PriceLogBuilder`, `PriceUpdateWorker`, `ItemsListUpdateWorker`,
`PriceScheduler` — and enable the Redis service in `app_fetcher`'s GitHub
Actions `test` job (wiring `REDIS_URL`, `REDIS_URL_SIDEKIQ`,
`REDIS_URL_STREAM`) so the Sidekiq/Redis-Stream-dependent parts of that
logic run for real in CI, not just locally. Get the whole `app_fetcher`
suite green in CI end-to-end.

## Expected Behavior

**`Steam::ItemParser`**
- `.parse` splits `"<weapon> | <item> (<condition>)"` into `weapon_type`,
  `item_name`, `condition`; detects `StatTrak™`/`Souvenir` markers into
  boolean flags; strips those markers from the parsed name.
- `.parse` on a name with no `" | "` separator leaves `weapon_type: nil`
  and treats the whole (marker/condition-stripped) string as `item_name`.
- `.parse` on a name with no trailing `(...)` leaves `condition: nil`.
- `.parse_collection` maps `.parse` over every name; an empty array input
  returns an empty array (no error).

**`Steam::PriceLogBuilder`**
- `.build` with a fully-populated `ItemPriceData` DTO returns an unsaved
  `PriceLog` with correctly cents-converted `lowest_price_cents`/
  `median_price_cents` and integer `volume` (commas stripped).
- `.build` with `nil` `lowest_price`/`median_price`/`volume` (Steam
  returning a successful-but-sparse payload) returns `0` for the
  corresponding field(s), not an error.
- `.build` with empty-string price/volume fields behaves the same as
  `nil` (returns `0`).

**`PriceUpdateWorker`**
- Missing `item_id` → returns immediately; no Steam API call is made, no
  DB write, nothing published.
- Successful Steam response, item has no prior `price_log` older than 24h
  (first-ever price) → creates a `PriceLog`, updates
  `item.current_price_cents`, sets `change_24h_cents` to `0`, and
  publishes one entry to the `prices_stream` Redis Stream with the
  correct `market_hash_name`/`price_cents`/`change_24h_cents`/
  `fetched_at` fields.
- Successful Steam response, item has a `price_log` older than 24h →
  `change_24h_cents` is the difference between the new and that older
  price, both a `PriceLog` row and the `Item` row are written inside one
  transaction, and a stream entry is published.
- Unsuccessful Steam response (Steam returns a "not found"/empty
  `success: 0` payload) → no `PriceLog` is created, `Item` is left
  unchanged, nothing is published to `prices_stream`, a
  `[PriceUpdateWorker] Failed for ...` warning is logged.
- Steam API error response (rate-limited / non-200) → same "no write, no
  publish" behavior as the empty-response case.

**`ItemsListUpdateWorker`**
- Given new `market_hash_name`s, creates one `Item` per name with
  attributes from `Steam::ItemParser`.
- Given a name that already exists, the existing `Item` row is updated
  (upserted), not duplicated.
- Given an empty array, does nothing and does not raise.

**`PriceScheduler`**
- An `Item` whose `updated_at` is older than 1 hour, or whose
  `current_price_cents` is `nil`, gets a `PriceUpdateWorker` job enqueued
  for its id.
- An `Item` that was updated within the last hour and already has a
  `current_price_cents` is **not** enqueued (must remain unchanged —
  this is the scheduler's whole filtering purpose).
- Multiple qualifying items each get exactly one job enqueued.
- The scheduler itself performs no Steam API call and no direct write.

## Scope

### In Scope

- Unit specs for the five named components, covering success / empty
  (or sparse) response / API-error scenarios as applicable to each
  component's actual responsibilities (see Expected Behavior above —
  not every component has all three scenarios, since `ItemParser` and
  `PriceLogBuilder` never call the Steam API themselves).
- Minimal spec support infrastructure needed to make those specs
  possible: enabling `Sidekiq::Testing` (so `PriceScheduler`'s
  `.perform_async` fan-out is assertable without a live Sidekiq-backed
  Redis queue), and a small helper for reading/isolating the
  `prices_stream` Redis Stream around specs that hit it for real.
  These are added specifically because they're new here, not to
  reformat/wire deeper Sidekiq testing conventions than this needs.
- New `FactoryBot` factories for `Item`/`PriceLog` needed to drive the
  above scenarios (stale vs. fresh item, item with/without a prior price
  log older than 24h) — existing fixtures stay untouched (see
  Implementation Approach).
- Enabling the commented-out Redis service in
  `app_fetcher/.github/workflows/ci.yml`'s `test` job and passing
  `REDIS_URL`, `REDIS_URL_SIDEKIQ`, `REDIS_URL_STREAM` into that job's
  test-run env, matching the values already used in the root
  `docker-compose.yml`.
- Verifying the full `app_fetcher` spec suite (existing request specs +
  new unit specs) passes locally against a real Redis, and that CI is
  green end-to-end.

### Out of Scope

- Any change to production business logic in the five components — this
  is test coverage for existing, already-correct behavior. If a spec
  uncovers a genuine bug, stop and flag it rather than silently
  expanding scope to fix it.
- `Steam::Client` itself does not get its own new spec file — it
  continues to be exercised indirectly via `WebMock` stubs, same as the
  existing `inventories_spec.rb` pattern.
- Fixing the two pre-existing deviations already logged in
  `.claude/styleguides/fix_me.md` for `item_parser.rb` (unwrapped
  `Regexp#freeze` constants) and `price_scheduler.rb` (missing
  `retry:`) beyond what `styleguides-check`/`implement-plan` decides is
  in-scope-and-trivial. Not pre-emptively fixed here.
- Wiring `REDIS_URL_SIDEKIQ` into any actual Sidekiq client
  configuration in `app_fetcher`'s Ruby code — it is currently unread
  by the codebase; this plan only passes it through CI env for parity
  with `docker-compose.yml`, per the task's explicit ask, without adding
  new config to consume it.
- `app_core`'s CI workflow, which has an identical commented-out Redis
  block — not requested, not touched.
- Deep testing of `Prop` rate-limiting itself (it's a no-op in the test
  env's `:null_store` cache anyway) — rate-limit/error behavior is
  covered at the `Steam::Client` response level via WebMock-stubbed
  status codes, not by exercising `Prop` for real.

## Implementation Approach

- Follow `.claude/styleguides/rspec-conventions.md`: build test data with
  `FactoryBot` factories (`spec/factories/items.rb`,
  `spec/factories/price_logs.rb`), not new fixture rows — the existing
  `items.yml`/`price_logs.yml` fixtures stay untouched by this plan
  (`redline`/`redline_recent` remain available to the two existing
  request specs, unaffected). `WebMock`'s `stub_request(...)
  .to_return(...)` for simulating Steam responses (see
  `inventories_spec.rb`) — all five new specs are unit-level, so this
  stays direct `WebMock`, not a VCR cassette (VCR is scoped to request
  specs only, none of which this plan adds). Plain `RSpec.describe
  ClassName do` with no `type:` metadata (type inference is off), no
  Sorbet sigil on spec files, `:aggregate_failures` tagged on any
  example with more than 3 expectations (e.g. `PriceUpdateWorker`'s
  success case, which checks the `PriceLog` row, the `Item`'s updated
  fields, and the stream entry together).
- Mirror the codebase's existing directory shape for new spec paths:
  `spec/parsers/steam/`, `spec/builders/steam/`, `spec/workers/`,
  `spec/schedulers/` — parallel to `app/parsers/steam/`,
  `app/builders/steam/`, `app/workers/`, `app/schedulers/`.
- Enable `Sidekiq::Testing.fake!` globally in `rails_helper.rb` (require
  `sidekiq/testing`), with jobs cleared between examples. This is safe
  against the two existing request specs: `inventories_spec.rb`'s
  "valid token" case never actually reaches
  `ItemsListUpdateWorker.perform_async` (the stubbed inventory only
  contains an item that already exists in fixtures, so
  `missing_names` is empty and `each_slice(500)` never fires) — verified
  by reading `Api::V1::InventoriesController#save_missing_items`.
- For `PriceUpdateWorker`'s Redis Stream publish, use the real
  `STREAM_REDIS_POOL` connection (not a mock) and assert against the
  actual `prices_stream` contents via `XRANGE`. This is the choice that
  actually requires CI's Redis service to be real — a fully mocked
  `redis.xadd` call would let the spec pass without Redis at all, which
  defeats the task's stated purpose ("чтобы эта логика реально
  проверялась в пайплайне"). A small support helper trims/reads the
  stream around each spec so runs stay isolated.
- CI: uncomment the existing commented-out `redis:` service block in
  `app_fetcher/.github/workflows/ci.yml`'s `test` job (keep the
  `valkey/valkey:8` image already written there — it's Redis-protocol
  compatible with the `redis` gem client, and matches what's already
  commented in both this file and `app_core`'s identical block), and
  uncomment/add the three `REDIS_*` env vars in the "Run tests" step,
  pointed at `localhost:6379` with the same `/0`, `/1`, `/2` database
  split `docker-compose.yml` uses.

## Files To Modify

- `app_fetcher/.github/workflows/ci.yml` — uncomment the `redis:`
  service block in the `test` job; uncomment/set `REDIS_URL`,
  add `REDIS_URL_SIDEKIQ`, `REDIS_URL_STREAM` in that job's "Run tests"
  step env. Reason: this is the CI-enablement half of the task.
- `app_fetcher/spec/rails_helper.rb` — `require "sidekiq/testing"`,
  `Sidekiq::Testing.fake!`, and a hook (`config.before(:each) {
  Sidekiq::Worker.clear_all }` or equivalent) to reset enqueued jobs
  between examples. Reason: `PriceScheduler`'s spec needs to assert on
  enqueued `PriceUpdateWorker` jobs without a live Sidekiq-backed queue
  connection.
- `app_fetcher/Gemfile` — add `factory_bot_rails` to the `:test` group
  (`Gemfile.lock` updates accordingly via `bundle install`). Reason:
  prerequisite for building test data per
  `.claude/styleguides/rspec-conventions.md`; not present in either app
  yet.

## Files To Create

- `app_fetcher/spec/factories/items.rb` — `FactoryBot` factory for
  `Item`, with traits/overrides for the scenarios this plan needs: a
  stale item (`updated_at` > 1h ago), an item with
  `current_price_cents: nil`, a fresh/already-priced item. Reason:
  replaces what would otherwise be new fixture rows (disallowed by
  `rspec-conventions.md`); needed to drive `PriceScheduler`'s query
  against real rows without stubbing `Item.where`.
- `app_fetcher/spec/factories/price_logs.rb` — `FactoryBot` factory for
  `PriceLog`, with an override for `created_at` older than 24h ago, to
  drive `PriceUpdateWorker`'s `change_24h_cents` "has prior price"
  branch. Reason: same as above; the existing `redline_recent` fixture
  is only 1h old and covers just the other branch.
- `app_fetcher/spec/parsers/steam/item_parser_spec.rb` — unit spec for
  `Steam::ItemParser.parse`/`.parse_collection` per Expected Behavior
  above. Reason: currently untested.
- `app_fetcher/spec/builders/steam/price_log_builder_spec.rb` — unit
  spec for `Steam::PriceLogBuilder.build`, covering populated/nil/empty
  DTO fields. Reason: currently untested.
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — unit spec for
  `PriceUpdateWorker#perform`, covering missing item, success (both
  `change_24h_cents` branches), and Steam API failure/error, asserting
  DB state and the real `prices_stream` contents. Reason: currently
  untested; this is the component with the most branching and the only
  one that talks to Redis directly.
- `app_fetcher/spec/workers/items_list_update_worker_spec.rb` — unit
  spec for `ItemsListUpdateWorker#perform`, covering create, upsert of
  an existing row, and empty input. Reason: currently untested.
- `app_fetcher/spec/schedulers/price_scheduler_spec.rb` — unit spec for
  `PriceScheduler#perform`, covering the stale/nil-price enqueue case,
  the fresh-item non-enqueue case, and multiple qualifying items.
  Reason: currently untested.
- `app_fetcher/spec/support/redis_stream_helper.rb` — small helper
  module providing a way to trim/clear `prices_stream` before/after a
  spec (e.g. `XTRIM prices_stream MAXLEN 0`) and read back entries via
  `XRANGE`, used by `price_update_worker_spec.rb`. Follows the shape of
  the existing `bridge_token_helper.rb` support file (a plain module,
  auto-loaded, included via `RSpec.configure`). Reason: isolates
  stream-touching specs from each other and from any stale local-dev
  stream data.

## Test Plan

Covered in detail under Expected Behavior and Files To Create above.
Summary of scenario coverage per component:

| Component | Success | Empty/sparse response | API error | Other |
|---|---|---|---|---|
| `Steam::ItemParser` | ✓ (multiple name shapes) | ✓ (empty collection) | n/a (no API call) | — |
| `Steam::PriceLogBuilder` | ✓ | ✓ (nil/empty DTO fields) | n/a (no API call) | — |
| `PriceUpdateWorker` | ✓ (both `change_24h_cents` branches) | ✓ (Steam `success: 0`) | ✓ (429/other status) | missing item guard |
| `ItemsListUpdateWorker` | ✓ (create) | ✓ (empty array) | n/a (no API call itself — parsing only) | upsert of existing row |
| `PriceScheduler` | ✓ (enqueues stale/nil-price items) | n/a | n/a (no API call) | fresh item NOT enqueued; multiple items |

All Steam API simulation goes through `WebMock` stubs against
`https://steamcommunity.com/...`, matching the existing
`inventories_spec.rb` pattern — never stubbing `Steam::Client` itself.

## Implementation Steps

1. Add `factory_bot_rails` to `app_fetcher/Gemfile`'s `:test` group,
   `bundle install`. Add `Sidekiq::Testing` setup to `rails_helper.rb`
   (require + `fake!` + per-example job clearing). Run the existing two
   request specs to confirm no regression.
2. Add `spec/support/redis_stream_helper.rb`.
3. Add `spec/factories/items.rb` and `spec/factories/price_logs.rb`
   with the traits/overrides needed for `PriceScheduler`/
   `PriceUpdateWorker` scenarios (existing fixtures — `redline`,
   `redline_recent` — stay untouched).
4. Write `item_parser_spec.rb` (red → green; pure function, no new
   fixtures needed beyond inline strings).
5. Write `price_log_builder_spec.rb` (red → green; construct
   `Steam::Response::Data::ItemPriceData` DTOs inline).
6. Write `price_log_builder_spec.rb`'s sibling for the worker layer:
   `price_update_worker_spec.rb` — requires a real Redis connection
   (`STREAM_REDIS_POOL`) to pass, so run this step against a local Redis
   (e.g. `docker compose up redis` or a bare `redis-server` on 6379)
   before it's expected to pass in CI.
7. Write `items_list_update_worker_spec.rb`.
8. Write `price_scheduler_spec.rb` (depends on step 1's Sidekiq testing
   setup).
9. Update `app_fetcher/.github/workflows/ci.yml`: uncomment the `redis:`
   service block, uncomment/add the three `REDIS_*` env vars in the
   "Run tests" step.
10. Run the full `app_fetcher` suite locally against a real Redis to
    confirm everything is green before relying on CI.
11. Push and confirm the `app_fetcher` CI workflow (`test` job, plus
    `lint`/`scan_ruby` on the new/changed files) is green end-to-end.

## Verification

- `bundle exec rspec` for the full `app_fetcher` suite, run locally
  against a real Redis instance (required for the new
  `price_update_worker_spec.rb` and any Sidekiq-adjacent specs).
- `bin/rubocop` over the new spec files and the two new factory files.
- `bin/brakeman`/`bin/bundler-audit` are unaffected (no new gems, no new
  production code) but will still run in CI as part of `scan_ruby`.
- `sidekiq/testing` and Sidekiq itself are already in `Gemfile.lock` (no
  new dependency there). `factory_bot_rails` is new — confirm
  `bundle install` only adds that gem (and its own dependencies) to
  `Gemfile.lock`, nothing else shifts.
- Final confidence check: push the branch and confirm the
  `app_fetcher` GitHub Actions `CI` workflow (`scan_ruby`, `lint`,
  `test`) is fully green, since the Redis-service behavior can only be
  fully confirmed by an actual Actions run, not a local one.

## Risks

- `PriceUpdateWorker`'s spec depends on a real, reachable Redis at
  `REDIS_URL_STREAM` (defaults to `redis://localhost:6379/2` when unset)
  to pass — this spec will fail (not just skip) in any environment
  without Redis running, including a plain local `bundle exec rspec`
  outside `docker-compose`. This is the intended trade-off per this
  plan's approach (real Redis over a mock), but it does mean local dev
  now needs `docker compose up redis` (or an equivalent local Redis) to
  run the full suite, where it didn't before.
- Running specs against a shared Redis instance (e.g. a developer's
  local `docker-compose` Redis, DB index 2) could interleave with
  manually-triggered dev-time `prices_stream` writes if the app is also
  running locally at the same time. Low risk today since no consumer of
  `prices_stream` exists yet, but the `redis_stream_helper` should trim
  the stream around each spec to minimize pollution either direction.
- Enabling `Sidekiq::Testing.fake!` globally is a cross-cutting change
  to `rails_helper.rb` that affects every spec, not just the new ones —
  confirmed safe against the two existing request specs (see
  Implementation Approach), but worth double-checking after step 1
  rather than assuming.
- `item_parser.rb` and `price_scheduler.rb` are pre-flagged in
  `fix_me.md` as deviating from Sorbet/retry conventions; writing specs
  against their current behavior should not be blocked by those
  deviations, but `implement-plan` should decide explicitly whether
  either trivial fix rides along with this change.

## Assumptions

- The CI Redis image should be `valkey/valkey:8`, matching the value
  already written (but commented out) in both `app_fetcher`'s and
  `app_core`'s workflow files, rather than `redis:7-alpine` (used in
  `docker-compose.yml`). Both are Redis-protocol compatible with the
  `redis` gem client used in `config/initializers/redis.rb`, so this is
  a low-stakes assumption, but not independently confirmed from a
  written decision anywhere.
- ~~"юнит-тесты" for the Redis-Stream-publishing half of
  `PriceUpdateWorker` should hit a real Redis rather than a mock~~ — no
  longer an assumption, now a stated MUST in
  `.claude/styleguides/fetcher/background-jobs.md`'s Testing section and
  `.claude/adr/fetcher/rspec-testing-strategy.md`.
- `REDIS_URL_SIDEKIQ` is passed through CI purely for parity/completeness
  per the task's explicit list of env vars, even though no current
  `app_fetcher` code reads it — confirmed by grep that it's unused
  outside `docker-compose.yml`. Not treated as a bug to fix in this
  plan.

## Applicable Styleguides

- `.claude/styleguides/rspec-conventions.md` — constrains every new spec
  file (`Files To Create`): unit-level placement/`type:` metadata for
  all five components, `FactoryBot` for `Item`/`PriceLog` test data
  (not new fixture rows), `WebMock` (not VCR — this plan adds no
  request specs) for Steam API simulation, no Sorbet sigil on spec
  files, `:aggregate_failures` on any example with more than 3
  expectations.
- `.claude/adr/fetcher/rspec-testing-strategy.md` — the ADR backing the
  above; specifically its background-jobs special case (unit-level
  orchestration + real backing service for a job's own direct I/O)
  is why `PriceUpdateWorker`'s spec uses a real `STREAM_REDIS_POOL`
  instead of a mock, and its FactoryBot-over-fixtures decision is why
  `Files To Create` adds factories instead of extending
  `items.yml`/`price_logs.yml`.
- `.claude/styleguides/fetcher/background-jobs.md` — its Testing section
  constrains the `PriceUpdateWorker`, `ItemsListUpdateWorker`, and
  `PriceScheduler` spec files specifically: `Sidekiq::Testing.fake!`
  (configured in `rails_helper.rb`, not per-spec) for
  `PriceScheduler`'s enqueue assertions, a real Redis connection +
  `XRANGE` assertion (not a mocked `redis.xadd`) for
  `PriceUpdateWorker`'s stream publish, and trimming `prices_stream`
  around specs via `spec/support/redis_stream_helper.rb` for isolation.
  Its pre-existing Rules (queue routing, retry counts, transaction
  boundaries) also describe the production behavior these new specs are
  asserting against.
- `.claude/styleguides/fetcher/steam-response-objects.md` — constrains
  how `price_log_builder_spec.rb` constructs
  `Steam::Response::Data::ItemPriceData` DTOs (via `.new`/`from_hash`
  semantics, `const` fields) and the response shape
  `price_update_worker_spec.rb`'s `WebMock` stubs must produce for
  `Steam::Client` to parse successfully.
- `.claude/adr/fetcher/price-updates-via-redis-stream.md` — explains why
  `prices_stream` exists and is worth asserting against for real, which
  is the reasoning `price_update_worker_spec.rb` and this plan's
  CI-Redis-enablement half both depend on.
- `.claude/styleguides/ruby-sorbet.md` — not modified by this plan (no
  production Ruby files change), but its "every hand-written file gets
  a sigil" rule is why `rspec-conventions.md` had to state explicitly
  that spec files are exempt; referenced for that boundary, not applied
  directly here.
- `.claude/styleguides/git-commits.md` — applies at commit time once
  implementation lands (scope tag `[Fetcher]`, given every changed file
  is under `app_fetcher/`).

## Completion Criteria

- All five components have direct unit specs covering the scenarios in
  Expected Behavior.
- `app_fetcher/.github/workflows/ci.yml`'s `test` job runs a real Redis
  service and passes `REDIS_URL`/`REDIS_URL_SIDEKIQ`/`REDIS_URL_STREAM`
  into the test run.
- The full `app_fetcher` spec suite passes locally against a real Redis.
- The `app_fetcher` CI workflow is green end-to-end on the pushed branch.

# Implementation Summary

## Implemented

- Added `factory_bot_rails` to `app_fetcher/Gemfile`'s `:test` group
  (`Gemfile.lock` updated via `bundle install` — only `factory_bot` and
  `factory_bot_rails` added, nothing else shifted).
- `app_fetcher/spec/rails_helper.rb`: enabled Sidekiq's fake testing mode,
  included `FactoryBot::Syntax::Methods` globally, and added a
  `before(:each) { Sidekiq::Worker.clear_all }` hook so enqueued jobs
  don't leak between examples.
- `app_fetcher/spec/support/redis_stream_helper.rb` (new): a
  `RedisStreamHelper` module (`flush_prices_stream`,
  `prices_stream_entries`) against the real `STREAM_REDIS_POOL`, included
  globally via `RSpec.configure`.
- `app_fetcher/spec/factories/items.rb`, `spec/factories/price_logs.rb`
  (new): `FactoryBot` factories for `Item` (`:stale`, `:without_price`
  traits) and `PriceLog` (`:old` trait, >24h old), replacing what would
  otherwise have been new fixture rows.
- Five new unit spec files, one per component in scope:
  - `spec/parsers/steam/item_parser_spec.rb`
  - `spec/builders/steam/price_log_builder_spec.rb`
  - `spec/workers/price_update_worker_spec.rb`
  - `spec/workers/items_list_update_worker_spec.rb`
  - `spec/schedulers/price_scheduler_spec.rb`
- `app_fetcher/.github/workflows/ci.yml`: uncommented the `redis:`
  service (`valkey/valkey:8`) in the `test` job, added
  `REDIS_URL`/`REDIS_URL_SIDEKIQ`/`REDIS_URL_STREAM` to the "Run tests"
  step env, and fixed the run command (see Deviations).

No production business logic was changed — all five components' behavior
was already correct; this is coverage for existing behavior.

## Tests

27 examples total (6 pre-existing + 21 new), 0 failures. Commands
actually executed (inside the running `steam_project-app_fetcher-1`
Docker container, which has real network access to `db_fetcher`
(Postgres) and `redis` — the same `redis:7-alpine` instance the compose
stack already runs):

- `bundle exec rails db:test:prepare` (test DB setup)
- `bundle exec rspec` — run after each new spec file and again after the
  full set was in place; run three times in a row against the full suite
  to check for order-dependent flakiness (RSpec randomizes example
  order by default) — stable at 27/0 every time.
- `bundle exec rails db:test:prepare spec` — the exact command now used
  by CI's `test` job, run locally as a final check (27 examples, 0
  failures, exit 0).

Coverage per component matches the plan's Test Plan table: `ItemParser`
(7 examples: weapon/item/condition split, StatTrak, Souvenir, no
separator, no condition, `parse_collection` map + empty array);
`PriceLogBuilder` (3: fully-populated DTO incl. `$`-prefixed and
comma-decimal prices, nil fields, empty-string fields); `PriceUpdateWorker`
(5: missing item guard, first-ever price + real stream publish, prior
price log older than 24h → `change_24h_cents` diff, unsuccessful Steam
response, Steam error status); `ItemsListUpdateWorker` (3: create,
upsert of an existing row, empty array); `PriceScheduler` (3: stale/
no-price enqueue, fresh item not enqueued, multiple qualifying items).

## Verification

- `bundle exec rspec` / `bundle exec rails db:test:prepare spec`: 27
  examples, 0 failures (run repeatedly, stable).
- `bundle exec rubocop <touched Ruby files>`: initially 4
  `Layout/SpaceInsideArrayLiteralBrackets` offenses in two new spec
  files (project style wants `[ "a", "b" ]`, not `["a", "b"]`) —
  autocorrected with `rubocop -A`, then re-verified clean (0 offenses
  across all 9 touched/created Ruby files). A broader `rubocop app spec`
  run afterward found 3 more offenses, all in pre-existing production
  files I never touched (`price_log_builder.rb`, `inventories_controller.rb`,
  `items_list_update_worker.rb` — trailing whitespace/missing newline) —
  left alone as out of scope.
- `bundle exec brakeman --no-pager`: exits 3 (1 warning: Rails 7.2.3.1
  is past EOL). Confirmed pre-existing and unrelated by re-running
  against the codebase with my changes stashed — same warning, same
  exit code.
- `bundle exec bundler-audit check --update`: exits 1 (2 CVEs in `yard`
  0.9.38, pulled in transitively via `yard-sorbet`/`tapioca`). Confirmed
  pre-existing via `git show HEAD:app_fetcher/Gemfile.lock` — `yard` was
  already pinned at 0.9.38 before this change; my `Gemfile.lock` diff
  only adds `factory_bot`/`factory_bot_rails`.
- `bundle exec srb tc`: 54 errors, but 51 of them exist on the
  unmodified codebase too (confirmed by re-running with my changes
  stashed) — all inside `app/workers/price_update_worker.rb`, a file I
  never touched. The 3 new ones are "Unable to resolve constant"
  (`Sidekiq`, `FactoryBot`) on `spec/rails_helper.rb` — the exact same
  error class every existing spec file already produces (`RSpec`, `JWT`
  unresolved in `inventories_spec.rb`, `bridge_token_helper.rb`, etc.),
  confirming this is this project's already-accepted Sorbet-vs-spec
  behavior, not a regression. `srb tc` is not part of the plan's
  Verification section.
- Filed a separate follow-up (not fixed here, confirmed out of scope):
  the pre-existing Brakeman/bundler-audit failures above.

## Deviations

- **`Sidekiq.testing!(:fake)` instead of `require "sidekiq/testing"` +
  `Sidekiq::Testing.fake!`.** The plan specified the latter, but Sidekiq
  8.1.4 (the version actually installed) prints "⛔️ `require
  "sidekiq/testing"` is deprecated and will be removed in Sidekiq 9.0"
  when used. Switched to the non-deprecated equivalent API with
  identical semantics (`.jobs`, `Sidekiq::Worker.clear_all` all still
  work — `Sidekiq::Worker` is a plain alias for `Sidekiq::Job` in this
  version). No behavior change, just avoids a warning the plan couldn't
  have anticipated without running against this exact gem version.
- **CI's `run:` command changed from `bin/rails db:test:prepare test` to
  `bin/rails db:test:prepare spec`, beyond what the plan specified.**
  Discovered that `bin/rails test` runs Minitest against a `test/`
  directory that doesn't exist in this app (RSpec is the only test
  framework in use) — it silently reports "0 runs, 0 failures" and
  exits 0. This means CI's `test` job has never actually executed the
  RSpec suite, before or after enabling Redis; my new specs (and the two
  pre-existing ones) would never have run in CI even with Redis
  available. `rspec-rails` provides a `bin/rails spec` task that
  correctly shells out to `rspec` (verified: exit 0 on the full green
  suite). Fixed as part of this same change since it's the exact line
  being edited for the Redis-enablement task, and without it the
  plan's stated completion criterion ("CI is green end-to-end") would
  be true for a meaningless reason (zero tests run) rather than the
  actual one. `app_core`'s CI has the identical `... test` pattern —
  not touched, out of scope for this plan.

## Remaining Issues

- **Actual GitHub Actions run not confirmed** — pushing a branch and
  observing the real Actions run is outside what this environment can
  do; local verification used the exact CI command
  (`bin/rails db:test:prepare spec`) inside a container with real
  Postgres and Redis, which is the strongest available proxy, but the
  plan's literal completion criterion ("CI workflow is green end-to-end
  on the pushed branch") needs a human (or a follow-up session with push
  access) to confirm on an actual PR.
- **`scan_ruby` CI job will fail regardless of this change** — pre-existing
  Brakeman (Rails EOL) and bundler-audit (`yard` CVEs) findings, confirmed
  unrelated to this plan (see Verification). Spun off as a separate
  follow-up task rather than bundled into this PR.
- **The two `fix_me.md` entries for `item_parser.rb` (missing `T.let`)
  and `price_scheduler.rb` (missing `retry:`) were deliberately left
  unfixed.** Neither file was otherwise being edited by this plan (no
  entry in Files To Modify), and the plan's own Out of Scope section
  reserves this decision for `implement-plan`. `price_scheduler.rb`'s
  fix would change runtime retry behavior — not a pure style fix, and
  choosing a correct `retry:` value wasn't scoped by this plan. Left
  both entries in place, unfixed.
- `app_core`'s CI workflow has the identical commented-out Redis service
  and the identical `bin/rails ... test` (0-tests) issue — confirmed
  out of scope per the plan, not touched.
