---
status: implemented
app: fetcher
goal: Make an item's price change show in every list as soon as it has two price logs, by falling back to the oldest available log when no ~24h-old log exists, and make the list sparkline render from that same (short) history
created: 2026-10-16
---

# Development Plan

## Goal

Fix the divergence between the item-detail chart and the list views:

- The item-detail hero chart (`PortfolioTile`, item mode) computes its
  delta on the client from the raw `price_logs` series (`last − first`), so
  an item with two recent logs shows `+3%`.
- Every list (portfolio dashboard rows via `dynamics`, the Tracked Items
  catalog incl. `Gaining today`/`Losing today`, and the inventory
  catalog/detail item rows) reads the stored `items.change_24h_cents`,
  which `PriceUpdateService` sets to `0` whenever there is no price log
  **older than 24 hours**. With two fresh logs it is therefore `0`
  everywhere, so the lists read flat and the list sparkline is nearly
  empty.

After this change: an item with at least two price logs shows the same
sign of change in every list as its detail chart, and the list sparkline
renders a real line (≥2 points) instead of a single point.

## Expected Behavior

**Normal behavior**

- An item with two price logs both younger than 24h: every list shows the
  item's change as `newest − oldest` (same sign/magnitude basis as the
  detail chart), i.e. a non-zero `change_24h_cents`, a non-zero
  `change_24h_percent`, an up/down delta badge, and the item counts toward
  `Gaining today` / `Losing today` when positive/negative.
- Once a price log at least 24h old exists, the change goes back to being
  measured against the most recent log that is at least 24h old — i.e. the
  metric returns to a true trailing-24h change (existing behavior, unchanged).
- An item's list sparkline (`trend_7d`) renders a line whenever it has at
  least two logs in the 7-day window, including two logs that are only
  hours apart.

**Edge cases**

- Item with a single price log (its first ever): `change_24h_cents` stays
  `0` (no baseline) — no delta, unchanged.
- Item with several logs all younger than 24h: the baseline is the
  **oldest** log, not the most recent — `change = newest − oldest`.
- Item with both a ≥24h-old log and newer logs: baseline is the most
  recent log that is ≥24h old — unchanged from today.
- Item with two logs at identical `created_at`: sparkline downsampling
  must not raise and must still emit that single distinct point.
- Item with exactly one log inside the 7-day window, but an older log
  outside it: sparkline emits the one in-window point (unchanged).

**Failure behavior**

- Unchanged: a failed Steam response still leaves the item's price/change
  untouched; no cache invalidation on failure.

**Must remain unchanged**

- The `dynamics`, `trend`, `history`, `/api/public/items`, and inventory
  endpoints' response shapes.
- The client-side percent formula (`change / (current − change)`) and the
  `trendDirection` "flat" rule.
- The `ItemTrendCache` public interface (`fetch_for`/`invalidate`), its
  cache key version, its payload shape, and the ≤5-point cap.
- `InventoryDetailQuery#change_for` (the inventory hero uses
  `InventoryValueLog`, a daily-granularity metric — not this code path).
- `PriceUpdateWorker`'s success path other than the computed change value
  (Steam call → `PriceLog` + `Item` update → three cache invalidations →
  stream publish).
- No `app_core` code change — the mappers already pass
  `change_24h_percent`/`trend_7d` straight through.

## Scope

### In Scope

- `app_fetcher`: change the `change_24h_cents` baseline selection in
  `PriceUpdateService` to fall back to the oldest available `PriceLog`
  when no log ≥24h old exists.
- `app_fetcher`: make `ItemTrendCache#downsample` anchor its sampling
  window to the data's own span (oldest→newest log in the window) instead
  of the fixed `now − 7d … now` span, so ≥2 logs produce ≥2 points.
- Tests for both changes (`price_update_service_spec.rb`,
  `item_trend_cache_spec.rb`).
