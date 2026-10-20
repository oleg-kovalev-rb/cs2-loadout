---
status: implemented
app: fetcher+core
goal: Remove the empty strip at the start of the hero chart in 7d (and every other) period — fix the demo history windows and make the shared chart axis span the data it actually has
created: 2026-10-20
---

# Development Plan

## Goal

In `7d` mode the hero chart's line starts around `6d ago` while the
left-hand axis label says `7d ago`, so the chart looks like its left
chunk is missing. The same shape shows up in the item-detail and public
inventory charts. Make every hero chart span its actual data on the
x-axis, and make the demo history cover its full requested window so
the demo chart fills it exactly like a mature real account's chart.

## Expected Behavior

### Demo data (`app_fetcher`)

- `GET /api/demo/inventory_values?period=7d` returns one daily point per
  day from `today - 7` through `yesterday` (at `00:00 UTC`, matching
  `InventoryValueLog` rows) plus a live point at `Time.current`:
  8 points. The first point is at or before the chart's nominal domain
  start (`now - 7d`), and the last point is at "now".
- `period=30d` behaves the same way (30 daily points + live = 31);
  `period=1y` and `period=all` return every available daily point
  through yesterday plus the live point (365 points, as today).
- `GET /api/demo/item_prices/:name/history` follows the same window
  rule for `7d`/`30d`/`1y`/`all`; `period=24h` covers a full 24 hours
  inclusively (25 hourly points from `now - 24h` to `now`).
- Values stay internally consistent: the newest point equals the item's
  current price / the portfolio's current total; the 24h change is
  still `current - yesterday`; the 5-point trend still ends at the
  current price; the portfolio delta is still `last - previous`.
- The portfolio series is still the sum of the item series at every
  point (live point included).

### Chart axis (`app_core`)

- `HeroChart`'s x-domain starts at the first data point when the series
  is shorter than the selected period, and at `now - PERIOD_MS[period]`
  otherwise; it ends at `max(now, latest point)`, and points older than
  the period boundary are clipped (`allowDataOverflow`). `'all'` keeps
  `dataMin..dataMax`.
- X-axis labels are generated from that effective span instead of only
  from the nominal period:
  - when the data covers the nominal period, the labels are unchanged
    (`7d ago / 5d ago / 4d ago / 2d ago / today`, `24h ago / 18h ago /
    12h ago / 6h ago / now`, `12mo / 9mo / 6mo / 3mo / today`);
  - when the data starts later than the nominal period (young account,
    short item history), the labels describe the actual span (e.g.
    `4d ago / 3d ago / 2d ago / 1d ago / today`), so the line starts at
    the left edge and no label claims a range the data doesn't have;
  - when the actual span is too short for whole-unit day/month labels
    (fewer than 4 units), the labels fall back to the next finer unit
    (`d` → `h`, `mo` → `d`) so labels never repeat;
  - `'all'` keeps its current blank labels except the trailing `today`.
