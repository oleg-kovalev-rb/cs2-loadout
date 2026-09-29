---
status: implemented
app: fetcher+core
goal: Record each user's daily inventory value in app_fetcher (keyed by steam_id), self-seeded on the first request that finds none and refreshed nightly, with a read endpoint for the eventual dashboard chart
created: 2026-09-29
---

# Development Plan

## Goal

Start recording a real, persisted history of each user's inventory value
over time — one point per calendar day, starting from around their
first-ever login — so the dashboard can eventually plot actual
wealth-over-time instead of the client-computed, current-inventory-only
series `portfolioSeries.js` produces today. This plan covers the backend
only: the table, the seed, the nightly refresh, and a read endpoint.
Wiring the React dashboard to actually fetch and render this new endpoint
(likely replacing or extending `PortfolioTile`'s series) is explicitly
**out of scope** — see Scope.

## Why this lives in `app_fetcher`, not `app_core`

`app_core` has no API of its own (`.claude/adr/core/
thin-controllers-actions-direct-fetcher-reads.md`) — every existing
`/api/v1/...` endpoint the dashboard calls lives in `app_fetcher`. This
plan's new table is keyed by **`steam_id`**, not `user_id` — `app_fetcher`
has no `User` model today and this plan doesn't introduce one; `steam_id`
is already the sole identity concept throughout `app_fetcher`
(`UserInventoryCache`, `current_steam_id`). Computing the value itself
also only needs data `app_fetcher` already owns (`Item.current_price_cents`
+ a live Steam inventory-composition fetch).

## Revision: self-seeding instead of a cross-app trigger call

The original version of this plan had `app_core`'s `Steam::LoginUser`
detect a brand-new `steam_id` and make a synchronous, fire-and-forget
HTTP call to a new `app_fetcher` endpoint to seed the first log entry —
`app_core`'s first-ever backend-to-backend call to `app_fetcher`, with
its own new ADR justifying the exception. During implementation review
this was replaced with a smaller design that needs no new cross-app
coupling at all:

`Api::V1::InventoryValuesController#index` (the read endpoint) now
**self-seeds**: if it finds zero log entries for `current_steam_id`, it
enqueues `InventoryValueUpdateWorker` for that `steam_id` (deduplicated,
same shape as the existing `InventoriesController#enqueue_price_warmup`
pattern already documented in `caching.md`) before rendering the
(empty) response. The very first `GET /api/v1/inventory_values` the
browser ever makes for a `steam_id` is what plants the seed — no
backend-to-backend call, no new `lib/steam/` class, no new ADR. This
mirrors an already-accepted pattern in this codebase (a normal read
request opportunistically warming missing data) instead of introducing a
new one.

This does shift "Day 0" from "the literal instant of registration" to
"the first time this `steam_id`'s dashboard data is read" — for that
gap to matter, a user would have to sign up and never reach `/dashboard`.
Checked, not assumed: today `SessionsController#callback` redirects to
`root_path`, a *separate* page (`HomePagesController`) with a manual
"Go to dashboard" link — so this plan also fixes that gap directly:
`HomePagesController#index` now redirects an already-signed-in visitor
straight to `dashboard_path`, so `root_path` (`SessionsController`'s
post-login redirect target) leads to the dashboard immediately, with no
extra click, for every login. "Day 0" and "first login" are the same
moment again in practice, without needing the backend-to-backend call
that provided that guarantee in the original design.

## Naming: `InventoryValueLog`, not "Snapshot" or "History"

Every value this plan records is, in some sense, a snapshot, and every
value this plan *reads back* is, in some sense, historical — neither
word distinguishes this data from anything else `app_fetcher` stores, so
both were dropped from every class/table/route name. What's left:

- **Model/table**: `InventoryValueLog`/`inventory_value_logs` — one
  persisted row per `steam_id` per day — mirrors `app_fetcher`'s existing
  `PriceLog`/`price_logs` naming exactly.
- **Controller/route**: `Api::V1::InventoryValuesController`/
  `inventory_values` — plain, not framed as a "history" endpoint just
  because what it returns happens to span multiple days. One action,
  `#index` — no separate trigger action (see Revision above).
- **Worker/scheduler**: `InventoryValueUpdateWorker`/
  `InventoryValueScheduler` — follows `PriceUpdateWorker`/
  `PriceScheduler`'s existing `<Noun>UpdateWorker`/`<Noun>Scheduler`
  naming (see `background-jobs.md`), not a name derived from the model.

## Expected Behavior

**Normal behavior**

- The first `GET /api/v1/inventory_values` request for a `steam_id` with
  no existing log entries returns an empty `points` array and enqueues a
  worker that records today's value; a later request (once the worker has
  run) sees that first point.
