---
status: implemented
app: fetcher+core
goal: Stop a brand-new user's portfolio value from being written (and thereafter shown) as 0 by gating the first InventoryValueLog row on every marketable item being priced, and show an "estimating" state with the live partial sum on the dashboard until then
created: 2026-10-16
---

# Development Plan

## Goal

Fix the race that makes a freshly-registered user's portfolio value show
`$0.00`: today the daily `InventoryValueLog` row is written from an
incomplete state (either before `UserInventory` exists, or before any of
the user's items have a price), and once written it is never corrected, so
both the dashboard hero (`PortfolioTile`) and the public inventory detail
hero (`InventoryDetailQuery#total_value_cents`) keep rendering the stale
zero even after prices arrive.

After this change:

- `InventoryValueLog` is only written once the inventory is
  **fully priced** — i.e. no `marketable` item of that inventory still has
  `current_price_cents: nil`. `non-marketable` items (which never get a
  price) do not block it.
- While an inventory is not yet fully priced, the dashboard shows an
  "estimating" state on the portfolio hero plus the **live partial sum** of
  the prices it already has (computed on the client, not read from
  `InventoryValueLog`), instead of a misleading `$0.00`.
- As soon as the inventory becomes fully priced, the dashboard re-fetches
  `/api/v1/inventory_values`, the self-seed writes the first (now correct)
  row, and the hero switches to the real value.

## Expected Behavior

**Normal behavior**

- New user, first dashboard load, prices not yet available: the split
  layout renders normally; the portfolio hero shows the sum of the priced
  items so far as its value (e.g. "$12.34") with a small muted
  "Estimating…" caption (a placeholder block instead of a number when
  nothing is priced yet), and no delta badge.
- Once every `marketable` item of the inventory has a price: the
  dashboard re-fetches `/api/v1/inventory_values`; the controller's
  self-seed now passes the gate, writes today's row with the full sum, and
  returns it; the hero shows the real value and a delta.
- Returning user (inventory already fully priced): unchanged — the first
  `/api/v1/inventory_values` request self-seeds/returns the stored row
  immediately.

**Edge cases**

- Inventory synced but with zero items: considered fully priced; a
  `total_value_cents: 0` row is written (unchanged from today), hero shows
  `$0.00`.
- Inventory where every owned item is `non-marketable`: considered fully
  priced (no `marketable` item can be unpriced); a `0` row is written;
  hero shows `$0.00` — this is a genuine zero, not "estimating".
- `/api/v1/inventory_values` requested before the inventory has been
  synced (no `UserInventory` row): nothing is written, an empty array is
  returned; the client shows the estimating state and re-fetches.
- An inventory with at least one `marketable` item that never gets a price
  (Steam permanently fails for it): the gate never opens, so no snapshot is
  written and the dashboard stays in the estimating state showing the
  partial sum. Accepted (see Risks) — a partial sum is still shown, so the
  user is not left staring at a blank tile.
- Item mode of `PortfolioTile` is unaffected.

**Failure behavior**

- If prices never complete in a session, the dashboard keeps showing the
  estimating state with whatever partial sum exists; it does not fall back
  to `$0.00` and does not poll forever (bounded by `useItemPrices`'s
  existing 5-attempt schedule).
- A failed `/api/v1/inventory_values` fetch keeps today's existing
  `status: 'error'` behavior.

**Must remain unchanged**

- `WARMUP_CAP` (20) and `WARMUP_DEDUP_TTL` (90s) in
  `Api::V1::ItemPricesController` — explicitly out of scope (decision
  below).
- `Steam::Client` / `Prop` rate-limit configuration.
- `PriceUpdateWorker`'s success path (Steam call → `PriceLog` + `Item`
  update → three cache invalidations) — behaviorally unchanged; only how it
  reads `PriceUpdateService`'s result changes.
- `InventoryCatalogQuery` — already computes `total_value_cents` as a live
  `SUM(items.current_price_cents)`, so the public list page is already
  correct and needs no change.