- A series whose data extends earlier than `now - period` (real
  portfolio logs start at the cutoff day's midnight) is labelled with
  its true span; the visible line already reached the left edge there.
- The y-axis, tooltip, partial-point markers, period sets, and CSS are
  unchanged.

## Scope

### In Scope

- Demo synthetic series window selection (`Demo::PriceSeries`,
  `Demo::Dataset`).
- The shared `HeroChart` x-domain and x-axis label generation
  (`shared/components/HeroChart.jsx`, `shared/chartConfig.js`), which
  also covers the inventory-detail / public chart because it uses the
  same component.
- Demo specs, a new pure-function test for the label generator, an
  `HeroChart` partial-series case, and the two styleguides that describe
  these areas.

### Out of Scope

- Changing the real `/api/v1` or `/api/public` query shapes
  (`InventoryValueQuery`, `ItemPriceHistoryQuery`) — those windows are
  already honest; the chart now renders them honestly too.
- Fabricating data for gaps that genuinely have no history.
- The y-axis, tooltip, partial-estimate markings, period sets, CSS, or
  the demo item composition/prices/pool.

## Implementation Approach

**Demo windows.** The real 7d query takes `log_date >= today - 7`,
drops today's log, and appends a live point at `Time.current`, so it
spans 7+ days and ends at "now". The demo currently slices the *last N*
daily points (`today - 6 .. today`, at noon UTC) with no live point, so
it spans one day less than the axis and can end in the future. Mirror
the real shape: anchor daily points at `00:00 UTC`, select the window by
`range.since_date` through yesterday, and append a live point at
`Time.current` with the current value — in both `Demo::PriceSeries` and
`Demo::Dataset#portfolio_points`. The 24h hourly window becomes
`now - 24h .. now` inclusive.

**Chart axis.** Keep Recharts as the renderer and make the axis
deterministic:

- compute `dataMin`/`dataMax` from the series;
- `axisStart = dataMin > periodStart ? dataMin : periodStart` (so a short
  series shrinks the axis, a mature one keeps the period boundary);
- `axisEnd = period === 'all' ? dataMax : max(now, dataMax)`;
- pass `[axisStart, axisEnd]` as the `XAxis` domain with
  `allowDataOverflow` (non-`all`) so older-than-period points are
  clipped, and pass the same pair to `generateAxisLabels`;
- `generateAxisLabels` switches to a span-aware calculation: pick the
  nominal unit (`h` for 24h, `d` for 7d/30d, `mo` for 1y), compute
  `spanUnits = (end - start) / unitMs`, downgrade to the next finer unit
  when `spanUnits < X_AXIS_TICK_COUNT - 1`, then label each tick
  `round(spanUnits * (1 - frac))` units ago, with the period's trailing
  word (`now` for 24h, `today` otherwise);
- when there are no points (or a zero-length span), fall back to the
  nominal period domain/labels so the empty state renders as today.

## Applicable Styleguides

- `agent/styleguides/fetcher/demo-api.md` — constrains the demo window
  rule (`Demo::PriceSeries#points_for`, `Demo::Dataset#portfolio_points`)
  and the demo testing expectations; amended with the cutoff-day +
  live-point rule before implementation.
- `agent/styleguides/core/react-dashboard.md` — constrains
  `HeroChart`'s x-domain/label span rule, `shared/chartConfig.js`, and
  the Vitest layout for the new pure-function test; amended with the
  "Hero chart x-axis: span the data, not just the period" subsection.
- `agent/styleguides/ruby-sorbet.md` — `typed: strict` sigs for the new
  private helpers in `price_series.rb`/`dataset.rb`.
- `agent/styleguides/rspec-conventions.md` — unit vs. request spec
  placement, real-vs-stub choices, and time control (`travel_to`) for the
  live point.
- `agent/styleguides/fix_me.md` — the log for the stale `HeroChart`
  test claim found while amending `react-dashboard.md`.
- `agent/styleguides/git-commits.md` — the `[Scope] Imperative summary`
  message if the change is committed.

## Files To Modify

- `app_fetcher/app/queries/demo/price_series.rb` — anchor daily points at
  `00:00 UTC`; add a live point at `Time.current`; rework `points_for`
  window selection (daily by `range.since_date`, 24h over the full day).
- `app_fetcher/app/queries/demo/dataset.rb` — `portfolio_points` selects
  the cutoff..yesterday window and appends the live portfolio point;
  helper for the live point.
- `app_fetcher/spec/queries/demo/price_series_spec.rb` — update window
  sizes, assert midnight daily anchoring, assert the last point is at
  "now" and equals the anchor.
- `app_fetcher/spec/queries/demo/dataset_spec.rb` — update portfolio
  point counts/window, assert the portfolio is still the sum of the item
  series and that the last point is live.
- `app_fetcher/spec/requests/api/demo/inventory_values_spec.rb` — 7d
  history size becomes 8; assert the first date is `today - 7`.
- `app_fetcher/spec/requests/api/demo/item_prices_spec.rb` — 7d history
  size becomes 8, 24h becomes 25.
- `app_core/app/frontend/shared/chartConfig.js` — span-aware
  `generateAxisLabels(period, start, end)` with the unit-downgrade rule;
  no change to `PERIOD_MS` or tick counts.
- `app_core/app/frontend/shared/components/HeroChart.jsx` — compute the
  effective x-extent from the series, pass it as the `XAxis` domain and
  to `generateAxisLabels`; `'all'` keeps `dataMin..dataMax`.
- `app_core/app/frontend/shared/__tests__/HeroChart.test.jsx` — add a
  short-series case proving the labels describe the real span instead of
  the nominal period.
- `agent/styleguides/fetcher/demo-api.md` — replace the implicit “last N
  points” demo window with the cutoff-day + live-point rule.
- `agent/styleguides/core/react-dashboard.md` — add the hero-chart
  x-domain/label rule to the charting section.
- `agent/styleguides/fix_me.md` — log that `react-dashboard.md` still
  claims `HeroChart` has no dedicated test file although
  `shared/__tests__/HeroChart.test.jsx` exists.

## Files To Create

- `app_core/app/frontend/shared/__tests__/chartConfig.test.js` —
  pure-function tests for the span-aware label generator (full period,
  short period, unit downgrade, `'all'`).

## Test Plan

- Unit (`spec/queries/demo/price_series_spec.rb`):
  - window sizes: `24h` → 25, `7d` → 8, `30d` → 31, `1y`/`all` → 365;
  - daily points are at `00:00 UTC`, the first `7d` point's date is
    `Date.current - 7`, the first `30d` point's date is
    `Date.current - 30`;
  - the last point of every window is at `Time.current` and carries the
    anchor price;
  - the hourly window starts 24 hours before its last point;
  - existing determinism / positive-price / variation specs keep
    passing.
- Unit (`spec/queries/demo/dataset_spec.rb`):
  - `value(period: "7d").history.points` has 8 points, the first dated
    `today - 7`, the last at "now" with the summed current total;
  - portfolio values equal the sum of the item series values at each
    point (live point included);
  - snapshot total and delta assertions still hold.
- Request specs (`spec/requests/api/demo/`):
  - `inventory_values?period=7d` → 8 history points, first date
    `today - 7`, last total equals `current.total_value_cents`;
  - item history `7d` → 8 points, `24h` → 25 points, last price still
    equals the current price.
- Frontend unit (`shared/__tests__/chartConfig.test.js`):
  - full 7d span → `['7d ago', '5d ago', '4d ago', '2d ago', 'today']`;
  - full 24h and 1y spans → unchanged labels;
  - 3-day data in the 7d period → hour labels, no duplicates;
  - `'all'` → blank labels except the trailing `today`.
- Frontend component (`shared/__tests__/HeroChart.test.jsx`):
  - a series spanning 2 days in `7d` mode renders labels derived from the
    actual span (no `7d ago`);
  - existing partial-estimate-note cases keep passing.
- No backend spec is added for `InventoryValueQuery` /
  `ItemPriceHistoryQuery`: their windows are unchanged.

## Implementation Steps

1. `Demo::PriceSeries`: place daily points at `00:00 UTC`; add a private
   `live_point` (at `Time.current`, price = `current_price_cents`);
   rewrite `points_for` to return the daily cutoff..yesterday window plus
   the live point (`all` = every daily point except today + live); make
   `build_hourly` generate `HOURS + 1` points from `now - 24h` to `now`.
2. `Demo::Dataset`: rewrite `portfolio_points` to select summed totals
   whose date is within `range.since_date`..yesterday, then append a live
   point at `Time.current` with the current summed total; keep the
   date-window logic in one helper.
3. Update the demo unit/request specs above (red → green around the new
   point counts and timestamps).
4. `shared/chartConfig.js`: change `generateAxisLabels` to take the
   effective `start`/`end`, derive the unit from the span with the
   downgrade rule, and keep the existing `'all'` behavior.
5. `HeroChart.jsx`: compute `dataMin`/`dataMax`, build the effective
   domain, and pass it to both `XAxis` and `generateAxisLabels`.
6. Add `shared/__tests__/chartConfig.test.js` and the short-series
   `HeroChart` case.
7. Amend `agent/styleguides/fetcher/demo-api.md` and
   `agent/styleguides/core/react-dashboard.md`; log the stale
   `HeroChart`-test claim in `agent/styleguides/fix_me.md`.
8. Re-check `app_fetcher` Sorbet signatures for the new/updated private
   helpers (`srb tc` in the verification step).

## Verification

- `app_fetcher`: `bundle exec rspec spec/queries/demo spec/requests/api/demo`
  (or the Docker equivalent used by `bin/ci`), `bundle exec rubocop`, and
  `bundle exec srb tc`.
- `app_core`: `npm test` (Vitest), `npm run lint`, and the Prettier check
  from `bin/ci`.
- Manual: demo dashboard `7d` — the line starts at the `7d ago` edge and
  ends at `today`; repeat for `30d`, `1y`, `all`, an item-detail chart
  (`24h` included), and the public inventory-detail chart.
- Manual: a real account whose history is shorter than the selected
  period shows labels for the real span and a line touching the left
  edge, with no invented data.

## Risks

- Asserting `at == now` in specs is flaky; use `travel_to` or a
  `be_within(2.seconds)` comparison.
- Demo deltas for item mode change slightly because the oldest `7d`/`30d`
  point moves one day back; the 24h item chart's first value moves from
  `now - 23h` to `now - 24h`.
- The label unit-downgrade threshold (`X_AXIS_TICK_COUNT - 1`) is a
  judgment call; it must keep the full-period labels byte-identical,
  which the new unit tests lock down.
- `1y`/`all` stay at 365 points only as long as the daily series length
  is 365; revisit the window sizing if `DAYS` changes.
- Domain/labels are computed from `Date.now()` at render, so a chart left
  open across a day boundary can shift on re-render — already true today.

## Assumptions

- Recharts 3.10.1 extends an explicit numeric domain with out-of-range
  data when `allowDataOverflow` is false (`parseNumericalUserDomain` →
  `extendDomain`), so the computed extent matches what is drawn.
- The real `/api/v1`/public windows (cutoff-date logs through a live
  "now" point) are the reference contract; no query change is needed
  there.
- Growing demo history payloads by one point is acceptable.
- `Time.current` (UTC) is the correct "now" for the demo live point, as
  in `InventoryValueQuery.live_point`.

## Completion Criteria

- the desired chart behavior is explicit for both demo and real data;
- scope is explicit;
- affected files/components are identified;
- test strategy is defined;
- implementation steps are ordered;
- verification is defined;
- the plan has been written to
  `agent/plans/fix-demo-chart-history-window.md`.

# Implementation Summary

## Implemented

- `Demo::PriceSeries`: daily points now sit at `00:00 UTC`; `points_for`
  returns the range's cutoff day through yesterday plus a live point at
  `Time.current` carrying the anchor price (`all` = every daily point
  except today, plus live). The hourly series now spans the full 24 hours
  (`now - 24h .. now`, 25 points).
- `Demo::Dataset#portfolio_points`: selects summed daily totals from
  `range.since_date` through yesterday and appends a live portfolio point
  at `Time.current` with the summed current total; the now-unused
  `window_days` helper was replaced by `value_point`.
- `HeroChart`: x-domain now starts at the first data point when the
  series is shorter than the period (no empty left strip) and at the
  period boundary otherwise; it ends at `max(now, last point)`.
  `allowDataOverflow` clips points older than the period boundary so a
  mature series still fills the axis up to the first tick. `'all'`
  keeps `dataMin..dataMax`.
- `shared/chartConfig.js`: `generateAxisLabels(period, start, end)`
  derives labels from the effective axis extent, downgrades the unit
  (`d` → `h`, `mo` → `d`) when the span is shorter than four whole units,
  and keeps the canonical labels for full-period series.
- Styleguides: `fetcher/demo-api.md` gained the whole-window +
  live-point rule; `core/react-dashboard.md` gained the hero-chart
  x-axis/label rule; `fix_me.md` logs the stale `HeroChart`-test claim.

## Tests

Added/changed:

- `app_fetcher/spec/queries/demo/price_series_spec.rb` — window sizes
  (25/8/31/365/365), midnight anchoring, cutoff-day starts, live point at
  now carrying the anchor.
- `app_fetcher/spec/queries/demo/dataset_spec.rb` — 7d portfolio window
  (8 points, first `today - 7`, live last point), item history window
  sizes.
- `app_fetcher/spec/requests/api/demo/inventory_values_spec.rb` — 8-point
  7d history starting on `today - 7`.
- `app_fetcher/spec/requests/api/demo/item_prices_spec.rb` — 7d → 8
  points, 24h → 25 points.
- `app_core/app/frontend/shared/__tests__/chartConfig.test.js` (new) —
  canonical labels for full periods, real-span labels for short series,
  unit downgrade, `'all'`.
- `app_core/app/frontend/shared/__tests__/HeroChart.test.jsx` — short
  series gets hour labels, mature series anchors at the period boundary.

Commands executed:

- `docker compose run --rm --no-deps app_fetcher bundle exec rspec` (with
  the test Redis up)
- `docker compose run --rm --no-deps app_fetcher bundle exec rubocop app/queries/demo spec/queries/demo spec/requests/api/demo`
- `docker compose run --rm --no-deps app_fetcher bundle exec srb tc`
- `npx vitest run` (app_core)
- `npm run lint`, `npm run format:check` (app_core)
- `docker compose run --rm --no-deps -e RAILS_ENV=test app_fetcher bin/rails runner ...` — verified the demo payloads: 7d 8 points starting `today - 7 00:00Z`, 30d 31, 1y/all 365, 24h 25, every window ending at `now`.

## Verification

- `app_fetcher`: 567 examples, 0 failures; RuboCop clean on the changed
  dirs; `srb tc` reports no errors.
- `app_core`: 55 test files / 329 tests passed; ESLint reports only the
  pre-existing `tracked_items/TrackedItems.jsx` warning; Prettier clean.
- Manual browser pass on the demo dashboard/item chart is still worth
  doing (not executed here — no browser in this environment).

## Deviations

- The plan's first x-axis wording (`[min(period start, first point),
  max(now, last point)]`) would have made the leftmost label read
  `8d ago` late in the day for daily data. The implementation instead
  keeps the period boundary for mature series and clips older points
  (`allowDataOverflow`), so `7d` mode still reads `7d ago ... today`,
  while short series shrink the axis and are labelled with their real
  span. Plan and styleguide text were updated to match.
- No `app_fetcher` query changes were needed for the real V1/public
  charts: their windows are already correct, and the shared `HeroChart`
  now renders them without an empty strip.

## Remaining Issues

- None blocking. The stale `HeroChart`-has-no-test line in
  `react-dashboard.md` remains logged in `fix_me.md` for a later pass.
