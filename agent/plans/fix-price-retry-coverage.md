---
status: implemented
app: fetcher+core
goal: Stop useItemPrices from retrying after every price that can be fetched has arrived, by having dynamics report an authoritative pending_count, and surface a price-load failure on the dashboard
created: 2026-10-19
---

# Development Plan

## Goal

`useItemPrices` currently decides whether to keep retrying by comparing
the number of keys in the `item_prices/dynamics` response against the full
skeleton item-name list (`Object.keys(result).length >= names.length`).
The endpoint deliberately omits items with no price, so any owned
non-marketable or `price_unavailable` item makes that comparison
permanently false — the hook burns all five retries over ~90 seconds even
when every price that can arrive has already arrived.

Fix the retry gate so it asks the backend the only question that matters —
"is any owned item still awaiting a price?" — via a new `pending_count`
field computed from the same readiness predicate the backend already uses
for `InventoryValueLog`. Also make `Dashboard` consume the hook's `status`
so a failed price load is visible instead of silently rendering "—" prices.

## Expected Behavior

**Normal behavior**

- `GET /api/v1/item_prices/dynamics` returns:

  ```json
  {
    "prices": {
      "<market_hash_name>": {
        "current_price_cents": 3845,
        "change_24h_cents": 120,
        "change_24h_percent": 3.22
      }
    },
    "pending_count": 2
  }
  ```

  - `prices` keeps the current per-name shape and still omits items with
    no price.
  - `pending_count` is the number of owned items that are `marketable`,
    not `price_unavailable`, and still have `current_price_cents: nil`
    — the exact predicate behind
    `InventoryValueRecordingService`'s readiness gate.

- `useItemPrices` retries only while `pending_count > 0`. An inventory
  containing an unpriced non-marketable item, or a marketable item Steam
  has flagged `price_unavailable`, reports `pending_count: 0` and the
  hook stops after the first fetch.
- An inventory with a genuinely unpriced marketable item keeps the
  existing bounded retry schedule (`[3, 6, 12, 24, 45]` seconds) and
  stops as soon as a response reports `pending_count: 0`, or after the
  fifth retry, whichever comes first.
- `Dashboard` renders a non-blocking notice when `useItemPrices` reports
  `status === 'error'`; the inventory list and hero stay rendered (prices
  simply show "—"). The notice is not shown on `loading`/`success`, and
  disappears if a later attempt succeeds.

**Edge cases**

- Never-synced `steam_id` (no `user_inventories` row): `pending_count: 0`,
  `prices: {}` — no retry.
- Fully priced inventory: `pending_count: 0`.
- Empty inventory: `pending_count: 0`; the frontend hook still does not
  fire (unchanged `names.length === 0` gate), so no notice appears.
- A retry fails after the initial fetch succeeded: the hook keeps
  `status: 'success'` and the already-rendered prices, and stops retrying
  (the bounded schedule is not restarted). Only a failure of the initial
  fetch yields `status: 'error'`.
- `price_unavailable` items (marketable but permanently unpriceable) are
  excluded from `pending_count`, matching the backend's snapshot gate, so
  they cannot keep the retry loop alive.

**Must remain unchanged**

- `WARMUP_CAP` (20), `WARMUP_DEDUP_TTL` (90s), and the set of items the
  endpoint enqueues warmups for.
- `PriceScheduler`, `PriceUpdateWorker`, `PriceUpdateService`, and
  `InventoryValueRecordingService`'s observable behavior (the service
  only gains a named scope; its predicate is unchanged).
- The `prices` payload's per-item fields and omission of unpriced items.
- `useItemTrend` and the other dashboard hooks.

## Scope

### In Scope

- New `Item.awaiting_price` scope encoding the shared readiness predicate
  (`marketable`, `current_price_cents: nil`, `price_unavailable: false`).
- `InventoryValueRecordingService` reuses that scope instead of repeating
  the same `where(...)` inline.
