---
status: implemented
app: fetcher
goal: Stop a permanently-unpriceable marketable item from blocking a user's first InventoryValueLog snapshot forever, by recording on the item that Steam currently has no price for it and excluding it from the readiness gate
created: 2026-10-16
---

# Development Plan

## Goal

`InventoryValueRecordingService` (from
`agent/plans/portfolio-first-snapshot-race.md`) only writes a day's
`InventoryValueLog` once every `marketable` item of the inventory has a
price. That gate is correct for the transient case (`WARMUP_CAP`, hourly
`PriceScheduler`) but has no escape hatch for an item Steam reports as
having no price: `Steam::Client#perform_request` maps a `success: false`
price body to `status: 404`, and `PriceUpdateWorker` drops it — so
`current_price_cents` stays `nil` forever and the gate never opens. One
such item (a `marketable` item with no active market listings, e.g. a
just-released item, or one whose price endpoint keeps returning
`success: false`) blocks **the whole inventory's** snapshot, not just its
own contribution.

After this change, an item Steam reports as having no price is flagged on
the item itself and stops blocking the snapshot.

## Expected Behavior

**Normal behavior**

- When `PriceUpdateWorker` gets a response that is a **definitive** "no
  price" (`response.not_found?` — a `Steam::Response` predicate for
  `status == 404`, which the client produces from a `success: false`
  price body), it sets `item.price_unavailable = true`.
- The readiness gate treats a `marketable`, price-unavailable item as
  "done" (like a non-marketable one): it no longer blocks the day's
  snapshot. An inventory whose only unpriced marketable items are
  price-unavailable now gets its `InventoryValueLog` row, summing the
  priced items.
- When a price **does** arrive later (a successful fetch), the flag is
  cleared.

**Edge cases**

- **Transient** failure (`429` from `Prop`, network/`500`) must **not** set
  the flag — those keep blocking the snapshot until resolved, exactly as
  today.
- An inventory where an unpriced marketable item is neither priced nor
  flagged still returns `Skipped` (unchanged — the transient wait).
- A flagged item that later becomes priceable is re-attempted by the
  existing hourly `PriceScheduler` (see Decisions — `due_for_price_update`
  is unchanged), a successful fetch clears the flag, and it counts
  normally from then on. So the flag is self-healing.

**Failure behavior**

- Unchanged: `PriceUpdateWorker` still logs and returns without raising on
  any non-`success?` response.

**Must remain unchanged**

- `WARMUP_CAP`/`WARMUP_DEDUP_TTL` and the frontend warmup retry schedule.
- `Prop` rate-limit configuration.
- `PriceScheduler`, `due_for_price_update`, and `stale_or_unpriced` — the
  hourly refresh is the flag's healing mechanism (see Decisions).
- The dashboard "Estimating…" UX and the `ServiceResult` contract.
- `InventoryValueScheduler` (nightly fan-out) — unchanged.

## Scope

### In Scope

- New `items.price_unavailable` boolean column (default `false`, not null)
  — migration + schema. **No data migration/backfill**: the dev DB will be
  dropped and re-fetched from scratch.
- `Steam::Response#not_found?` (a `status == 404` predicate).
- `PriceUpdateWorker`: set the flag when `response.not_found?`.
- `PriceUpdateService`: clear the flag on a successful update.
- `InventoryValueRecordingService`: the readiness predicate ignores
  flagged items.
- Regenerate `sorbet/rbi/dsl/item.rbi` (new column, per
  `agent/styleguides/ruby-sorbet.md`).
- A `:price_unavailable` factory trait; specs for all of the above.

### Out of Scope

- A time-based retry window / excluding flagged items from
  `due_for_price_update` (a boolean can't express "retry after N"; the
  existing hourly refresh already re-attempts flagged items, so nothing is
  lost — see Decisions).
- Any change to the transient pricing paths: `WARMUP_CAP`, retry-on-`429`,
  or splitting the `Prop` `steam_price` bucket by traffic source.