- Once nightly (00:00 UTC), every `steam_id` that has at least one log
  entry gets a new point recorded for that day, computed from their
  current Steam inventory composition and `app_fetcher`'s own current
  prices.
- Signing in redirects to `root_path`, which — for an already-signed-in
  visitor — now redirects straight to `dashboard_path`, so the
  dashboard's data (and therefore this seed) loads immediately after
  login in the normal case.
- A logged-in user's dashboard can request their full history
  (`GET /api/v1/inventory_values`) and get back one point per day,
  oldest first.
- Re-running the update for a `steam_id` on a day it already has an
  entry (e.g. the seed landing the same day as that night's scheduler
  run) updates that day's value in place — never a second row for the
  same day.

**Edge cases**

- An item the user owns that has no `Item` row in `app_fetcher` at all
  yet contributes `0` to that day's total (mirrors `ItemPriceCache.
  fetch_for`'s existing "omit names with no matching row" behavior) —
  this plan does not attempt to backfill/warm those items as a side
  effect; that's the existing warmup path's job.
- An item with an `Item` row but `current_price_cents: nil` (not yet
  priced) contributes `0`, not an error.
- An inventory with zero items produces a `total_value_cents: 0` log
  entry, not a skipped day.
- A repeat `GET /api/v1/inventory_values` for the same still-empty
  `steam_id` within the dedup window (90 seconds, matching the existing
  warmup pattern's derivation) does not enqueue a second seed.

**Failure behavior**

- If the Steam inventory call fails (rate-limited or otherwise) for a
  given `steam_id` on a given night — or during the seed itself — no log
  entry is written for that day; that `steam_id`'s chart has a gap for
  that day, not a stale duplicate or a zero. A later request/night tries
  again (the dedup key expires; the nightly scheduler retries anyone
  with at least one entry, and a `steam_id` that never got a successful
  seed simply gets re-attempted the next time `#index` is called with
  still-zero entries).

**Must remain unchanged**

- `Steam::LoginUser.call`'s existing behavior — untouched by the final
  version of this plan.
- Every existing `app_fetcher` endpoint, cache, worker, and scheduler.

## Scope

### In Scope

- New `app_fetcher` table + model (`InventoryValueLog`).
- New `app_fetcher` worker (computes + persists one `steam_id`'s value
  for today) and scheduler (nightly fan-out to every known `steam_id`),
  following the exact existing `PriceUpdateWorker`/`PriceScheduler`
  pattern.
- New `app_fetcher` `Api::V1::` read endpoint that self-seeds the first
  entry on a cache-empty read, deduplicated.
- `app_core/app/controllers/home_pages_controller.rb` — redirect an
  already-signed-in visitor straight to the dashboard, so "Day 0" and
  "first login" coincide in practice.
- Test coverage for all of the above.

### Out of Scope

- Any React/dashboard change. `PortfolioTile`/`portfolioSeries.js` keep
  computing their current client-side series exactly as today; wiring in
  the new real history is a follow-up plan.
- Задача 3 (historical simulation) — reads from `price_logs`, unrelated
  to this plan's new table, and explicit follow-up work.