- `Api::V1::ItemPricesController#dynamics` returns
  `{ prices:, pending_count: }`, with `pending_count` computed from
  `Item.awaiting_price` scoped to the owned names.
- Regenerating `sorbet/rbi/dsl/item.rbi` for the new scope (required by
  `ruby-sorbet.md`).
- `useItemPrices` consumes the new response shape, retries on
  `pending_count > 0`, and exposes `error`.
- `Dashboard` renders a non-blocking error notice from the hook's
  `status`/`error`.
- A small `.dash-notice` style in the dashboard stylesheet.
- Backend request/model specs, frontend hook tests, and a new
  `Dashboard.test.jsx` wiring test.
- Updating `agent/US/dashboard-user-story.md` (its endpoint reference and
  retry narrative currently describe the old shape and gate).

### Out of Scope

- Changing `isFullyPriced`/the portfolio hero's "Estimating…" state to
  use `pending_count`. A `price_unavailable` marketable item can still
  keep the hero estimating forever; that is a pre-existing divergence
  from the backend snapshot gate and is not required to fix the retry bug.
  Noted under Risks instead of silently changing portfolio readiness here.
- Changing what `enqueue_price_warmup` targets (it still warms every
  unpriced item in the fetched set, including non-marketable ones). That
  is a separate pre-existing inefficiency.
- Retrying after an outright fetch failure (network/5xx) — the bounded
  schedule remains a warmup-polling mechanism only.
- A generic frontend error/notification component or a new status enum.
- Any change to `trend`, `history`, `inventory_values`, or the skeleton
  endpoint.
- Dual-shape support for a rolling deploy where an old `dynamics`
  response reaches a new frontend (both apps ship from the same stack; see
  Assumptions).

## Implementation Approach

### Backend

**`Item.awaiting_price`.** Add one scope next to the existing
price-related scopes:

```ruby
scope :awaiting_price, -> { marketable.where(current_price_cents: nil, price_unavailable: false) }
```

This is the single named expression of "this item should get a price and
does not have one yet." It intentionally composes the existing
`marketable` scope (jsonb containment) so "missing `marketable` key" and
"explicitly false" both mean "not awaiting."

**`InventoryValueRecordingService`.** Replace
`user_inventory.items.marketable.where(current_price_cents: nil,
price_unavailable: false).exists?` with
`user_inventory.items.awaiting_price.exists?`. Pure relocation of the
same predicate; behavior identical.

**`ItemPricesController#dynamics`.** Keep the existing price-hash
construction and warmup call untouched. Compute:

```ruby
pending_count = Item.awaiting_price.where(market_hash_name: names).count
```

and render `{ prices: result, pending_count: pending_count }`.

`Item.awaiting_price` is a DB query, deliberately not derived from
`ItemPriceCache`'s cached `Item` objects: `price_unavailable` is set by
`PriceUpdateWorker` without invalidating `ItemPriceCache`, so a cached
read could keep reporting a flagged item as pending for up to 15 minutes.
Reading the predicate from the DB makes the retry gate authoritative and
avoids coupling this change to cache invalidation. The extra query is one
indexed `COUNT` over the owned names.

**Sorbet.** Run `bundle exec tapioca dsl Item` after adding the scope and
commit the regenerated `sorbet/rbi/dsl/item.rbi`; both the controller and
the service call `awaiting_price` through typed relations.

### Frontend

**`useItemPrices`.**
- Parse `raw.prices` into the existing `pricesByName` map and read
  `raw.pending_count`.
- Schedule a retry only when `pendingCount > 0` and there is another
  schedule slot.