- Documentation sync for the changed `change_24h_cents` semantics (the
  exact artifact is settled in `styleguides-check`).

### Out of Scope

- Any `app_core` source or test change (the lists already render whatever
  the backend sends).
- Backfilling/repairing existing `items.change_24h_cents = 0` rows — the
  next hourly `PriceUpdateWorker` run per item recomputes them from the
  (now-fixed) fallback (see Risks).
- `ItemCatalogCache` freshness (TTL-only, 2 min) — a pre-existing
  characteristic, not the reported bug.
- Renaming the field (`change_24h_cents`/`change_24h_percent`) or the
  `24h` labels, even though during warmup the value is "change since
  tracking began" rather than a strict 24h change — accepted trade-off
  (see Decisions).
- `InventoryValueLog`-based inventory-hero change and daily granularity.
- Any change to `PricePeriod`, the range toggles, or the 24h history
  endpoint.

## Implementation Approach

Both fixes are small and live in `app_fetcher`; nothing in `app_core`
changes.

### Decision: fallback semantics

The list "change" is a single stored column. To match the detail chart
while history is short, `PriceUpdateService` picks its baseline in order:

1. the most recent log with `created_at <= 24.hours.ago` (today's rule);
2. otherwise the **oldest** log overall.

The new log itself is not yet saved when the baseline is chosen, so it is
never its own baseline. Zero prior logs → `nil` baseline → `0` (unchanged
first-price behavior). This is deliberately a *warmup* behavior: once the
item has ≥24h of history, rule 1 applies and the metric is a true
trailing-24h change again. The `24h` label stays as-is; the alternative
(relabeling or a second field) was rejected as a much wider change for a
transient state.

### Decision: sparkline anchor

`ItemTrendCache#downsample` currently samples 5 targets at fixed fractions
of `now − 7d … now`. With logs clustered in the last hours, only the
final target sees data → one point. Anchoring the same 5-target sampling
to `[oldest_log.created_at, newest_log.created_at]` (the query already
bounds `logs` to the 7-day window) guarantees that N distinct logs in the
window yield up to `min(N, 5)` points, including N = 2. The cap, the
dedup-by-id behavior, and the payload shape are unchanged, so the cache
key version does not need to be bumped.

## Files To Modify

- `app_fetcher/app/services/price_update_service.rb` — replace the
  `price_24h_ago` selection with a `baseline` that falls back to the
  oldest log when the `created_at <= 24.hours.ago` query returns `nil`;
  compute `change_24h_cents` against it. Reason: makes the stored change
  non-zero as soon as a second log exists.
- `app_fetcher/app/caching/item_trend_cache.rb` — in the private
  `#downsample`, derive the sampling start/span from
  `logs.first.created_at`/`logs.last.created_at` instead of
  `TREND_WINDOW.ago`/`TREND_WINDOW.to_i`. Reason: makes the list
  sparkline render for short histories.
- `app_fetcher/spec/services/price_update_service_spec.rb` — add the
  "recent-only logs" baseline case and the "multiple recent logs → oldest
  is the baseline" case; keep the existing "no prior log → 0" and
  "older than 24h → diff" cases.
- `app_fetcher/spec/caching/item_trend_cache_spec.rb` — add a
  "two recent logs → two points" case; keep the existing examples green.
- `agent/US/dashboard-user-story.md` — note, in the `PriceUpdateWorker`
  step and/or the Data & Caching Map's item-price row, that the change
  falls back to the oldest available log while the item has no ≥24h-old
  log. Reason: keep the end-to-end narrative in sync with the job's
  behavior (per the file's own "keep this in sync" rule).

## Files To Create

None — both fixes extend existing classes.

## Test Plan

- **`price_update_service_spec.rb`** (unit):
  - existing: no prior log → `change_24h_cents == 0` (kept);
  - existing: prior log ≥24h old → diff against it (kept);
  - new: prior logs exist but all are younger than 24h → `change_24h_cents`
    equals `new_price − oldest_log_price`;
  - new: two prior recent logs, oldest differs from newest → baseline is
    the **oldest** (assert against the oldest price, not the newest).
- **`item_trend_cache_spec.rb`** (unit):
  - existing: cold-cache DB-hit count, ≤5 points, ordering, "exactly as
    many distinct points as exist", "excludes logs older than the
    window", invalidation — all kept;
  - new: two logs an hour apart → the returned series has two points
    whose prices match the two logs in ascending time order.
- **Regression**: run the full `app_fetcher` suite (the value feeds
  `dynamics`, catalog, and inventory serializers, whose specs use explicit
  `change_24h_cents` values and are unaffected).

## Implementation Steps

1. `price_update_service_spec.rb`: add the two new baseline examples and
   confirm they fail against current code (RED).
2. `PriceUpdateService`: implement the baseline fallback (oldest-log
   fallback when no ≥24h-old log). Confirm the spec file is GREEN and the
   existing two examples still pass.
3. `item_trend_cache_spec.rb`: add the "two recent logs → two points"
   example and confirm it fails (RED — currently one point).
4. `ItemTrendCache#downsample`: anchor the sampling window to
   `logs.first.created_at..logs.last.created_at`. Confirm GREEN, including
   the pre-existing downsampling examples.
5. Update `agent/US/dashboard-user-story.md` to describe the fallback.
6. Run the full `app_fetcher` RSpec suite, `bin/rubocop` on the touched
   Ruby files, and `srb tc`.
7. (Optional, environment permitting) manual check: after one
   `PriceUpdateWorker` run for an item that has two recent logs, confirm
   `items.change_24h_cents != 0`, that `/api/v1/item_prices/dynamics`
   reports a non-zero `change_24h_percent`, and that `/trend` returns ≥2
   points.

## Verification

- `app_fetcher`: targeted specs for the two touched files, then the full
  suite (`RAILS_ENV=test bundle exec rspec`) — 0 failures.
- `app_fetcher`: `bin/rubocop` on the changed files — no offenses.
- `app_fetcher`: `bundle exec srb tc` — no new errors.
- No frontend/Ruby-in-`app_core` change, so no `app_core` checks are
  required.
- Manual (optional): the Redis/cache-backed item endpoints reflect the new
  change and trend values for a two-log item.

## Risks

- **Semantic drift during warmup.** While an item has no ≥24h-old log,
  `change_24h_cents` means "change since the oldest known price," not a
  strict 24h change. Accepted for the warmup window only; once ≥24h of
  history exists the metric converges to the existing meaning. Documented
  in the user story.
- **No retroactive fix.** Existing rows with `change_24h_cents = 0` are
  not backfilled; they self-heal on the next successful price fetch for
  that item (hourly `PriceScheduler`). If an immediate demo is needed,
  a one-off `PriceUpdateWorker.perform_async` per item is the lever
  (out of scope).
- **`ItemCatalogCache` lag.** The public Tracked Items catalog is
  TTL-only (2 min) and is not invalidated by `PriceUpdateWorker`, so its
  page can lag the recomputed change by up to 2 minutes. Pre-existing,
  out of scope.
- **Sparkline geometry shift.** Anchoring the sampling window to the data
  changes where points sit within the decorative sparkline for
  spread-out histories; the point count, cap, and shape contract are
  unchanged, and the existing downsampling specs still pass.
- **Two baselines to keep consistent.** The stored value and the client
  chart still derive their numbers differently (stored column vs.
  last-vs-first of the fetched series). They agree on *sign* while history
  is short (the case reported here); they can differ in magnitude for
  ranges other than ~24h, which is expected and out of scope to unify.

## Assumptions

- The reported item's two price logs are both younger than 24h (implied by
  the symptom: the detail chart shows a change while the stored
  `change_24h_cents` is `0`).
- A brief warmup window with a "since tracking began" change is
  acceptable, as confirmed with the user (fallback to the oldest log).
- The list sparkline being near-empty is part of the same report and is
  in scope (confirmed with the user).

## Applicable Styleguides

- `agent/styleguides/fetcher/services.md` — governs
  `PriceUpdateService`: the single `self.call`, the unchanged
  `ServiceResult[Item]` (`Ok`) return, and the "precondition/business logic
  lives inside the service" rule — the new baseline selection stays inside
  `.call`, adding no public surface. Its Testing section (unit spec under
  `spec/services/`, assert on the outcome) shapes the added spec cases.
- `agent/styleguides/fetcher/caching.md` — governs the `ItemTrendCache`
  change: bulk read-through + invalidation shape, versioned keys, safety
  TTL, and the rule that the version segment is bumped only when the
  **cached payload's shape** changes (it does not here — still
  `T::Array[TrendPoint]`). Its Testing section (unit spec in
  `spec/caching/`, assert against real `Rails.cache` state) governs the
  added downsampling example.