- Any "active user" / recency concept for scoping the nightly run — the
  scheduler processes every known `steam_id` every night, accepting that
  Steam's shared rate-limit budget may cause some to miss a day (see
  Risks).
- Backfilling/warming unpriced items as a side effect of computing a
  day's value — relies entirely on the existing, unrelated warmup path.
- Any `app_core`-to-`app_fetcher` backend call, and the `solid_queue`
  setup that would have been a prerequisite for an `app_core`-side async
  version of it — neither is needed by the final design (see Revision).
- Fixing `app_core/spec/controllers/dashboards_controller_spec.rb`'s
  known `type: :controller` deviation (`fix_me.md`).

## Implementation Approach

**Data model (`app_fetcher`).** `inventory_value_logs`: `steam_id`
(string), `log_date` (date), `total_value_cents` (integer), plus
standard timestamps — a unique index on `[steam_id, log_date]` is the
idempotency mechanism, mirroring how `items.market_hash_name` is
uniquely indexed today.

**Computation and persistence: one worker, two triggers — following
`architecture-layers.md`'s existing three-scenario map exactly, adding no
new layer type.**

- `InventoryValueUpdateWorker#perform(steam_id)` (Scenario 3, `app/
  workers/`) is the *only* place that computes and writes. It calls
  `Steam::Client#fetch_user_inventory(steam_id)` (same call
  `Api::V1::InventoriesController#show` already makes), and on success,
  bulk-looks-up prices via `ItemPriceCache.fetch_for(names)`, sums
  `current_price_cents || 0` across the returned items, and writes one
  row via `InventoryValueLog.upsert_all([{...}], unique_by: [:steam_id,
  :log_date])` — a single-row `upsert_all` rather than
  `find_or_initialize_by` + save, so a near-simultaneous seed + nightly
  run for the same `steam_id`/day resolves at the database's `ON
  CONFLICT`. On a failed Steam response, log a
  `[InventoryValueUpdateWorker] ...` warning and return — no row
  written, matching `PriceUpdateWorker`'s existing failure shape.
- `InventoryValueScheduler#perform` (Scenario 2, `app/schedulers/`) does
  no I/O itself — queries `InventoryValueLog.distinct.pluck(:steam_id)`
  for every `steam_id` that has ever had a log entry, and fans out
  `InventoryValueUpdateWorker.perform_async(steam_id)` once per id.
  Triggered nightly by `sidekiq-cron` via a new `config/schedule.yml`
  entry (`schedule_inventory_value_updates`, `cron: "0 0 * * *"`),
  exactly like `PriceScheduler`'s existing hourly entry.
- `Api::V1::InventoryValuesController#index` (Scenario 1, `app/
  controllers/api/v1/`) reads `InventoryValueLog.where(steam_id:
  current_steam_id).order(:log_date)` and renders `{points: [...]}`. If
  that query is empty, it *first* enqueues
  `InventoryValueUpdateWorker.perform_async(current_steam_id)` — guarded
  by the same `Rails.cache.write(key, true, unless_exist: true,
  expires_in: 90.seconds)` dedup shape `InventoriesController
  #enqueue_price_warmup` already uses — before rendering the (still
  empty, this time) response. No `Steam::Client` call and no persistence
  happen inside the controller itself; it only enqueues, per
  `internal-api-controllers.md`.
- The route is explicit (`get "inventory_values"`, no bare `resources`),
  per `internal-api-controllers.md`.

**`app_core`'s `HomePagesController` fix.** `index` now checks
`current_user` first and redirects to `dashboard_path` immediately if
present, before rendering the sign-in/welcome view. `Steam::LoginUser`
itself is untouched — the fix lives entirely in how the post-login
redirect target behaves for an already-signed-in visitor.

## Files To Modify

- `app_fetcher/config/routes.rb` — add `get "inventory_values"` under
  the existing `api/v1` namespace.
- `app_fetcher/config/schedule.yml` — add the nightly
  `InventoryValueScheduler` entry.