- `InventoryValueScheduler`'s fan-out query (existing-row owners only),
  including its missing explicit `retry:` (tracked separately in
  `fix_me.md`; not touched here).

## Scope

### In Scope

- `app_fetcher`: introduce the shared `ServiceResult[Payload]` contract
  (`app/services/service_result.rb`) and migrate all three services
  (`UserInventorySyncService`, `PriceUpdateService`,
  `InventoryValueRecordingService`) and their callers to it, per
  `agent/styleguides/fetcher/services.md` and
  `agent/adr/fetcher/service-result-contract.md`.
- `app_fetcher`: gate `InventoryValueRecordingService` so it writes only
  when the inventory is fully priced (and only when a `UserInventory`
  exists), returning `ServiceResult::Skipped` when it does not write.
- `app_fetcher`: update the service/worker/request specs to cover the gate
  and the new result contract at every call site.
- `app_core`: expose `marketable` on the mapped dashboard items.
- `app_core`: a small pure `utils/` module deriving "fully priced?" and the
  priced partial sum from the already-fetched items + prices.
- `app_core`: make `usePortfolioHistory` re-fetch when the "fully priced"
  state flips.
- `app_core`: render the estimating state (indicator + partial sum, no
  delta) on `PortfolioTile`'s portfolio hero instead of `$0.00`.
- Tests for all of the above.

### Out of Scope

- Raising/removing `WARMUP_CAP` or `WARMUP_DEDUP_TTL` (decision: keep the
  cap; see Implementation Approach → Decisions).
- Making throttled `PriceUpdateWorker` runs retryable
  (retry-on-`429`). Not required while the cap stays: the hourly
  `PriceScheduler` still eventually prices the rest; the gate simply waits.
  Flagged as a follow-up (Risks).
- Splitting the `Prop` `steam_price` rate-limit bucket by traffic source
  (the deferred idea in `agent/adr/fetcher/price-cache-invalidation.md`).
- Any change to `InventoryDetailQuery`'s `logs.last || live_sum` logic: once
  the gate guarantees stored rows are complete, "a row exists" is once
  again a reliable signal, and the existing live-sum fallback already
  covers the no-row case.
- Backfilling/repairing existing bogus zero rows: the local DB will be
  wiped and the account re-registered during verification.
- Touching `fix_me.md`'s `inventory_value_scheduler.rb` `retry:` entry
  (file not otherwise modified by this plan).
- Any new `app_core` → `app_fetcher` backend call.

## Implementation Approach

### Decisions (resolving the research Open Questions)

1. **Who re-triggers the snapshot after prices land.** The existing
   self-seed in `Api::V1::InventoryValuesController#index` already
   re-attempts on *every* request while the `steam_id` has zero log rows.
   With the gate, "zero rows" stays true until the inventory is fully
   priced, so the request path self-heals with no new trigger. The client's
   re-fetch on the readiness flip is what makes this happen without the
   user manually reloading. No new worker/fan-out is introduced.
2. **Retry-on-throttle: out of scope** (cap stays 20, so the existing
   hourly `PriceScheduler` remains the backstop). See Risks.
