---
status: implemented
app: fetcher
goal: Make the nightly inventory-value fan-out cover every known UserInventory (so a missed first seed is backfilled) and cascade InventoryValueLog deletion with its UserInventory
created: 2026-10-19
---

# Development Plan

## Goal

Close two gaps found during review of the inventory-value history
feature:

1. `InventoryValueScheduler` currently fans out only to `steam_id`s that
   already have at least one `InventoryValueLog` row. A user whose
   inventory is known to `app_fetcher` but whose first snapshot never got
   written (dashboard closed before the inventory was fully priced, no
   `inventory_values` request yet, failed frontend fetch, admin-synced
   inventory) is therefore never picked up by the nightly run. The
   scheduler should fan out for every `UserInventory`, whether or not a
   log exists yet.
2. `UserInventory` declares `has_many :inventory_value_logs` without a
   `dependent:` option, so deleting an inventory through the admin API
   leaves its logs behind. Since deleting an inventory is the app's
   "forget this user" operation, the logs must be deleted with it.

The second point also makes the first one unambiguous: after this change
`inventory_value_logs` has no independent existence from
`user_inventories`, so `UserInventory` is the correct and only source of
truth for the nightly fan-out.

## Expected Behavior

**Normal behavior**

- Once nightly, `InventoryValueScheduler` enqueues
  `InventoryValueUpdateWorker` exactly once for every distinct `steam_id`
  present in `user_inventories` — including `steam_id`s that have no
  `InventoryValueLog` row yet.
- A user whose inventory is known but whose first snapshot never got
  written gets that snapshot on the next nightly run, instead of waiting
  for another dashboard visit (which, for a dormant user, may never
  come).
- Deleting a `UserInventory` deletes every `InventoryValueLog` row with
  the same `steam_id`. No log row survives its inventory.
- The scheduler keeps the existing `retry: 3`-style explicit retry
  policy required of every scheduler/worker.

**Edge cases**

- A `steam_id` with an `InventoryValueLog` but no `UserInventory` (a
  legacy orphan from before this change) is not fanned out. The
  recording service would return `Skipped` for it anyway, so enqueuing
  would be a no-op job.
- A `UserInventory` with zero items still gets a nightly job like any
  other; `InventoryValueRecordingService` already treats it as fully
  priced and writes a `total_value_cents: 0` row.
- A `UserInventory` with a `marketable` item still awaiting a price still
  gets a nightly job; the service returns `Skipped`, writing nothing —
  same as today.
- Deleting one user's inventory must not delete another `steam_id`'s
  logs.
- Re-running the scheduler must not enqueue duplicate jobs for the same
  `steam_id` (guaranteed by the unique index on
  `user_inventories.steam_id`).

**Failure behavior**

- Unchanged: if the recording service cannot write a row (missing
  inventory, unpriced marketable item), it returns `Skipped` and the day
  simply has no row for that `steam_id`.
- Unchanged: no Steam call happens in the scheduler. It only reads local
  rows and enqueues jobs.

**Must remain unchanged**

- `InventoryValuesController#index`'s synchronous first-read seed via
  `InventoryValueRecordingService.call`.
- The per-day idempotency of `InventoryValueLog` (`upsert_all` on
  `[steam_id, log_date]`).
- The public and admin read paths that consume `InventoryValueLog`.
- `UserInventorySyncService` / `UserInventory.sync!` behavior.

## Scope

### In Scope

- `InventoryValueScheduler` fan-out source: `UserInventory`, not
  `InventoryValueLog`.
- Explicit `retry:` on `InventoryValueScheduler`.
- `dependent: :delete_all` on `UserInventory#inventory_value_logs`.
- Scheduler and model specs for the new behavior.
- Correcting the living user story
  (`agent/US/dashboard-user-story.md`) where it describes the scheduler
  and the first-read seed.
- Removing the now-fixed `InventoryValueScheduler` entry from
  `agent/styleguides/fix_me.md`.

### Out of Scope

- A one-off cleanup of legacy orphan `InventoryValueLog` rows in
  existing databases. They stop being updated after this change; deleting
  them, if any exist, is a separate operational decision.
- Changing the ordering of the nightly jobs (`InventoryValueScheduler`
  at 00:00 UTC vs. `UserInventorySyncScheduler` at 01:00 UTC). The
  snapshot continues to use the inventory composition as of the last
  sync.