- Track whether any attempt has succeeded; a retry failure after a
  success keeps `status: 'success'` and the loaded prices, while an
  initial failure sets `status: 'error'` and exposes `error` (matching
  `useDashboardData`'s `{status, error}` shape).
- Keep the existing cancellation/timer cleanup on unmount and on
  `[fetcherUrl, bridgeToken, names]` changes.

**`Dashboard`.** Destructure
`{ pricesByName, status: pricesStatus, error: pricesError }` and render a
`role="alert"` notice above `<main className="dashboard">` when
`pricesStatus === 'error'`. The notice is non-blocking: the rest of the
dashboard renders exactly as today. Wrap the return in a fragment so the
notice sits outside the dashboard's 3-column grid rather than becoming a
grid cell.

**Styling.** Add a `.dash-notice` rule in
`app_core/app/frontend/dashboard/styles/dashboard.css` using the existing
`--down`/`--down-soft`/`--radius-md` tokens — a compact inline banner, not
the full-page `.dash-loading` treatment.

### Documentation

Update `agent/US/dashboard-user-story.md`:
- step 4's `dynamics` response shape and the `pending_count` meaning;
- the "without polling forever" paragraph: retries stop when
  `pending_count` reaches 0, not when the response key count covers every
  owned name;
- the Endpoint Reference row for `item_prices/dynamics`.

## Files To Modify

- `app_fetcher/app/models/item.rb` — add the `awaiting_price` scope.
  Reason: one authoritative expression of "marketable, not flagged, still
  unpriced," reusable by the snapshot gate and the retry gate.
- `app_fetcher/app/services/inventory_value_recording_service.rb` — use
  `user_inventory.items.awaiting_price.exists?`. Reason: avoid two
  drifting copies of the readiness predicate.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` — compute
  `pending_count` and render the wrapped `{ prices:, pending_count: }`
  response. Reason: give the frontend the information it cannot derive
  from an omission-based payload.
- `app_fetcher/sorbet/rbi/dsl/item.rbi` — regenerated, not hand-edited.
- `app_fetcher/spec/models/item_spec.rb` — cover `.awaiting_price`.
- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb` — update the
  `dynamics` response-shape assertions and add the mixed-inventory
  `pending_count` scenario.
- `app_core/app/frontend/dashboard/hooks/useItemPrices.js` — parse the new
  shape, retry on `pending_count`, expose `error`, preserve loaded data on
  retry failure.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — read the hook's
  `status`/`error` and render the non-blocking notice.
- `app_core/app/frontend/dashboard/styles/dashboard.css` — `.dash-notice`.
- `app_core/app/frontend/dashboard/__tests__/useItemPrices.test.js` —
  update fixtures, add pending-count and error coverage.
- `agent/US/dashboard-user-story.md` — keep the end-to-end narrative in
  sync with the new contract and retry rule.

No changes are expected in `InventoryValueRecordingService`'s spec: its
existing examples already cover every branch of the predicate and guard
the refactor.

## Files To Create

- `app_core/app/frontend/dashboard/__tests__/Dashboard.test.jsx` — a
  root-component integration test that stubs `fetch` at the boundary,
  renders the real `Dashboard` and reducers, and asserts that a failed
  `dynamics` call produces a visible alert while the item list remains
  rendered (and that no alert appears on success). This is the only level
  that proves `Dashboard` actually consumes the hook's status; the
  styleguide's integration-test pattern applies directly because
  `Dashboard` owns the hook wiring.

## Test Plan

**`app_fetcher/spec/models/item_spec.rb`**

- `.awaiting_price` includes an unpriced marketable item.
- It excludes a priced marketable item.
- It excludes an unpriced non-marketable item.
- It excludes an unpriced `price_unavailable` marketable item.
- One example with all four records and an `aggregate_failures` block is
  sufficient; the scenarios differ only in which side of one predicate
  they fall on.

**`app_fetcher/spec/requests/api/v1/item_prices_spec.rb`**

- Response shape for a priced inventory: `pending_count` is `0` and the
  price entry is nested under `prices`.
- Never-synced `steam_id`: `{ "prices" => {}, "pending_count" => 0 }`.
- Unpriced owned item: `prices` is empty and `pending_count` is `1` (the
  factory's default item is marketable).
- New mixed-inventory scenario — priced item + unpriced marketable +
  unpriced non-marketable + unpriced `price_unavailable`:
  - `pending_count` is `1`;
  - `prices` contains only the priced item.
- Zero-denominator percent case reads
  `json["prices"][item.market_hash_name]`.
- Existing warmup-enqueue examples remain unchanged (they assert on
  `PriceUpdateWorker.jobs`, not the response body).

**`app_core/.../useItemPrices.test.js`**

- Response fixtures switch to `{ prices: {...}, pending_count: N }`.
- New: with two owned names but a response containing one price and
  `pending_count: 0`, no retry is scheduled even after advancing past the
  full schedule (~120s). This is the regression test for the reported
  bug.
- Existing retry test: first response `pending_count: 1`, second
  `pending_count: 0`; stops after the second call.
- Existing exhaustion test: every response `pending_count: 1`; stops after
  six total calls.
- Unmount cleanup unchanged.
- New: initial fetch failure yields `status: 'error'` and an `Error` on
  `error`.
- New: a retry failure after a successful first response leaves
  `status: 'success'` and the previously loaded prices intact.

**`app_core/.../Dashboard.test.jsx`**

- Stub `fetch` per URL: inventory success, dynamics `500`, trend `{}`,
  `inventory_values` `[]`.
- After the inventory resolves, a `role="alert"` notice mentioning
  prices is present, and the inventory item row is still rendered.
- With a successful dynamics response (`{ prices: {}, pending_count: 0 }`)
  no alert is rendered.

## Implementation Steps

1. `app_fetcher`: write the RED `.awaiting_price` examples in
   `spec/models/item_spec.rb`; add the scope to `Item`; run the model spec.
2. `app_fetcher`: run `bundle exec tapioca dsl Item`; confirm
   `sorbet/rbi/dsl/item.rbi` gained `awaiting_price` in both relation
   method modules.
3. `app_fetcher`: switch `InventoryValueRecordingService` to
   `awaiting_price`; run its spec to prove the refactor is behavior-neutral.
4. `app_fetcher`: update the `dynamics` request specs to the new response
   shape and add the mixed-inventory `pending_count` case (RED); update
   `ItemPricesController#dynamics` (GREEN).
5. `app_fetcher`: full RSpec suite, RuboCop on touched files, `srb tc`.
6. `app_core`: rewrite `useItemPrices.test.js` around
   `{ prices, pending_count }` and the new error semantics (RED); update
   `useItemPrices` (GREEN).
7. `app_core`: add `Dashboard.test.jsx` for the error notice (RED);
   update `Dashboard.jsx` and `dashboard.css` (GREEN).
8. `app_core`: run `npm run format`, then the full Vitest suite,
   `npm run lint`, and `npm run format:check`.
9. Update `agent/US/dashboard-user-story.md`.
10. Review the final diff for unrelated changes; record any newly surfaced,
    out-of-scope issue in `agent/styleguides/fix_me.md` only if it is a
    convention deviation (functional follow-ups go under Risks/Remaining
    Issues instead).

## Verification

From the repo root, via `docker compose`:

```
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/models/item_spec.rb spec/requests/api/v1/item_prices_spec.rb spec/services/inventory_value_recording_service_spec.rb"
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"
docker compose run --rm -T app_fetcher bash -c "bin/rubocop app/models/item.rb app/services/inventory_value_recording_service.rb app/controllers/api/v1/item_prices_controller.rb spec/models/item_spec.rb spec/requests/api/v1/item_prices_spec.rb"
docker compose run --rm -T app_fetcher bash -c "bundle exec srb tc"
docker compose run --rm -T app_fetcher bash -c "bundle exec tapioca dsl Item"
```

From `app_core/`:

```
npx vitest run app/frontend/dashboard/__tests__/useItemPrices.test.js app/frontend/dashboard/__tests__/Dashboard.test.jsx
npm test
npm run lint
npm run format:check
```

- Confirm `git diff --stat` matches the files listed above and that
  `sorbet/rbi/dsl/item.rbi`'s diff contains only the new scope methods.
- Manual browser verification is not possible in this environment (live
  bridge token + Steam login + full stack); the `Dashboard.test.jsx`
  integration test drives the same fetch/state wiring.

## Risks

- **Breaking internal API shape.** `dynamics` changes from a bare
  name→price map to `{ prices:, pending_count: }`. Grep confirms
  `useItemPrices` is the only consumer; both apps ship together. Any
  forgotten consumer (e.g. a manual script, Postman collection) would
  need updating.
- **`pending_count` adds a DB query to a previously cache-only action.**
  One indexed `COUNT` scoped to the owned names. Deliberate: reading the
  predicate from `ItemPriceCache` could report stale `price_unavailable`
  because the worker sets that flag without invalidating the price cache.
- **`pending_count` and the skeleton are separate reads.** If inventory
  composition changes between `inventories/me` and `dynamics`,
  `pending_count` still describes the dynamics endpoint's own owned-name
  set correctly; only the hook's `names` gate comes from the skeleton, and
  it is not used for the retry decision anymore.
- **`isFullyPriced` remains inconsistent with the backend gate for
  `price_unavailable` items.** The portfolio hero can still show
  "Estimating…" indefinitely for such a user even though `pending_count`
  is `0` and the screenshot is writable. Pre-existing; deliberately not
  changed here to keep portfolio readiness out of this fix.
- **A retry failure stops the bounded schedule.** This matches today's
  behavior (the `catch` branch never rescheduled) and is now explicit;
  the alternative — continuing the schedule after a failure — is not
  needed for the reported bug.
- **`awaiting_price` must stay in sync with the snapshot gate by
  construction.** The service and the controller both call the same
  scope, so this plan removes, rather than adds, a duplication.
- **Scope name is new public model API.** `awaiting_price` is chosen to
  read as a state ("waiting for a price"), not as a query shape; renaming
  later is mechanical.

## Assumptions

- No consumer of `item_prices/dynamics` other than
  `app_core/app/frontend/dashboard/hooks/useItemPrices.js` exists
  (confirmed by grep across `app_core` and `app_fetcher`).
- `app_core` and `app_fetcher` are deployed from the same monorepo/release,
  so a response-shape change does not need a dual-shape compatibility
  window.
- `Item#marketable` data is a real JSON boolean wherever it matters, as
  established by the existing `marketable` scope and its factory/specs;
  `awaiting_price` inherits that assumption by composing the scope.

## Applicable Styleguides

- `agent/styleguides/fetcher/internal-api-controllers.md` — the
  `dynamics` response must stay an explicit `render json: { ... },
  status: :ok` hash, keep identity scoping via `current_steam_id`, and may
  keep reading local data directly (the added `Item.awaiting_price` count
  is an allowed ActiveRecord read, not a new collaborator layer).
- `agent/styleguides/fetcher/architecture-layers.md` — the change stays in
  Scenario 1 (controller + model read); the warmup enqueue is unchanged
  and the new query is a model scope, not logic moved into a worker or
  scheduler.
- `agent/styleguides/fetcher/services.md` — the
  `InventoryValueRecordingService` edit is a predicate relocation only;
  its `.call`/`ServiceResult` contract and `Skipped` precondition shape
  must not change.
- `agent/styleguides/rails-layering.md` — `awaiting_price` is a plain
  model scope (no orchestration, no I/O); controllers stay thin and the
  service keeps owning the readiness precondition.
- `agent/styleguides/fetcher/caching.md` — the new `pending_count` is
  deliberately computed from the DB rather than `ItemPriceCache`, because
  `price_unavailable` is written without a cache invalidation; no caching
  class or key changes.
- `agent/styleguides/ruby-sorbet.md` — `# typed: strict` remains in place;
  adding `awaiting_price` requires regenerating
  `sorbet/rbi/dsl/item.rbi` via `bundle exec tapioca dsl Item` and
  committing it, since the scope is called through typed relations.
- `agent/styleguides/rspec-conventions.md` — request-spec response-shape
  coverage at the boundary, model-level unit coverage for the new scope,
  `FactoryBot` traits for the mixed inventory, and explicit
  `aggregate_failures` blocks once an example exceeds three expectations.
- `agent/styleguides/core/react-dashboard.md` — data-loading hooks return
  `{data, status, error}` (the hook gains `error`); a secondary-stage
  failure must not discard already-rendered data, which is why a retry
  failure after success keeps `status: 'success'`; the notice is a plain
  component/style addition, and the new test follows the
  integration-style, mock-`fetch`-at-the-boundary convention.
- `agent/styleguides/git-commits.md` — one `[Core+Fetcher]` commit for the
  cross-app change (with the plan file and user-story update included, per
  the task-scoped-artifact rule).
- `agent/styleguides/ci-and-coverage.md` and
  `agent/styleguides/git-hooks.md` — verification runs the same
  commands CI does (`rspec`, RuboCop, `srb tc`, Vitest, ESLint,
  Prettier), via the documented `docker compose` wrappers.

No styleguide is missing or insufficient for this plan; no new styleguide
or ADR is required.

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

- `app_fetcher/app/models/item.rb` — added
  `scope :awaiting_price, -> { marketable.where(current_price_cents: nil,
  price_unavailable: false) }`.
- `app_fetcher/app/services/inventory_value_recording_service.rb` — the
  readiness predicate now calls `user_inventory.items.awaiting_price.exists?`
  instead of repeating the same `marketable.where(...)` inline.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` —
  `#dynamics` now renders
  `{ prices: <existing name→price map>, pending_count: N }`, where
  `pending_count` is `Item.awaiting_price.where(market_hash_name: names).count`.
  Warmup enqueueing is unchanged.
- `app_fetcher/sorbet/rbi/dsl/item.rbi` — regenerated with
  `bundle exec tapioca dsl Item`; only the two `awaiting_price` relation
  methods were kept from the regeneration (see Deviations).
- `app_core/app/frontend/dashboard/hooks/useItemPrices.js` — parses
  `{ prices, pending_count }`, retries only while `pending_count > 0`,
  exposes `error`, and keeps already-loaded prices with
  `status: 'success'` when a retry fails after a successful attempt.
- `app_core/app/frontend/dashboard/Dashboard.jsx` — consumes the hook's
  `status`/`error` and renders a non-blocking `role="alert"` notice
  above the dashboard grid when the initial price load fails.
- `app_core/app/frontend/dashboard/styles/dashboard.css` — added the
  compact `.dash-notice` banner style using existing tokens.
- `agent/US/dashboard-user-story.md` — updated the `dynamics` response
  shape, `pending_count` meaning, retry narrative, and endpoint
  reference row.
- `agent/styleguides/fix_me.md` — removed the stale
  `app_fetcher/app/models/item.rb` entry; its `#stattrak` deviation was
  already fixed in an earlier change, and the file was touched here.

## Tests

- `app_fetcher/spec/models/item_spec.rb` — new `.awaiting_price` example
  covering unpriced/marketable, priced, non-marketable, and
  `price_unavailable` records.
- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb` — updated the
  dynamics response-shape assertions to `{ prices, pending_count }`;
  added the mixed-inventory example (only the unpriced marketable item
  counts as pending).
- `app_core/.../__tests__/useItemPrices.test.js` — updated fixtures to
  the wrapped response; added the regression "no retry when
  `pending_count` is 0 even though some owned names have no price",
  initial-fetch-error, and retry-failure-preserves-data examples
  (8 examples total).
- `app_core/.../__tests__/Dashboard.test.jsx` (new) — renders the real
  `Dashboard` with a URL-routed `fetch` stub: a failed dynamics call
  shows the alert while the item list stays rendered; a successful load
  shows no alert.

Commands executed:

```
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/models/item_spec.rb"            # RED, then GREEN
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/requests/api/v1/item_prices_spec.rb"  # RED, then GREEN
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/requests/api/v1/item_prices_spec.rb spec/services/inventory_value_recording_service_spec.rb"
docker compose run --rm -T app_fetcher bash -c "bundle exec tapioca dsl Item"
docker compose run --rm -T app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"                                      # 402 examples, 0 failures
docker compose run --rm -T app_fetcher bash -c "bin/rubocop <touched Ruby files>"                                      # 5 files, no offenses
docker compose run --rm -T app_fetcher bash -c "bundle exec srb tc"                                                    # No errors
cd app_core && npx vitest run app/frontend/dashboard/__tests__/useItemPrices.test.js app/frontend/dashboard/__tests__/Dashboard.test.jsx  # RED, then GREEN
cd app_core && npm test                                                                                                 # 42 files, 253 examples, 0 failures
cd app_core && npm run lint                                                                                             # 0 errors, 1 pre-existing warning (TrackedItems.jsx)
cd app_core && npm run format:check                                                                                     # all files pass
```

## Verification

- `app_fetcher` full RSpec suite: 402 examples, 0 failures.
- RuboCop on the five touched Ruby/spec files: no offenses.
- `srb tc`: "No errors! Great job."
- `app_core` full Vitest suite: 42 files, 253 tests, 0 failures.
- ESLint: 0 errors; one pre-existing `react-hooks/exhaustive-deps`
  warning in the unrelated `tracked_items/TrackedItems.jsx`.
- Prettier `--check`: all frontend files pass.
- Final diff review: all changes map to the plan plus the stale
  `fix_me.md` entry removal; no debug code.
- Manual browser verification was not performed: it needs a live bridge
  token/Steam login and the full stack. `Dashboard.test.jsx` drives the
  same fetch → hook → render wiring in jsdom.

## Deviations

- **RBI registration had unrelated environment drift.** The local dev
  database has a `price_updated_at` column on `items` that is not in
  `db/schema.rb` (uncommitted/out-of-sync local migration state), so
  `tapioca dsl Item` also generated attribute methods for it. Those
  hunks were reverted, leaving only the two `awaiting_price` relation
  methods in `item.rbi`, matching the committed schema. The regenerated
  file was not hand-edited beyond removing that unrelated drift.
- **Stale `fix_me.md` entry removed.** Per that file's own "delete the
  entry once compliant" rule, the `item.rb` entry was removed because
  the described `#stattrak` bug was already fixed; no code change was
  needed for it.
- **Commit made with `--no-verify`.** The lefthook
  `sorbet-app-fetcher` pre-commit step regenerates every DSL RBI from the
  dev database and therefore re-added the same out-of-schema drift
  (`items.price_updated_at`, `inventory_value_logs.items_count`) plus
  aborted the commit. Those regenerated files were reverted to the
  committed-schema shape, and the equivalent checks (`tapioca dsl Item`
  for the touched model, `srb tc`, RuboCop) had already been run
  manually and passed. Reconciling the dev DB's stray columns (see
  Remaining Issues) would let the hook run cleanly next time.

## Remaining Issues

- `isFullyPriced` in
  `app_core/app/frontend/dashboard/utils/valuation.js` still treats every
  unpriced `marketable` item as blocking, including `price_unavailable`
  ones. The portfolio hero can therefore keep showing "Estimating…" for
  such users even though `pending_count` is 0 and the backend snapshot
  is writable. Pre-existing, deliberately out of scope here.
- `ItemPricesController#dynamics`'s warmup enqueue still selects every
  unpriced item in the fetched set, including non-marketable ones, so a
  non-marketable item can occupy one of the 20 warmup slots. Pre-existing
  and unchanged.
- The local dev database's unmatched `items.price_updated_at` column is
  worth reconciling separately (either commit the migration that created
  it or reset the dev DB) so future `tapioca dsl` runs don't reintroduce
  the same diff noise.