- `agent/styleguides/fetcher/architecture-layers.md` +
  `agent/styleguides/rails-layering.md` — dependency direction: the change
  stays in the Service and Caching layers, invoked from
  `PriceUpdateWorker` (Scenario 3); no logic moves onto
  `Item`/`PriceLog` models, and no new layer is added.
- `agent/styleguides/fetcher/background-jobs.md` — constrains
  `PriceUpdateWorker`: its success path stays thin orchestration with an
  unchanged transaction boundary and the same three cache invalidations;
  only the computed change value changes (inside the service it calls).
- `agent/styleguides/ruby-sorbet.md` — `typed: strict` + `sig` on the
  touched files; the new baseline local is typed
  `T.nilable(PriceLog)`; no `T.unsafe`/sigil changes.
- `agent/styleguides/rspec-conventions.md` +
  `agent/adr/fetcher/rspec-testing-strategy.md` — spec levels (unit for
  the service and the caching class), `FactoryBot` for test data (reuse
  the existing `price_log` factory and its `:old` trait; add no fixture
  rows), and example granularity.
- `agent/styleguides/git-commits.md` — `[Fetcher] Imperative summary` at
  commit time (single-app change).
- `agent/styleguides/ci-and-coverage.md` + `agent/styleguides/git-hooks.md`
  — how the verification commands (`rspec`, `rubocop`, `srb tc`) are run
  for `app_fetcher` (through the CI compose override), and the pre-commit
  hook expectations for the staged Ruby files.