- Any change to `InventoryValueRecordingService`'s "fully priced" gate.
- Any change to the controller's synchronous self-seed.
- Any `app_core` frontend change.
- Rewriting the historical
  `agent/plans/inventory-value-history.md` record. Its internal
  Scope/Implementation-Approach contradiction is resolved by this plan
  and by the corrected user story, not by editing the old record.

## Implementation Approach

The change stays inside the two files that already own the behavior; no
new class or layer is warranted (per
`agent/styleguides/fetcher/architecture-layers.md`, the scheduler keeps
doing a local query plus `.perform_async`, and the model owns only
schema/associations).

**Scheduler (`app_fetcher/app/schedulers/inventory_value_scheduler.rb`).**
Replace `InventoryValueLog.distinct.pluck(:steam_id)` with
`UserInventory.pluck(:steam_id)`. `user_inventories.steam_id` already has
a unique index, so no `distinct` is needed. Keep the existing
`InventoryValueUpdateWorker.perform_async` loop and `queue: :default`.
Add `retry: 3`, matching `UserInventorySyncScheduler` and
`PriceScheduler`.

Why this is safe: recomputing an existing day is already idempotent via
`upsert_all`; the service still skips inventories with an unpriced
marketable item; and the scheduler itself performs no external I/O.

**Model (`app_fetcher/app/models/user_inventory.rb`).** Extend the
association to:

`has_many :inventory_value_logs, foreign_key: :steam_id, primary_key: :steam_id, dependent: :delete_all`

`delete_all` (not `delete`) issues one `DELETE ... WHERE steam_id = ?`
for the association and is appropriate because `InventoryValueLog` has no
callbacks and no child associations. The association itself stays — it
is still used by
`Api::Admin::UserInventoriesController#show` to read the latest value.
This is a deliberate product decision: an inventory row represents the
user in `app_fetcher`, so removing it must remove their value history
too.

**Documentation.** `agent/US/dashboard-user-story.md` currently says the
controller enqueues a deduplicated worker and that the scheduler fans out
to `steam_id`s that already have a log. Neither matches the code: the
seed is synchronous, and after this change the fan-out covers every
`UserInventory`. Correct both passages so the living document describes
the implemented system, and note that the nightly run is the backstop for
a missed first seed.

## Files To Modify

- `app_fetcher/app/schedulers/inventory_value_scheduler.rb` — change
  the fan-out query to `UserInventory.pluck(:steam_id)`; add `retry: 3`.
  Reason: cover known inventories that have no log yet, and satisfy the
  explicit-retry rule.
- `app_fetcher/app/models/user_inventory.rb` — add
  `dependent: :delete_all` to `inventory_value_logs`. Reason: delete
  history with the inventory, no orphans.
- `app_fetcher/spec/schedulers/inventory_value_scheduler_spec.rb` —
  rewrite the contexts around `UserInventory` rather than
  `InventoryValueLog`; add the "inventory without a log" case and the
  legacy-orphan case. Reason: pin the new fan-out source.
- `app_fetcher/spec/models/user_inventory_spec.rb` — add a `#destroy`
  context asserting logs with the same `steam_id` are deleted and another
  `steam_id`'s logs are untouched. Reason: pin the cascade policy at the
  model boundary.
- `agent/US/dashboard-user-story.md` — correct the self-seed description
  (synchronous service call, no enqueue/dedup) and the scheduler
  description (every `UserInventory`, nightly backstop).
- `agent/styleguides/fix_me.md` — remove the
  `inventory_value_scheduler.rb` deviation entry now that `retry:` is
  added.

## Files To Create

None. Both behaviors already live in the existing scheduler and model;
a new service or class would add a layer without a second caller.

## Test Plan

**`app_fetcher/spec/schedulers/inventory_value_scheduler_spec.rb`**
(unit, `Sidekiq::Testing.fake!` is already global):

- `UserInventory` with no `InventoryValueLog` → enqueues exactly one job
  for its `steam_id`. This is the regression test for the reported gap.
- `UserInventory` with multiple historical logs → still exactly one job
  for that `steam_id` (no per-log duplication).
- No `UserInventory` and no logs → enqueues nothing.
- An `InventoryValueLog` with no matching `UserInventory` (legacy
  orphan) → enqueues nothing, pinning `UserInventory` as the single
  source of truth.

**`app_fetcher/spec/models/user_inventory_spec.rb`** (unit):

- Destroying a `UserInventory` deletes all `InventoryValueLog` rows with
  its `steam_id`.
- Destroying it leaves another `steam_id`'s logs intact.

**Existing coverage that must stay green (no edits expected):**