- Backfilling/repairing already-unpriced items (dev DB reset).
- Frontend changes (the estimating state already resolves once the
  snapshot exists).
- A user-visible indicator of "some items could not be priced".

## Implementation Approach

### Decisions

1. **Storage: a boolean `items.price_unavailable` (default `false`, not
   null).** A simple "last known: Steam has no price for this" flag. No
   timestamp and no retry window — so it gates only the readiness check,
   not the scheduler.
2. **Healing via the existing hourly `PriceScheduler`; `due_for_price_update`
   is unchanged.** `stale_or_unpriced` already re-selects marketable items
   every hour (`updated_at < 1.hour.ago OR current_price_cents IS NULL`),
   so a flagged item keeps being re-attempted for free; the next successful
   fetch clears the flag. Excluding it from the scheduler would remove that
   healing and is deliberately not done. (Trade-off accepted: a flagged
   item still gets ~one failing Steam call per hour — the same order as the
   hourly refresh every other item already gets.)
3. **Detection via a `Steam::Response` predicate, not a raw status read.**
   `background-jobs.md` forbids HTTP-status branching inside a worker, so
   the distinction is exposed as `Steam::Response#not_found?`
   (`status == 404`) and the worker branches on
   `response.not_found?`. The client already maps a `success: false` price
   body to `status: 404`; a transient `Prop::RateLimited`/network failure
   maps to `429`/`500`. (A genuine HTTP 404 on this endpoint is not
   expected; if it occurred it would also count as unavailable — an
   acceptable, documented simplification.)

### Changes

- `Steam::Response`: add `#not_found?` (`status == 404`).
- `PriceUpdateWorker#perform`: in the existing `unless response.success?`
  branch, before logging/returning, set the flag when
  `response.not_found?` (`item.update!(price_unavailable: true)`); for any
  other non-success response, do nothing (transient).
- `PriceUpdateService#call`: add `price_unavailable: false` to the existing
  `item.update!(...)` so a success clears the flag.
- `InventoryValueRecordingService#unpriced_marketable?`: add
  `price_unavailable: false` to the `where`, so a flagged item no longer
  blocks.

## Files To Modify

- `app_fetcher/lib/steam/response.rb` — add `#not_found?`.
- `app_fetcher/app/workers/price_update_worker.rb` — set the flag on
  `response.not_found?`.
- `app_fetcher/app/services/price_update_service.rb` — clear the flag on
  success.
- `app_fetcher/app/services/inventory_value_recording_service.rb` — the
  readiness predicate ignores flagged items.
- `app_fetcher/db/schema.rb` — regenerated by the migration.
- `app_fetcher/sorbet/rbi/dsl/item.rbi` — regenerated (`tapioca dsl Item`)
  for the new column.
- `app_fetcher/spec/factories/items.rb` — add a `:price_unavailable` trait.
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — `not_found?`
  sets the flag; `429`/`500` do not; success clears it.
- `app_fetcher/spec/services/price_update_service_spec.rb` — success
  clears a prior flag.
- `app_fetcher/spec/services/inventory_value_recording_service_spec.rb` —
  a flagged marketable item does not block; an unmarked one still does.

## Files To Create

- `app_fetcher/db/migrate/<timestamp>_add_price_unavailable_to_items.rb` —
  `add_column :items, :price_unavailable, :boolean, default: false, null: false`.
- `app_fetcher/spec/lib/steam/response_spec.rb` — unit spec for
  `#not_found?` (no `response_spec` exists today).

## Test Plan

- **`response_spec.rb`** (unit): `#not_found?` is true for `status: 404`,
  false for `200`/`429`/`500`; `#success?` unchanged.
- **`price_update_worker_spec.rb`** (unit): a `success: false` price body
  (status `404`) sets `item.price_unavailable` and writes no `PriceLog`; a
  `429` response leaves the flag `false`; a successful fetch on an already
  flagged item clears it.
- **`price_update_service_spec.rb`** (unit): a successful `call` clears a
  pre-existing `price_unavailable`.