3. **The read path needs no "today is live" change.** The gate makes every
   stored row a *complete* value, so `logs.last` is trustworthy again, and
   the no-row case already falls back to the live sum in
   `InventoryDetailQuery`. The dashboard's partial sum is computed purely
   client-side from prices (per the user's requirement: "без
   портфолио-логов").
4. **Readiness is always scoped to `marketable`.** Non-marketable items are
   never priced, so any "all names priced" definition (including
   `useItemPrices`'s current coverage check) would never converge.
5. **Keep `WARMUP_CAP` at 20.** It exists to bound a request's impact on
   the shared `steam_price_rpm` budget (ADR constraint) and — because
   throttled worker runs are silently dropped — removing it would waste
   jobs rather than speed anything up.

### Backend (`app_fetcher`)

**Uniform `ServiceResult` contract first.** Adopt the shared result object
from `agent/adr/fetcher/service-result-contract.md` /
`agent/styleguides/fetcher/services.md`: every `app/services/` `.call`
returns `ServiceResult[Payload]` (`Status` = `Ok`/`Skipped`/`Failed`). This
is a cross-cutting refactor of all three services, required because the
gate introduces a third outcome — "deliberately did nothing" — that the
layer's current per-service shapes cannot express:

- `UserInventorySyncService`: drop the nested `Result` struct; return
  `Failed(error:)` on a Steam failure, `Ok(data: <items>)` otherwise.
  Callers `InventoriesController#render_resolved` and
  `UserInventorySyncWorker` switch to `result.success?` / `result.data` /
  `result.error`.
- `PriceUpdateService`: return `Ok(data: <the updated Item>)`; its caller
  `PriceUpdateWorker` reads `result.data` instead of the mutated argument.
- `InventoryValueRecordingService`: gate + result (below).

**The readiness gate.** `InventoryValueRecordingService.call` checks before
the `upsert_all`:

- look up `UserInventory` by `steam_id`; if absent, write nothing and
  return `Skipped` (kills the "self-seed raced ahead of the inventory sync"
  sub-case directly — today this path writes `0`);
- otherwise, if any of the inventory's `marketable` items still has
  `current_price_cents: nil` (`user_inventory.items.marketable.where(
  current_price_cents: nil).exists?`), write nothing and return `Skipped`;
- otherwise compute the sum as today, upsert, and return
  `Ok(data: <the log>)`.

Callers branch on the outcome (`success?`/`skipped?`), never on
`data.nil?`. The controller's existing "re-read logs after the call"
already renders the `Skipped` case correctly (an empty list); the worker
simply does nothing more.

The nightly `InventoryValueScheduler` → `InventoryValueUpdateWorker` path
goes through the same service, so it too stops writing partial rows (a
partially-priced existing user simply gets a gap that night rather than a
bogus value, per Expected Behavior).

### Frontend (`app_core`)

- `useDashboardData.mapItem`: carry `metadata.marketable` through as
  `marketable` (it is already present in the `/inventories/me` payload's
  `metadata`; only the mapper drops it today).
- New pure module `app/frontend/dashboard/utils/valuation.js`:
  - `isFullyPriced(items)` — `true` when the inventory has no `marketable`
    item lacking a `currentPriceCents`; also `true` for an empty item list
    (mirrors the backend's zero-item rule). Items here are the merged
    items carrying `currentPriceCents` from `useItemPrices`.
  - `pricedTotalCents(items)` — sum of `currentPriceCents` over items that
    have one (the "partial sum so far").
  Kept pure and unit-tested, per `agent/styleguides/core/react-dashboard.md`'s
  "derived data lives in `utils/`" rule.
- `usePortfolioHistory(fetcherUrl, bridgeToken, period, refreshKey)` — add
  a `refreshKey` argument folded into the effect's dependency list, so the
  caller can force a re-fetch (passing e.g. `'ready'`/`'pending'`). Existing
  callers/tests pass a constant and are unaffected semantically.
- `Dashboard.jsx`: compute `items` as today, then derive `fullyPriced` and
  `pricedTotalCents`; pass `fullyPriced` as the `refreshKey` to
  `usePortfolioHistory`; pass an estimating signal + the partial sum to
  `PortfolioTile`.
- `PortfolioTile.jsx`: in portfolio mode, when `portfolioSeries` is empty
  **and** the inventory is not yet fully priced, show the partial sum as
  the hero value with a small muted "Estimating…" caption (a
  `.hero-value-skeleton` placeholder when nothing is priced) —
  and suppress the delta badge. When the series is empty but the inventory
  *is* fully priced (genuinely-zero inventory), keep today's `$0.00`
  rendering. Item mode is untouched.

## Files To Modify

- `app_fetcher/app/services/inventory_value_recording_service.rb` — add the
  readiness guard (no `UserInventory` → skip; unpriced `marketable` item →
  skip); return `ServiceResult[InventoryValueLog]` (`Skipped`/`Ok`).
- `app_fetcher/app/services/user_inventory_sync_service.rb` — drop the
  nested `Result` struct; return `ServiceResult[T::Array[Item]]`
  (`Failed`/`Ok`).
- `app_fetcher/app/services/price_update_service.rb` — return
  `ServiceResult[Item]` (`Ok`); stop relying on in-place mutation.
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb` —
  `render_resolved` switches to `result.success?` / `result.data`.
- `app_fetcher/app/workers/user_inventory_sync_worker.rb` — branch on
  `result.success?` / `result.error`.
- `app_fetcher/app/workers/price_update_worker.rb` — read `result.data`
  instead of the mutated `item`.
- `app_fetcher/spec/services/inventory_value_recording_service_spec.rb` —
  replace the "unpriced item counts as 0" expectation with a `Skipped` /
  writes-nothing case; add a non-marketable-unpriced → `Ok` case; add a
  no-`UserInventory` → `Skipped` case.
- `app_fetcher/spec/services/user_inventory_sync_service_spec.rb`,
  `app_fetcher/spec/workers/user_inventory_sync_worker_spec.rb`,
  `app_fetcher/spec/workers/price_update_worker_spec.rb`,
  `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — update the
  assertions that read the old `result.success`/`result.items` shape or the
  `PriceUpdateService.call` return.
- `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb` — update the
  zero-entries self-seed context: not-fully-priced → empty array and no
  row; fully priced → writes and returns today's row.
- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb` — add a
  not-fully-priced → no-row case (existing cases already use priced items
  and stay green).
- `app_core/app/frontend/dashboard/hooks/useDashboardData.js` — map
  `marketable` from `metadata`.
- `app_core/app/frontend/dashboard/hooks/usePortfolioHistory.js` — add the
  `refreshKey` dependency.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — derive/thread
  `fullyPriced` and the partial sum.
- `app_core/app/frontend/dashboard/components/PortfolioTile.jsx` — render
  the estimating state in portfolio mode.
- `app_core/app/frontend/dashboard/__tests__/useDashboardData.test.js` —
  assert `marketable` on mapped items.
- `app_core/app/frontend/dashboard/__tests__/usePortfolioHistory.test.js` —
  assert the `refreshKey` change triggers a re-fetch.
- `app_core/app/frontend/dashboard/__tests__/PortfolioTile.test.jsx` —
  update the current "shows a zero value when no points" case to the
  estimating state, and add the fully-priced-genuinely-zero case.

## Files To Create

- `app_fetcher/app/services/service_result.rb` — the shared
  `ServiceResult[Payload]` value object (`Status` enum `Ok`/`Skipped`/
  `Failed`, `data`/`error`, `success?`/`skipped?`/`failed?`), per
  `agent/adr/fetcher/service-result-contract.md`.
- `app_fetcher/spec/services/service_result_spec.rb` — unit tests for the
  three predicates and their construction.
- `app_core/app/frontend/dashboard/utils/valuation.js` — `isFullyPriced` /
  `pricedTotalCents`, pure derived-data helpers per the React styleguide.
- `app_core/app/frontend/dashboard/__tests__/valuation.test.js` — unit
  tests for the two helpers.

## Test Plan

- **`service_result_spec.rb`** (unit): `ServiceResult[...].new` with each
  status; `success?`/`skipped?`/`failed?` return the right boolean per
  status.
- **`user_inventory_sync_service_spec.rb`** (unit): a failed Steam response
  → `failed?` with the error; success → `success?` with the items in
  `data` (replaces assertions on the old nested `success`/`items`).
- **`price_update_worker_spec.rb`** (unit): the worker still writes the
  `PriceLog`/`Item` fields and publishes to the stream, now reading the
  updated `Item` from the `ServiceResult` — same behavior asserted through
  `result.data` instead of the mutated argument.
- **`inventory_value_recording_service_spec.rb`** (unit): fully-priced
  inventory → `Ok` with the log and the summed total (existing cases stay,
  re-pointed at `result.data`); inventory with an unpriced `marketable`
  item → `skipped?`, **no** `InventoryValueLog` row for today; inventory
  with an unpriced `non_marketable` item (plus priced items) → `Ok`, row
  written with the priced sum; no `UserInventory` row → `skipped?`, no log
  row; an existing row updates in place when the inventory is fully priced.
- **`inventory_values_spec.rb`** (request): existing-entries → unchanged;
  zero entries + not-fully-priced → `[]` returned and no row created;
  zero entries + fully priced → today's row created and returned.
- **`inventory_value_update_worker_spec.rb`** (unit): not-fully-priced →
  no row written.
- **`valuation.test.js`** (unit): empty list → fully priced, total `0`;
  all-marketable-priced → fully priced, correct total; a `marketable` item
  without a price → not fully priced, total excludes it; an unpriced
  `non-marketable` item → still fully priced; mixed list → total is the sum
  of the priced ones only.
- **`usePortfolioHistory.test.js`** (unit): changing `refreshKey` triggers
  exactly one additional fetch; unchanged otherwise.
- **`useDashboardData.test.js`** (extended): mapped items expose
  `marketable` from `metadata`.
- **`PortfolioTile.test.jsx`** (updated): portfolio mode, empty series,
  not-fully-priced → estimating indicator shown, partial sum shown, no
  delta, no `$0.00`; portfolio mode, empty series, fully priced → `$0.00`
  (regression); existing non-empty-series cases unchanged.
- **Regression**: `useItemPrices.test.js`, `inventory_detail_query_spec.rb`
  (unchanged logic), `inventory_catalog_*` — run to confirm no fallout.

## Implementation Steps

1. `app_fetcher`: TDD `ServiceResult` against a new
   `service_result_spec.rb`.
2. `app_fetcher`: migrate `UserInventorySyncService` /
   `PriceUpdateService` and their callers (`InventoriesController`,
   `UserInventorySyncWorker`, `PriceUpdateWorker`) to `ServiceResult`,
   updating the affected specs — a pure return-shape change, no behavior
   change.
3. `app_fetcher`: TDD the `InventoryValueRecordingService` gate + result
   (`Skipped` / `Ok`) against its spec (unpriced-marketable → `Skipped`;
   non-marketable → `Ok`; no-inventory → `Skipped`), then wire the guard;
   update `inventory_values_spec.rb` and
   `inventory_value_update_worker_spec.rb`.
4. `app_core`: TDD `utils/valuation.js` against a new `valuation.test.js`.
5. `app_core`: extend `useDashboardData.test.js` and map `marketable` in
   `useDashboardData.js`.
6. `app_core`: TDD the `refreshKey` re-fetch in
   `usePortfolioHistory.test.js`, then add the dependency.
7. `app_core`: update `PortfolioTile.test.jsx` for the estimating/zero
   split (write the estimating case first, confirm it fails against the
   current `$0.00` code), then implement the tile change.
8. `app_core`: wire `Dashboard.jsx` — derive `fullyPriced`/partial sum,
   pass `refreshKey`, thread the props to `PortfolioTile`.
9. Full suites in both apps; then manual verification against a wiped local
   DB and a fresh registration.

## Verification

- `app_fetcher`: targeted specs for the touched files, then the full RSpec
  suite (regression).
- `app_core`: targeted Vitest files (`valuation.test.js`,
  `usePortfolioHistory.test.js`, `useDashboardData.test.js`,
  `PortfolioTile.test.jsx`), then the full frontend suite; plus `app_core`'s
  RSpec suite for any request-spec fallout.
- `bin/rubocop` in both apps for touched Ruby files; `srb tc` in
  `app_fetcher` (accounting for the documented pre-existing baseline).
- Manual: wipe the local DB, register a fresh account, load the dashboard,
  confirm the hero shows the estimating state + partial sum, then flips to
  the real value once prices land, and that exactly one
  `inventory_value_logs` row exists for today with a non-zero value.

## Risks

- **The gate may not converge quickly for inventories with many unpriced
  marketable items.** `WARMUP_CAP` (20/request) plus the shared
  `steam_price_rpm` (20/min) and the silent drop of throttled
  `PriceUpdateWorker` runs mean completion is paced by `PriceScheduler`'s
  hourly passes after the in-session warmup. The user has explicitly
  accepted this ("пускай ждут"); the estimating state means the wait is
  visible and shows a partial sum rather than nothing. If this proves
  annoying, the follow-up is making throttled `PriceUpdateWorker` runs
  re-enqueue with backoff (out of scope here).
- **A permanently-unpriceable `marketable` item blocks the snapshot
  forever** for that inventory. This follows directly from the chosen
  "wait for all marketable" rule. The dashboard still shows the partial
  sum, so the impact is "no history point" rather than "blank tile".
- **Two sources of the readiness definition** (backend
  `marketable.where(current_price_cents: nil).exists?` vs. the frontend's
  `isFullyPriced`) could drift if the definition of "marketable" or the
  `/inventories/me` payload changes. Kept consistent by deriving both from
  the same `metadata.marketable` flag; a comment referencing the backend
  predicate should be left in `valuation.js`.
- **Frontend readiness is only as fresh as `useItemPrices`.** It stops
  after 5 attempts, so for a slow/large inventory the session may end
  while still "estimating"; the next reload re-attempts. Accepted.
- **`usePortfolioHistory`'s new parameter** changes a hook signature;
  its single production caller is `Dashboard.jsx` and its test, both
  updated here.
- **The `ServiceResult` migration reaches beyond the bug's blast radius** —
  it also touches `UserInventorySyncService`/`PriceUpdateService` and their
  callers. This is deliberate (settled in
  `agent/adr/fetcher/service-result-contract.md`), and the change is
  return-shape-only with no behavior change, but it widens the diff and the
  set of specs to re-run; a mistake there would be silent (the old
  `result.success`/`result.items` readers no longer exist). Run the full
  `app_fetcher` suite, not just the gate specs, to catch missed call sites.

## Assumptions

- `metadata.marketable` is present and boolean on every item returned by
  `GET /api/v1/inventories/me` (confirmed for items created by
  `ItemParser.parse`; the endpoint returns `metadata` verbatim).
- The user-facing "estimating" copy ("Estimating…") is illustrative; the
  exact wording is not a design constraint. (All user-facing copy is in
  English — the app has no Russian localization.)
- Wiping the local DB and re-registering is acceptable for verification,
  so no data migration/repair is needed (user's explicit decision).

## Applicable Styleguides

- `agent/styleguides/fetcher/services.md` — governs the whole backend
  change: the single `.call` entry point, the uniform
  `ServiceResult[Payload]` return (`Ok`/`Skipped`/`Failed`), "branch on
  outcome, never on `data.nil?`", the precondition-lives-in-the-service
  rule, and the requirement to test every `Skipped` branch. Its backing ADR
  `agent/adr/fetcher/service-result-contract.md` is the "why".
- `agent/styleguides/fetcher/architecture-layers.md` — the layer map and
  call-site rules the migrated services and their Scenario-1/Scenario-3
  callers must stay inside of; also updated here to reflect the new
  return contract and the gated recording service.
- `agent/styleguides/fetcher/background-jobs.md` — constrains
  `InventoryValueUpdateWorker` (unchanged behavior, DB-only, explicit
  `retry:`), `PriceUpdateWorker` (now reads `result.data`), and
  `UserInventorySyncWorker` (branches on `result.success?`/`result.error`);
  the guard-and-log failure shape still applies.
- `agent/styleguides/fetcher/internal-api-controllers.md` —
  `Api::V1::InventoryValuesController#index`'s self-seed stays a single
  collaborator call; `InventoriesController#render_resolved`'s new
  `result.success?`/`result.data` branch keeps the action thin.
- `agent/styleguides/fetcher/caching.md` — the self-seed reuses the
  existing Warmup/Dedup pattern unchanged; the cap/dedup numbers are
  deliberately untouched.
- `agent/styleguides/rails-layering.md` — the Controller → service →
  Models direction and "models are persistence + validations only"; the
  readiness predicate stays in the service, not on a model.
- `agent/styleguides/ruby-sorbet.md` — `T::Enum` for the `Status` tag set,
  `T.nilable`, `T.let`, `typed: strict` + `sig` on the new files.
- `agent/styleguides/rspec-conventions.md` +
  `agent/adr/fetcher/rspec-testing-strategy.md` — spec levels (unit for
  services/workers, request for controllers), `FactoryBot`,
  `Sidekiq::Testing.fake!`.
- `agent/styleguides/core/react-dashboard.md` — the frontend work:
  derived data in `utils/`, the extra status/readiness signal alongside
  `status`, the hook-per-need + `refreshKey` shape, and the
  component-test conventions.
- `agent/styleguides/core/architecture-layers.md` — the dashboard island
  keeps reading `app_fetcher` directly (no `app_core` proxy) for the
  `marketable` mapping and the readiness derivation.
- `agent/styleguides/git-commits.md` — the change touches both apps →
  `[Core+Fetcher]`.
- `agent/styleguides/ci-and-coverage.md`, `agent/styleguides/git-hooks.md`
  — how the verification commands are run for both apps.

## Completion Criteria

- [x] Desired behavior made explicit (gate + estimating UI).
- [x] Scope explicit (cap/retry-on-throttle/read-path changes excluded).
- [x] Affected files/components identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined (includes a fresh-registration manual check).
- [x] Plan checked against styleguides (`styleguides-check`).
- [x] Implemented (`implement-plan`).

# Implementation Summary

## Implemented

**`app_fetcher` — shared `ServiceResult` contract**
(`agent/adr/fetcher/service-result-contract.md`):

- `app/services/service_result.rb` (new): `ServiceResult < T::Struct`
  with `extend T::Generic` + `Payload = type_member`, a `Status` `T::Enum`
  (`Ok`/`Skipped`/`Failed`), `data`/`error`, and the
  `success?`/`skipped?`/`failed?` predicates — modeled on `Steam::Response`.
- `UserInventorySyncService`: nested `Result` removed; returns
  `ServiceResult[T::Array[Item]]` (`Failed(error:)` on a Steam failure,
  `Ok(data:)` otherwise). Callers updated:
  `Api::V1::InventoriesController#render_resolved`,
  `Api::Admin::UserInventoriesController#sync`,
  `UserInventorySyncWorker`.
- `PriceUpdateService`: returns `ServiceResult[Item]` (`Ok(data: <item>)`);
  `PriceUpdateWorker` now reads `result.data` instead of the mutated
  argument.
- `InventoryValueRecordingService`: readiness gate — returns `Skipped`
  (writing nothing) when there is no `UserInventory` row or any
  `marketable` item still has `current_price_cents: nil`; otherwise
  upserts today's row and returns `Ok(data: <the log>)`. The
  `UserInventory.find_by` nil case now skips instead of writing a `0`.

**`app_core` — estimating UX:**

- `hooks/useDashboardData.js`: `mapItem` now carries `metadata.marketable`.
- `utils/valuation.js` (new): `isFullyPriced(items)` /
  `pricedTotalCents(items)` — pure, null/empty-safe, mirroring the
  backend predicate.
- `hooks/usePortfolioHistory.js`: new `refreshKey` dependency, so the
  caller can force a re-fetch.
- `components/PortfolioTile.jsx`: in portfolio mode, an empty series with
  `isEstimating` shows the partial sum as the hero value (a real number,
  hero styling) with a small muted `Estimating…` caption, and a
  `.hero-value-skeleton` placeholder instead when nothing is priced yet;
  no delta either way. A genuinely-zero (fully-priced, empty) inventory
  keeps the existing `$0.00`. Item mode unchanged.
- `shared/styles/tokens.css`: `.hero-estimating` (small mono `--text-faint`
  caption) and `.hero-value-skeleton` (muted placeholder block sized to
  the hero value, incl. the mobile breakpoint).
- `Dashboard.jsx`: derives `fullyPriced`/`estimatedValueCents`, feeds
  `fullyPriced` into `usePortfolioHistory`'s `refreshKey`, and threads the
  two props to `PortfolioTile`.

## Tests

- `app_fetcher/spec/services/service_result_spec.rb` (new, 3 examples):
  the three predicates + payload/error per status.
- `app_fetcher/spec/services/user_inventory_sync_service_spec.rb`:
  re-pointed at `success?`/`data`/`failed?`.
- `app_fetcher/spec/services/price_update_service_spec.rb`: +1 example
  asserting the `Ok` result carries the updated `Item`.
- `app_fetcher/spec/services/inventory_value_recording_service_spec.rb`
  (rewritten): fully-priced → `Ok` + row; unpriced marketable → `Skipped`,
  no row; unpriced non-marketable → `Ok` (sums priced only);
  no `UserInventory` → `Skipped`, no row; existing row updates in place.
- `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb`:
  not-fully-priced and no-inventory → no row.
- `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb`: +1 example
  — not-fully-priced self-seed returns `[]` and writes nothing.
- `app_core/.../__tests__/valuation.test.js` (new, 6 examples);
  `useDashboardData.test.js` (+`marketable`); `usePortfolioHistory.test.js`
  (+refreshKey re-fetch); `PortfolioTile.test.jsx` (+estimating cases).

Commands executed (all from the repo root):

```
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"           # 384 examples, 0 failures
docker compose run --rm -T app_fetcher bash -c "bundle exec srb tc"                        # No errors
docker compose run --rm -T app_fetcher bash -c "bin/rubocop <touched files> -f simple"     # no offenses
docker compose run --rm -T app_core bash -c "npm test"                                     # 228 passed
docker compose run --rm -T app_core bash -c "RAILS_ENV=test bundle exec rspec"             # 39 examples, 0 failures
docker compose run --rm -T app_core bash -c "npx prettier --check <changed files>"         # clean
docker compose run --rm -T app_core bash -c "npx eslint app/frontend/dashboard"            # clean
```

## Verification

- **`app_fetcher` RSpec**: full suite 384 examples, 0 failures.
- **`srb tc`**: "No errors! Great job." — no new (or existing) type errors.
- **RuboCop**: 14 touched/created files, 0 offenses.
- **`app_core` Vitest**: full suite 228 examples, 40 files, all passing.
- **`app_core` RSpec**: 39 examples, 0 failures.
- **Prettier/ESLint**: every new/changed frontend file passes both.
- **Manual check**: not performed live — same environment limitation noted
  in prior plans (needs a live Steam OpenID login + the full stack). The
  specs exercise the same state machine a real session drives.

## Deviations

- **`npm test` / lint / format ran in `app_core` but not both apps' full
  `bin/ci`.** `app_fetcher/bin/ci` is `LoadError`-broken (pre-existing,
  tracked in `fix_me.md`), so the individual commands above were used —
  matching the prior plans' approach.
- **`fix_me.md` gained a new entry** for
  `app_core/app/frontend/inventories/InventoriesIndex.jsx` failing
  `prettier --check` — a pre-existing formatting deviation on an
  unrelated file (left unfixed to keep this change's diff focused).

## Remaining Issues

- Manual browser verification (estimating → real value transition on a
  fresh registration) was not run here; recommended against the local
  stack as the plan's Verification section describes.
- The accepted trade-offs stand: a permanently-unpriceable `marketable`
  item blocks that inventory's first snapshot (dashboard still shows the
  partial sum); readiness is only as fresh as `useItemPrices`'s bounded
  retry schedule.
- Retry-on-`429` for throttled `PriceUpdateWorker` runs and splitting the
  `Prop` `steam_price` budget by traffic source remain explicit follow-ups
  (out of scope).