- `spec/workers/inventory_value_update_worker_spec.rb` — the service's
  write/skip behavior is unchanged.
- `spec/requests/api/v1/inventory_values_spec.rb` — the synchronous
  first-read seed and period filtering are unchanged.
- `spec/requests/api/admin/user_inventories_spec.rb` — inventory deletion
  still succeeds; the model spec covers the cascade itself, so the
  request spec is not duplicated.

## Implementation Steps

1. **RED — scheduler spec.** Rewrite
   `inventory_value_scheduler_spec.rb` so the primary fixture is a
   `UserInventory` with no log, plus the orphan-log and no-inventory
   cases. Run the spec and confirm it fails against the current
   `InventoryValueLog`-based query for the right reason.
2. **GREEN — scheduler.** Switch the query to `UserInventory.pluck` and
   add `retry: 3`. Re-run the scheduler spec.
3. **RED — model spec.** Add the destroy/cascade examples to
   `user_inventory_spec.rb`; run and confirm they fail without
   `dependent:`.
4. **GREEN — model.** Add `dependent: :delete_all`. Re-run the model
   spec.
5. **Docs.** Correct `agent/US/dashboard-user-story.md` (seed +
   scheduler paragraphs) and remove the `inventory_value_scheduler.rb`
   entry from `agent/styleguides/fix_me.md`.
6. **Regression.** Run the full `app_fetcher` RSpec suite and RuboCop on
   every touched Ruby file.

## Verification

- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle
  exec rspec spec/schedulers/inventory_value_scheduler_spec.rb
  spec/models/user_inventory_spec.rb"` — targeted specs.
- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle
  exec rspec"` — full `app_fetcher` suite (regression).
- `docker compose run --rm app_fetcher bash -c "bin/rubocop
  app/schedulers/inventory_value_scheduler.rb
  app/models/user_inventory.rb
  spec/schedulers/inventory_value_scheduler_spec.rb
  spec/models/user_inventory_spec.rb -f simple"` — style.
- `docker compose run --rm app_fetcher bash -c "bundle exec srb tc"` —
  no new type errors (the two touched files already have `typed:
  strict` sigils; no signature changes).
- No manual browser check is planned; the behavior is DB-only and fully
  observable through the specs.

This worktree has no `.env`, so `docker compose` currently refuses to
interpolate services. Before running the commands above, create a local
(gitignored) `.env` from `.env.example` with dummy secrets, then bring up
`db_fetcher` and `redis` only.

## Risks

- **Fan-out now writes rows for dormant users.** Previously only
  `steam_id`s that had already produced a snapshot received nightly
  writes. After the change, every known `UserInventory` accrues one row
  per day, including users who never reopen the dashboard. This is the
  intended backfill, but it is a small, permanent increase in write
  volume and table size. It does not add Steam calls or rate-limit
  pressure.
- **`dependent: :delete_all` is irreversible.** Admin deletion of an
  inventory now also destroys that user's value history. This is the
  confirmed product decision (inventory and user are the same entity in
  `app_fetcher`; only items are shared across users).
- **Legacy orphan logs are not cleaned up.** If any `InventoryValueLog`
  rows already exist without a `UserInventory`, this change simply stops
  fanning out for them; it does not delete them. A separate cleanup can
  be considered if such rows exist.
- **Nightly snapshot timing is unchanged and still precedes the sync.**
  The 00:00 UTC value run uses the inventory composition from the last
  `UserInventorySyncService` run (at most 7 days old by design), while
  the sync scheduler runs at 01:00 UTC. This change does not alter that
  accepted trade-off.

## Assumptions

- `user_inventories.steam_id` is unique at the database level (verified
  in `app_fetcher/db/schema.rb`), so `pluck` cannot produce duplicate
  `steam_id`s.
- `InventoryValueLog` has no callbacks or dependent associations, so
  `delete_all` is behaviorally equivalent to `destroy` here and cheaper.

## Applicable Styleguides

- `agent/styleguides/fetcher/background-jobs.md` — the scheduler stays a
  query-only Scenario 2 fan-out (no Steam call, no inline persistence),
  must declare `retry:` explicitly, and its spec is a unit spec using
  `Sidekiq::Testing.fake!` to assert one enqueued job per record.
- `agent/styleguides/fetcher/architecture-layers.md` — confirms the
  change stays inside the existing Scheduler → Worker edge; no new layer
  or service is introduced.
- `agent/styleguides/rails-layering.md` — `dependent:` belongs on the
  model association (models own schema/associations), and no
  orchestration logic moves into a callback.