- **`inventory_value_recording_service_spec.rb`** (unit): an inventory
  with a priced item plus an unpriced but flagged `marketable` item → `Ok`
  + row (sum of the priced items); a priced item plus an unpriced unmarked
  `marketable` item → still `Skipped` (regression for the gate).
- **Regression**: the rest of `app_fetcher` (the recording service's other
  cases, `inventory_values` request spec, `inventory_detail_query_spec`,
  `price_scheduler_spec`).

## Implementation Steps

1. `app_fetcher`: add the migration; run it and `db:test:prepare`;
   regenerate `sorbet/rbi/dsl/item.rbi`.
2. `app_fetcher`: TDD `Steam::Response#not_found?` against the new
   `response_spec.rb`.
3. `app_fetcher`: add the `:price_unavailable` factory trait; TDD
   `PriceUpdateWorker`'s set-on-`not_found?` (and no-set-on-`429`) against
   `price_update_worker_spec.rb`.
4. `app_fetcher`: TDD `PriceUpdateService`'s clear-on-success against
   `price_update_service_spec.rb`.
5. `app_fetcher`: TDD the readiness predicate change against
   `inventory_value_recording_service_spec.rb`.
6. Full `app_fetcher` suite, RuboCop on touched files, `srb tc`.

## Verification

- `app_fetcher`: targeted specs, then the full RSpec suite.
- `bin/rubocop` on touched files; `srb tc` (confirm no new errors and the
  regenerated `item.rbi` resolves `price_unavailable`).
- DDL check: `bin/rails db:migrate` then confirm the column exists and
  `db/schema.rb` shows `price_unavailable` (default `false`, null: false);
  watch for an incidental `db/cache_schema.rb` change (revert if
  unrelated, as prior plans did).

## Risks

- **`Steam::Response#not_found?` (`status == 404`) is the proxy for
  "definitive no price."** It is correct for the `success: false` body the
  client produces; a genuine HTTP 404 would also match (not expected on
  this endpoint). Documented, not hedged further.
- **No evidence yet that this occurs in practice**: the dev DB currently
  has 0 unpriced items, so the failure mode is unobserved. The change is a
  robustness fix for "one weird item blocks the whole snapshot", not a fix
  for a reproduced bug — worth knowing if it's ever prioritized.
- **The flag is now a second source of truth about priceability** alongside
  `metadata.marketable`; they can disagree (that disagreement is the point).
  The flag only affects the readiness gate, never the displayed price.
- **Migration touches the shared `items` table**; the `tapioca dsl Item`
  regeneration is required under `typed: strict` and easy to forget —
  called out in the steps.
- **`db/cache_schema.rb` may normalize** as an incidental side effect of
  running migrations (same as the prior plan) — revert it if unrelated.

## Assumptions

- A real-world `marketable` item can trigger a `success: false` price
  response (no listings yet / delisted) — the case this plan exists for;
  the `marketable` flag comes from the inventory description, so the two
  genuinely can disagree.
- The dev database will be dropped and re-fetched, so no backfill of
  currently-unpriced items is needed.

## Applicable Styleguides

- `agent/styleguides/fetcher/steam-response-objects.md` — the
  `Steam::Response#not_found?` predicate and the "branch on a semantic
  predicate, never `#status`" rule the worker relies on (amended as part
  of this task).
- `agent/styleguides/fetcher/background-jobs.md` — the worker's
  set-flag-and-return shape on a non-`success?` response, and the MUST NOT
  on HTTP-status branching that forced the predicate route.
- `agent/styleguides/fetcher/services.md` — the readiness precondition
  lives in `InventoryValueRecordingService` (the gated write), returning
  `Skipped` when it is unmet.
- `agent/styleguides/fetcher/architecture-layers.md` — the
  worker/service/model layer boundaries the change stays inside of.
- `agent/styleguides/ruby-sorbet.md` — `T.let`, `typed: strict`, and the
  required `tapioca dsl Item` regeneration for the new column.
- `agent/styleguides/rails-layering.md` — the flag is a plain column; no
  orchestration moves onto the model.