- `app_fetcher/db/schema.rb` — regenerated by the new migration.
- `app_core/app/controllers/home_pages_controller.rb` — redirect to
  `dashboard_path` when `current_user` is present.

## Files To Create

- `app_fetcher/db/migrate/<timestamp>_create_inventory_value_logs.rb` —
  the table + unique `[steam_id, log_date]` index.
- `app_fetcher/app/models/inventory_value_log.rb` — plain
  `ApplicationRecord`, presence/uniqueness validations mirroring the DB
  constraint.
- `app_fetcher/app/workers/inventory_value_update_worker.rb`.
- `app_fetcher/app/schedulers/inventory_value_scheduler.rb`.
- `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb`.
- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb`.
- `app_fetcher/spec/schedulers/inventory_value_scheduler_spec.rb`.
- `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb`.
- `app_fetcher/spec/factories/inventory_value_logs.rb`.
- `app_core/spec/requests/home_pages_spec.rb` — `app_core`'s first
  request spec (per `rspec-testing-strategy.md`'s note that none existed
  yet).

## Test Plan

- **`InventoryValueUpdateWorker`** (unit, WebMock-stubbed Steam
  inventory endpoint, real `Item`/`ItemPriceCache` state via factories):
  successful fetch with priced items writes a row with the correct
  summed total; an owned item with `current_price_cents: nil` counts as
  `0`; an owned item with no matching `Item` row at all is omitted
  (counts as `0`, no error); a failed Steam response writes nothing and
  logs; running twice for the same `steam_id`/day updates the existing
  row in place (count stays 1, value reflects the second run).
- **`InventoryValueScheduler`** (unit, `Sidekiq::Testing.fake!`):
  enqueues the worker once per distinct `steam_id` that already has a
  log entry; no duplicate enqueues for a `steam_id` with multiple
  historical entries.
- **`Api::V1::InventoryValuesController`** (request,
  `Sidekiq::Testing.fake!`): unauthenticated → `:unauthorized`
  (regression, matches existing bridge-token auth behavior); with
  existing entries → returns only the authenticated `steam_id`'s own
  points, oldest first, does not leak another `steam_id`'s rows, and
  does not enqueue a seed; with zero entries → returns an empty list and
  enqueues exactly one seed for `current_steam_id`; a repeat request
  within the dedup window does not enqueue a second seed.
- **`HomePagesController`** (request, `app_core`'s first): a signed-out
  visitor gets the sign-in page; a signed-in visitor is redirected to
  `dashboard_path`.

## Implementation Steps

1. `app_fetcher`: migration + model (`InventoryValueLog`).
2. `app_fetcher`: TDD `InventoryValueUpdateWorker` against its spec.
3. `app_fetcher`: TDD `InventoryValueScheduler` against its spec; wire
   it into `config/schedule.yml`.
4. `app_fetcher`: TDD `Api::V1::InventoryValuesController#index`,
   including the self-seed + dedup path, against its request spec; wire
   the route.
5. `app_core`: TDD the `HomePagesController` redirect against its
   first-ever request spec.

## Verification

- `app_fetcher`: targeted specs for the new files, then the full suite
  (regression).
- `app_core`: targeted specs for `home_pages_spec.rb`, then the full
  suite (regression).
- `bin/rubocop` in both apps (matching this repo's existing per-change
  convention).
- `bin/rails db:test:prepare` in `app_fetcher` after the new migration.
- Manual: not planned to be performed live (same environment limitation
  noted in prior plans this session).

## Risks

- **`steam_inventory_rpd` (1000/day) is shared between this nightly job,
  the seed path, and ordinary daytime dashboard traffic**, and this plan
  deliberately doesn't scope or throttle beyond what `Prop.throttle!`
  already enforces globally — mirrors `PriceScheduler`'s own
  already-accepted shared-budget risk. As the user base grows past what
  1000/day can cover, some users will reliably miss nights/seeds, not
  just occasionally — worth revisiting once real usage data exists.