- `agent/styleguides/rspec-conventions.md` — model and scheduler specs
  are unit specs (no `type:` metadata), use `FactoryBot` for test data,
  and follow arrange → act (`subject`) → assert with
  `aggregate_failures` for multi-expectation examples.
- `agent/adr/fetcher/rspec-testing-strategy.md` — confirms the
  scheduler/model spec levels and that the database is exercised for
  real, not stubbed.
- `agent/styleguides/ruby-sorbet.md` — both touched Ruby files are
  `typed: strict`; no signature changes are needed, and new/changed code
  stays within the existing sigs.
- `agent/styleguides/fix_me.md` — touching
  `inventory_value_scheduler.rb` obliges removing its known-deviation
  entry once `retry:` is added.
- `agent/styleguides/git-commits.md` — the implementation commit is
  single-app, so it uses the `[Fetcher]` scope tag.

## Completion Criteria

- [x] Desired behavior made explicit.
- [x] Scope explicit.
- [x] Affected files/components identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (`styleguides-check`).
- [x] Implemented (`implement-plan`).

# Implementation Summary

## Implemented

- `app_fetcher/app/schedulers/inventory_value_scheduler.rb` — fan-out
  source changed from `InventoryValueLog.distinct.pluck(:steam_id)` to
  `UserInventory.pluck(:steam_id)`; added `retry: 3` to
  `sidekiq_options`.
- `app_fetcher/app/models/user_inventory.rb` — added
  `dependent: :delete_all` to `has_many :inventory_value_logs`.
- `app_fetcher/spec/schedulers/inventory_value_scheduler_spec.rb` —
  contexts now keyed on `UserInventory`; added the "inventory without a
  log" regression case and the "orphan log without an inventory" case.
- `app_fetcher/spec/models/user_inventory_spec.rb` — added `#destroy`
  examples covering the cascade and confirming another `steam_id`'s logs
  are untouched.
- `agent/US/dashboard-user-story.md` — corrected the self-seed
  description (synchronous `InventoryValueRecordingService` call, no
  worker/dedup) and the scheduler description (every `UserInventory`,
  nightly backfill).
- `agent/styleguides/fix_me.md` — removed the now-fixed
  `inventory_value_scheduler.rb` retry entry.

## Tests

- `app_fetcher/spec/schedulers/inventory_value_scheduler_spec.rb` — 4
  examples (was 3).
- `app_fetcher/spec/models/user_inventory_spec.rb` — 2 new examples.

Commands actually executed (via `docker compose run --rm --no-deps
app_fetcher`):

```
RAILS_ENV=test bin/rails db:create db:schema:load
RAILS_ENV=test bundle exec rspec spec/schedulers/inventory_value_scheduler_spec.rb
RAILS_ENV=test bundle exec rspec spec/models/user_inventory_spec.rb
RAILS_ENV=test bundle exec rspec
bin/rubocop app/schedulers/inventory_value_scheduler.rb app/models/user_inventory.rb \
  spec/schedulers/inventory_value_scheduler_spec.rb spec/models/user_inventory_spec.rb -f simple
bundle exec srb tc
```

## Verification

- Targeted scheduler spec: RED first (2 failures — the no-log case
  enqueued nothing, the orphan-log case enqueued a job), then 4/4 green
  after the change.
- Targeted model spec: RED first (cascade example failed, the other
  `steam_id` example already passed), then 8/8 green after the change.
- Full `app_fetcher` suite: **405 examples, 0 failures**.
- RuboCop on all four touched Ruby files: **no offenses detected**.
- `srb tc`: **"No errors! Great job."**

## Deviations

- None from the implementation plan. Environment-only workaround for
  verification: this worktree had no `.env`, so a local (gitignored)
  `.env` was created from `.env.example` with dummy secrets; host port
  6380 was already taken by another compose project, so an ad-hoc
  `redis:7-alpine` container (`shiny-squid-redis-aux`, network alias
  `redis`) was attached to the compose network and test runs used
  `--no-deps` against the already-running `db_fetcher`. Neither artifact
  is tracked by git.

## Remaining Issues

- Legacy `InventoryValueLog` rows without a `UserInventory` (if any exist
  in an existing database) are not deleted by this change; they simply
  stop being included in the nightly fan-out. A one-off cleanup remains a
  separate operational decision, as planned.
- The local `.env` and the ad-hoc Redis container are environment
  artifacts only; they must not be committed or treated as part of the
  change.