- `agent/styleguides/fix_me.md` — checked. None of the files this plan
  touches (`price_update_service.rb`, `item_trend_cache.rb`,
  `price_update_service_spec.rb`, `item_trend_cache_spec.rb`, or the user
  story) is listed as a known deviation, so no entry is resolved or added.
- `agent/styleguides/core/react-dashboard.md` — consulted and **not
  changed**: its "a zero/absent 24h change is `flat`" and
  `trendDirection` rules still hold — the plan makes the backend feed
  non-zero values through the existing frontend untouched.

## Completion Criteria

- [x] Desired behavior made explicit (fallback semantics + sparkline).
- [x] Scope explicit (no backfill, no frontend, no field rename).
- [x] Affected files identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [x] Plan checked against styleguides (`styleguides-check`).
- [x] Implemented (`implement-plan`).

# Implementation Summary

## Implemented

- `app_fetcher/app/services/price_update_service.rb` — the change
  baseline now falls back to the oldest available `PriceLog` when no log
  `<= 24.hours.ago` exists (`baseline ||= item.price_logs.order(created_at:
  :asc).first`). With a second log present, `change_24h_cents` is now
  non-zero instead of `0`, so every list (`dynamics`, the Tracked Items
  catalog, the inventory catalog/detail item rows) shows the same sign of
  change as the item-detail chart. Zero prior logs still yields `0`.