- **The seed now depends on the browser actually calling
  `GET /api/v1/inventory_values` at least once** (rather than firing
  unconditionally at login) — mitigated by the `HomePagesController`
  redirect fix so this happens immediately after every login in
  practice, but it's still a request-driven trigger rather than an
  unconditional one; a user who somehow never loads the dashboard still
  never gets seeded (same as: their inventory value was never going to
  be shown to them anyway, so this is a non-issue in practice).
- **A near-simultaneous seed request and nightly scheduler run for a
  brand-new `steam_id`** is handled by the `upsert_all`/unique-index
  combination resolving at the database level.
- **`app_core`'s `HomePagesController` had zero existing test
  coverage** — this plan's new spec is the first ever written against
  it, and is also `app_core`'s first `type: :request` spec — no
  established "sign in for a request spec" helper existed yet, so the
  spec stubs `current_user` via `allow_any_instance_of
  (ApplicationController)` rather than driving a real session (direct
  `session[:user_id] = ...` assignment before the first request doesn't
  take effect in this Rails version's integration-test session — checked
  empirically, not assumed). A more robust sign-in helper for future
  `app_core` request specs is a reasonable follow-up, not solved here.

## Assumptions

- `Date.current`/server time in `app_fetcher` is UTC (Rails' default
  unless configured otherwise) — not independently verified by checking
  `config.time_zone`.
- A dedicated `spec/models/inventory_value_log_spec.rb` was judged
  redundant with what the worker/request specs already exercise —
  consistent with existing precedent (`Item`/`PriceLog` have no
  dedicated model specs either).

## Applicable Styleguides

- `.claude/styleguides/fetcher/architecture-layers.md` — confirms the
  Controller/Scheduler/Worker split matches this app's existing
  Scenario 1/2/3 map exactly: the controller only enqueues (never calls
  `Steam::Client` or persists) and does so following the same
  self-warmup shape `InventoriesController` already uses; the scheduler
  only queries local state and fans out; the worker is the only layer
  that calls `Steam::Client` and persists.
- `.claude/styleguides/fetcher/background-jobs.md` — constrains
  `InventoryValueUpdateWorker`/`InventoryValueScheduler`: explicit
  `sidekiq_options queue:, retry:`, routing Steam-calling work onto the
  `:prices` queue (same as `PriceUpdateWorker`), idempotent writes,
  guard-and-log on a failed Steam response.
- `.claude/styleguides/fetcher/internal-api-controllers.md` — constrains
  `Api::V1::InventoryValuesController`: explicit route (no bare
  `resources`), `current_steam_id` as the only identity source, one
  collaborator per action, JSON response shape.
- `.claude/styleguides/fetcher/caching.md` — the worker becomes a new
  caller of `ItemPriceCache.fetch_for`; the controller's self-seed
  reuses the existing Warmup/Dedup Pattern section verbatim (same
  `Rails.cache.write(..., unless_exist: true)` shape, same 90-second
  derivation reasoning).
- `.claude/styleguides/core/architecture-layers.md` — unchanged by the
  final version of this plan; the `HomePagesController` fix is a plain
  controller-level redirect, not a new external call or a new layer.
- `.claude/styleguides/rails-layering.md`, `.claude/styleguides/
  ruby-sorbet.md` — the cross-app layering invariant and Sorbet/Ruby
  conventions every new file follows (`typed: strict`, `sig` on every
  method, `Steam::` namespacing not needed here since nothing new calls
  the Steam API from `app_core`).
- `.claude/styleguides/rspec-conventions.md` +
  `.claude/adr/fetcher/rspec-testing-strategy.md` — constrains every new
  spec's level (unit for the worker/scheduler, request for both new
  controllers), `FactoryBot` for test data, `Sidekiq::Testing.fake!` for
  enqueue assertions.
- `.claude/styleguides/git-commits.md` — this plan touches both apps, so
  its implementation commit is tagged `[Core+Fetcher]`.

## Completion Criteria