- `agent/styleguides/rspec-conventions.md` +
  `agent/adr/fetcher/rspec-testing-strategy.md` — unit spec levels,
  `FactoryBot`.
- `agent/styleguides/git-commits.md` — `[Fetcher]`, and (with the amended
  styleguide) a task-scoped commit bundling the styleguide amendment.
- `agent/styleguides/ci-and-coverage.md`, `agent/styleguides/git-hooks.md`
  — how the verification commands are run.

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

- `db/migrate/20261016190000_add_price_unavailable_to_items.rb` +
  `db/schema.rb` — `items.price_unavailable` boolean, `default: false,
  null: false`. No backfill (dev DB to be reset).
- `lib/steam/response.rb` — `Steam::Response#not_found?` (`status == 404`).
- `app/workers/price_update_worker.rb` — on a non-`success?` response,
  `item.update!(price_unavailable: true) if response.not_found?` before
  the existing log-and-return (transient `429`/`500` leave the flag alone).
- `app/services/price_update_service.rb` — the success `item.update!(...)`
  now also sets `price_unavailable: false` (healing).
- `app/services/inventory_value_recording_service.rb` — the readiness
  predicate is now
  `items.marketable.where(current_price_cents: nil, price_unavailable: false)`,
  so a flagged item no longer blocks the snapshot.
- `sorbet/rbi/dsl/item.rbi` — regenerated (`tapioca dsl Item`) for the new
  column.
- `spec/factories/items.rb` — `:price_unavailable` trait.
- `agent/styleguides/fetcher/steam-response-objects.md` — amended (the
  `#not_found?` predicate + "branch on a predicate, never `#status`").

## Tests

- `spec/lib/steam/response_spec.rb` (new, 2 examples): `#success?` and
  `#not_found?` truth tables.
- `spec/workers/price_update_worker_spec.rb`: a `success: false` (404)
  response sets `price_unavailable`; a `429` leaves it `false`; a
  successful fetch on a flagged item clears it.
- `spec/services/price_update_service_spec.rb`: a success clears a prior
  `price_unavailable`.
- `spec/services/inventory_value_recording_service_spec.rb`: a priced item
  plus a flagged unpriced marketable item → `Ok` + row.

Commands executed (from the repo root):

```
docker compose run --rm -T app_fetcher bash -c "bin/rails db:migrate"
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bin/rails db:test:prepare"
docker compose run --rm -T app_fetcher bash -c "bundle exec tapioca dsl Item"
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"          # 389 examples, 0 failures
docker compose run --rm -T app_fetcher bash -c "bin/rubocop <touched files>"              # 10 files, no offenses
docker compose run --rm -T app_fetcher bash -c "bundle exec srb tc"                       # No errors
```

## Verification

- `app_fetcher` full suite: 389 examples, 0 failures.
- RuboCop: 10 touched/created files, 0 offenses.
- `srb tc`: "No errors! Great job." — the regenerated `item.rbi` resolves
  `price_unavailable`.
- `db/schema.rb` shows `price_unavailable` (default `false`, null: false);
  no incidental `db/cache_schema.rb` change.

## Deviations

- **Design changed from the plan's original draft**: the marker is a
  boolean `price_unavailable` (not a `price_unavailable_at` timestamp), and
  `Item#due_for_price_update` is **not** changed. Consequence: the
  time-based retry window is gone, but healing is preserved because the
  existing hourly `PriceScheduler` already re-attempts every flagged item
  (`stale_or_unpriced`), and a success clears the flag. Directly per the
  user's instruction ("поле пускай будет булиновое price_unavailable").

## Remaining Issues

- The edge case is a robustness fix and is **unobserved in the current
  data** (dev DB had 0 unpriced items) — see the plan's Risks.
- A flagged item still gets ~one failing Steam call per hour (the same
  hourly refresh every other item gets); excluding it would lose the
  healing, so it was left as-is.
- Manual verification (a real `success: false` item unblocking a snapshot)
  not performed — no such item was available to reproduce with.