- `app_fetcher/app/caching/item_trend_cache.rb` — `#downsample` now
  anchors its 5-target sampling window to the data's own span
  (`logs.first.created_at … logs.last.created_at`) instead of the fixed
  `now − 7d … now` span, so a cluster of recent logs produces as many
  points as exist (two logs → two points) instead of collapsing to one.
  The final target is pinned to the newest log exactly, because deriving it
  from the truncated integer span landed just short of it and dropped that
  log. The payload shape, the ≤5-point cap, dedup-by-id, and the cache key
  version are unchanged.
- `agent/US/dashboard-user-story.md` — the `PriceUpdateWorker` step now
  documents the baseline fallback and that the metric reverts to a true
  trailing-24h change once ≥24h of history exists.

No `app_core` code changed — the mappers already forward
`change_24h_percent`/`trend_7d`, so the fixed backend values flow straight
into the existing rows, badges, stat tiles, and sparklines.

## Tests

Changed tests:

- `app_fetcher/spec/services/price_update_service_spec.rb` — added
  "with a single prior price log younger than 24h" (change against that
  log) and "with multiple prior price logs all younger than 24h" (baseline
  is the **oldest**, not the most recent).
- `app_fetcher/spec/caching/item_trend_cache_spec.rb` — added "returns
  both points for two recent logs only hours apart".

Commands actually executed (from the repo root, CI compose, `--no-deps`):

- `docker compose run --rm -T --no-deps app_fetcher bash -c "RAILS_ENV=test bundle exec rspec spec/services/price_update_service_spec.rb spec/caching/item_trend_cache_spec.rb"` — baseline 11 passed; **RED** 14 examples, 3 failures (all for the intended reason: `change_24h_cents` got `0`; trend got `[1200]`); then an intermediate 3 failures after the first `#downsample` edit (fractional-second truncation dropped the last log); **GREEN** 14 examples, 0 failures.
- `docker compose run --rm -T --no-deps app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"` — **395 examples, 0 failures**.
- `docker compose run --rm -T --no-deps app_fetcher bash -c "bin/rubocop <4 touched files> -f simple"` — **4 files inspected, no offenses**.
- `docker compose run --rm -T --no-deps app_fetcher bash -c "bundle exec srb tc"` — **No errors**.

## Verification

- RSpec (targeted + full): green, as above.
- Sorbet: no type errors.
- RuboCop: no offenses on the touched files.
- **Read-only dev-DB check** (`bin/rails runner`, no writes) confirmed the
  reported data shape and the fix's effect: items with 2–3 logs all under
  ~3h have `stored_change = 0`; the AK-47 the issue describes,
  `AK-47 | Point Disarray (Field-Tested)`, has oldest `13.58` / newest
  `14.00` with `stored = 0`, and the fallback baseline yields
  `new_change = 42` → `+3.09%` — matching the "+3%" the detail chart
  already displays. Flat-price items correctly stay at `0`.
- Not performed: full browser verification against a live Steam login; the
  same state machine is exercised by the specs and the read-only check.

## Deviations

- During implementation the first `#downsample` version
  (integer-truncated span) dropped the last log; the final target is now
  pinned to the newest log exactly. This is a refinement of the planned
  approach (data-anchored window), not a scope change.

## Remaining Issues

- Existing `items.change_24h_cents = 0` rows are not backfilled; each item
  self-heals on its next successful `PriceUpdateWorker` run (hourly
  `PriceScheduler`). For the reported AK-47, the value becomes `42` after
  the next price fetch for that item.
- The public Tracked Items catalog (`ItemCatalogCache`, TTL-only 2 min) can
  lag a recomputed change by up to 2 minutes — pre-existing, out of scope.
- While an item has no ≥24h-old log, `change_24h_cents` means "change since
  the oldest known price" rather than a strict 24h change; accepted
  warmup-window trade-off, documented in the user story.