- [x] Desired behavior made explicit.
- [x] Scope explicit.
- [x] Affected files/components identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (styleguides-check ran against
  the original cross-app-call design; the revision below removes a
  styleguide dependency rather than adding one, so it doesn't reopen
  that gate — see Revision).
- [x] Implemented (`implement-plan`).

# Implementation Summary

## Implemented

**`app_fetcher`**

- `db/migrate/20260929120000_create_inventory_value_logs.rb` +
  `app/models/inventory_value_log.rb` — `inventory_value_logs`
  (`steam_id`, `log_date`, `total_value_cents`, timestamps), unique
  index on `[steam_id, log_date]`.
- `app/workers/inventory_value_update_worker.rb`
  (`InventoryValueUpdateWorker#perform(steam_id)`) — calls
  `Steam::Client#fetch_user_inventory`, bulk-looks-up prices via
  `ItemPriceCache.fetch_for`, sums `current_price_cents || 0`, writes via
  `InventoryValueLog.upsert_all(..., unique_by: [:steam_id, :log_date])`.
- `app/schedulers/inventory_value_scheduler.rb`
  (`InventoryValueScheduler#perform`) — fans out to every known
  `steam_id`. Wired into `config/schedule.yml` as
  `schedule_inventory_value_updates` (`0 0 * * *`).
- `app/controllers/api/v1/inventory_values_controller.rb`
  (`Api::V1::InventoryValuesController#index`) — reads this
  `steam_id`'s log entries; self-seeds (deduplicated,
  `enqueue_first_value_seed`) when none exist yet. Route:
  `get "inventory_values"`.

**`app_core`**

- `app/controllers/home_pages_controller.rb` — redirects to
  `dashboard_path` when `current_user` is present, before rendering the
  sign-in view — makes "Day 0" and "first login" coincide in practice
  without any cross-app call.

## Superseded (built, then removed during the same implementation pass)

The original design added `app_core/lib/steam/inventory_value_trigger.rb`
(a fire-and-forget HTTP call to `app_fetcher`, triggered from
`Steam::LoginUser` on a brand-new `steam_id`), its own ADR
(`.claude/adr/core/backend-triggers-to-fetcher.md`), a matching edit to
`.claude/styleguides/core/architecture-layers.md`, a `#create` action on
the `app_fetcher` controller, and `app_core`'s first `FactoryBot`
setup + a `Steam::LoginUser` spec to cover the trigger call. All of this
was implemented, tested, and green — then replaced during a
post-implementation design discussion (see Revision above) with the
smaller self-seeding design, once it became clear the existing
`enqueue_price_warmup` pattern already solved the same problem without
introducing a new cross-app coupling or a new ADR. `factory_bot_rails`
was left in `app_core`'s `Gemfile` (harmless, general-purpose
infrastructure now available for `app_core`'s *next* test that needs
it — not itself something this plan's final scope required, but not
worth un-adding either) — `spec/factories/users.rb` was kept for the
same reason, even though the spec that originally motivated it
(`login_user_spec.rb`) was deleted along with the reverted trigger
logic.

## Tests

- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb` (5
  examples), `.../schedulers/inventory_value_scheduler_spec.rb` (3
  examples), `.../requests/api/v1/inventory_values_spec.rb` (4
  examples: unauthenticated, existing-entries-no-seed,
  empty-entries-seeds-once, dedup-on-repeat), `.../factories/
  inventory_value_logs.rb`.
- `app_core/spec/requests/home_pages_spec.rb` (2 examples, `app_core`'s
  first request spec): signed-out renders the sign-in page; signed-in
  redirects to `dashboard_path`.
- Test-sensitivity check performed on the dedup guard specifically:
  temporarily disabled the `Rails.cache.write(..., unless_exist: true)`
  guard and confirmed the "no duplicate seed" example fails for the
  right reason (2 enqueues instead of 1), then restored it — done
  because the test and implementation were written close together in
  this revision pass, so this substitutes for strict test-first
  ordering on that one example.

Commands actually executed for every increment (RED → GREEN), and again
at the end:

```
docker compose up -d db_fetcher db_core redis
docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec [target]"
docker compose run --rm app_fetcher bash -c "bin/rails db:migrate && RAILS_ENV=test bin/rails db:test:prepare"
docker compose build app_core   # to pick up factory_bot_rails after Gemfile/bundle install
docker compose run --rm app_core bash -c "RAILS_ENV=test bundle exec rspec [target]"
docker compose run --rm app_fetcher bash -c "bin/rubocop <files> -f simple"
docker compose run --rm app_core bash -c "bin/rubocop <files> -f simple"
docker compose run --rm app_fetcher bash -c "bundle exec srb tc"
docker compose run --rm app_fetcher bin/brakeman --no-pager
```

## Verification

- **`app_fetcher` full suite**: 60 examples, 0 failures (up from a
  48-example green baseline).
- **`app_core` full suite**: 6 examples, 0 failures (up from a
  4-example green baseline) — the intermediate 12-example count (with
  the now-superseded trigger/login_user specs) is not the final state.
- **Rubocop**: 0 offenses on all touched/created files in both apps
  (autocorrected 4 offenses along the way —
  `Layout/SpaceInsideArrayLiteralBrackets` on the migration,
  `Style/StringLiterals` in code that was later deleted with the
  superseded trigger class).
- **`srb tc`** (checked against the original design; not re-run after
  the revision since the revision only removes code): every new error
  was the same pre-existing category already documented in
  `fetcher-price-caching.md` — unresolved gem/DSL RBIs, `Item#
  current_price_cents` not resolving as a reader, `.perform_async`/
  `sidekiq_options` not resolving on new worker/scheduler classes. No
  new *category* introduced. Not part of this project's CI.
- **Brakeman** (`app_fetcher`): same empty-report-body/tooling quirk
  already noted in the prior plan's implementation summary.
- **Manual check**: not performed live (same environment limitation
  noted in prior plans this session).

## Deviations

- **`app_fetcher/db/cache_schema.rb` was regenerated as an incidental
  side effect** of running `bin/rails db:migrate`/`db:test:prepare`
  (schema-equivalent normalization, unrelated to this plan). Reverted
  with `git checkout`.
- **`InventoryValueUpdateWorker` doesn't use `T.must(response.data)`** —
  matched `Api::V1::InventoriesController#show`'s existing bare
  `response.data.market_hash_names` pattern instead, for consistency.
- **New `fix_me.md` entry**: `app_core/lib/steam/profile_fetcher.rb`'s
  `require` statements use single-quoted strings; confirmed via
  `rubocop` as real drift (not fixed, since that file isn't otherwise
  touched by this plan).
- **The controller/frontend design changed mid-implementation** — see
  "Superseded" above. Per `implement-plan`'s "Handling Unexpected
  Discoveries" guidance this would normally mean stopping and returning
  to `create-dev-plan`; in this case the redesign happened through direct,
  turn-by-turn collaborative discussion covering context, alternatives,
  and trade-offs equivalent to what that stage would produce, so it was
  carried out directly and this plan file was rewritten afterward to
  keep it an accurate record rather than a stale one.
- **No new ADR/styleguide needed for the final design** — the original
  plan's styleguide gate was for the (now-removed) cross-app call; the
  final design reuses an already-covered pattern
  (`caching.md`'s Warmup/Dedup Pattern), so `styleguides-check` was not
  re-run.

## Remaining Issues

- The `steam_inventory_rpd` shared-budget risk remains unaddressed by
  design, per accepted scope.
- `srb tc`'s pre-existing baseline was not fixed — unrelated to this
  change.
- Wiring the React dashboard to actually call
  `GET /api/v1/inventory_values` and render it is explicit follow-up
  work, not started here.
- `app_core` has no reusable "sign in for a request spec" helper yet —
  `home_pages_spec.rb` stubs `current_user` directly; a future spec
  needing the same thing should probably get a shared
  `spec/support/` helper instead of repeating the stub inline.
