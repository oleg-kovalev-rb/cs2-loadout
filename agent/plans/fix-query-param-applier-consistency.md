---
status: implemented
app: fetcher
goal: Fix the query-param layer's naming and contracts — make SortApplier scope-in/scope-out, resolve periods through PricePeriod + model SUPPORTED_PERIODS/for_period, rename ItemFilterField to ItemFilterOption, and use Pagination#apply in InventoryCatalogQuery
created: 2026-10-19
---

# Development Plan

## Goal

Remove the semantic mismatch called out in review: `Appliers::SortApplier`
must only sort (scope in, scope out), period/range resolution must live on
`PricePeriod` plus model `SUPPORTED_PERIODS`/`for_period` scopes, and
`Appliers::Pagination` must be used consistently as a value object rather
than having callers hand-roll `limit`/`offset`. Rename
`Options::ItemFilterField` to `Options::ItemFilterOption` so the flat
`Options::*` namespace uses one suffix per concern.

`Appliers::FilterApplier` and the `Appliers`/`Pagination` names stay as they
are; no generic `ParamResolver` and no merged sort/filter enum are
introduced.

## Research Summary

Current behavior (verified in code):

- `Appliers::SortApplier.call(raw_value, enum_class:, default:, param_name:)`
  resolves a `T::Enum` and returns the member. It is used both for real
  sorting (`ItemCatalogQuery`, `InventoryCatalogQuery`,
  `InventoryDetailQuery#items_sort`) and for `range` in
  `InventoryDetailQuery` (`PricePeriod`).
- `Appliers::Pagination` is already a value object with `#apply(scope)`;
  `ItemCatalogQuery` and `InventoryDetailQuery` use it, but
  `InventoryCatalogQuery` still calls `.limit(...).offset(...)` by hand.
- `InventoryValuation.series(steam_id, period, current:)` loads all
  `InventoryValueLog` rows for a `steam_id` and filters them in Ruby via
  `log_date >= period.duration&.ago&.to_date`.
- `Api::V1::InventoryValuesController` and
  `Api::V1::ItemPricesController#history` each define their own
  `ALLOWED_PERIODS` and inline `PricePeriod.try_deserialize(...)` branch.
- `InventoryDetailQuery#total_value_cents` comes from
  `InventoryValuation.current(user_inventory)` (the live last-known-price
  sum), not from a log. `range` only affects `InventoryValuation.series`.
- `Options::ItemFilterField` is referenced by `ItemCatalogQuery`,
  `Appliers::FilterApplier` specs, and `agent/styleguides/`.
- `InventoryValueLog` and `PriceLog` have generated Tapioca DSL RBIs under
  `app_fetcher/sorbet/rbi/dsl/`.

## Expected Behavior

- `range`/`period` resolution is separate from sorting. An invalid value
  still produces `Unsupported <param>: <value>`; `InventoryDetailQuery`
  raises `Api::Public::UnsupportedParamError`, the two `Api::V1`
  controllers keep rendering `400` with the same message.
- `InventoryDetailQuery` accepts only periods supported by
  `InventoryValueLog` (no `24h`); `InventoryValuesController` accepts the
  same set; `ItemPricesController#history` accepts all `PricePeriod` values
  including `24h`.
- History series queries filter in SQL through `for_period` rather than
  loading every log and rejecting in Ruby. `range=all` means no cutoff.
- `InventoryDetailQuery#total_value_cents` is unchanged: still the live
  valuation, independent of the selected range.
- `Appliers::SortApplier.call(scope, params, enum_class:, default:,
  param_name: "sort")` returns the sorted relation; it raises
  `Api::Public::UnsupportedParamError` for an invalid present value and
  applies `default` when the param is absent.
- `InventoryCatalogQuery` pages through `pagination.apply(scope)`.
- `Options::ItemFilterOption` replaces `Options::ItemFilterField`
  everywhere; sort behavior and `FilterApplier` behavior are unchanged.

## Scope

### In Scope

- `PricePeriod#since` / `#since_date` and a period-specific
  `PricePeriod.resolve`.
- `InventoryValueLog::SUPPORTED_PERIODS` + `scope :for_period`.
- `PriceLog::SUPPORTED_PERIODS` + `scope :for_period`.
- `InventoryValuation.series` using `for_period`.
- `InventoryDetailQuery` period resolution and SortApplier call-site
  update.
- `InventoryCatalogQuery` / `ItemCatalogQuery` SortApplier call-site
  updates; `InventoryCatalogQuery` pagination via `apply`.
- `InventoryValuesController` / `ItemPricesController#history` period
  resolution + `SUPPORTED_PERIODS`.
- Rename `Options::ItemFilterField` → `Options::ItemFilterOption`
  (class, file, spec, references).
- SortApplier scope-in/scope-out rewrite and spec rewrite.
- Update affected query/model/request specs.
- Regenerate Tapioca DSL RBIs for `InventoryValueLog` and `PriceLog`.
- Update `agent/styleguides/fetcher/list-query-objects.md`,
  `agent/styleguides/ruby-sorbet.md`, and the period references in
  `agent/styleguides/fetcher/public-api-controllers.md`.

### Out of Scope

- Renaming `Appliers::Pagination`, `Appliers::FilterApplier`, or the
  `Appliers::` namespace.
- A generic `ParamResolver`, a merged sort/filter enum, or merging
  `Item`/`Inventory` options.
- `Options::ItemSortOption` / `Options::InventorySortOption` behavior.
- Changing what `total_value_cents` means (live last-known-price sum).
- Reworking the 30-day `PriceHistoryCache` path in
  `ItemPricesController#history`.
- Editing historical ADRs; `list-query-objects-layer.md` remains the
  record of the original decision.

## Implementation Approach

### Periods

`PricePeriod` owns the period → cutoff conversion:

- `#since` → `T.nilable(ActiveSupport::TimeWithZone)` (`duration&.ago`);
- `#since_date` → `T.nilable(Date)` (`since&.to_date`, nil for `all`);
- `.resolve(raw_value, supported:, default:)` → `T.nilable(PricePeriod)`,
  returning nil for an unknown *or unsupported* value, and `default` when
  the raw value is blank. This is domain-specific period resolution, not a
  generic param resolver; callers decide how to report failure.

Models own their own supported vocabulary and cutoff query:

- `InventoryValueLog::SUPPORTED_PERIODS` = 7d/30d/1y/all (no 24h),
  `scope :for_period` filters `log_date` by `period.since_date` when present;
- `PriceLog::SUPPORTED_PERIODS` = all five periods, `scope :for_period`
  filters `created_at` by `period.since` when present.

`InventoryValuation.series` changes from load-all-then-Ruby-filter to
`InventoryValueLog.where(steam_id:).for_period(period).order(:log_date)`.

`InventoryDetailQuery` resolves `range` with
`PricePeriod.resolve(params[:range], supported:
InventoryValueLog::SUPPORTED_PERIODS, default: PricePeriod::SevenDays)`
and raises `Api::Public::UnsupportedParamError` on nil. The two
controllers use the same resolver with their own model constant and keep
their existing inline `render ... :bad_request` branches.

### SortApplier

Rewrite to:

```text
SortApplier.call(scope, params, enum_class:, default:, param_name: "sort")
  → raw = params[param_name]
  → option = enum_class.try_deserialize(raw.presence || default.serialize)
  → raise UnsupportedParamError unless option
  → option.apply(scope)   # localized T.unsafe at the deserialization boundary
```

The return type is `ActiveRecord::Relation`; the `T.type_parameter(:Enum)`
contract is removed. Call sites pass the scope they already built:
`FilterApplier` → `SortApplier` → `Pagination#apply` in `ItemCatalogQuery`,
`SortApplier` → `Pagination#apply` in `InventoryCatalogQuery` and
`InventoryDetailQuery#top_items`.

### Options

Rename class/file/spec only: `ItemFilterField` → `ItemFilterOption`. Keep
the classes `ItemSortOption`, `InventorySortOption`, and `ItemFilterOption`
flat under `Options::`, one resource per concern.

## Files To Modify

- `app_fetcher/app/models/price_period.rb` — add `#since`, `#since_date`,
  `.resolve`.
- `app_fetcher/app/models/inventory_value_log.rb` — add
  `SUPPORTED_PERIODS` and `scope :for_period`.
- `app_fetcher/app/models/price_log.rb` — add `SUPPORTED_PERIODS` and
  `scope :for_period`.
- `app_fetcher/app/queries/inventory_valuation.rb` — use `for_period` in
  `.series`; no change to `total`/`current`.
- `app_fetcher/app/queries/appliers/sort_applier.rb` — scope-in/scope-out
  contract.
- `app_fetcher/app/queries/inventory_catalog_query.rb` — SortApplier call
  + `pagination.apply`.
- `app_fetcher/app/queries/item_catalog_query.rb` — SortApplier call +
  `ItemFilterOption`.
- `app_fetcher/app/queries/inventory_detail_query.rb` — resolve `range`
  independently, SortApplier for `items_sort`, `for_period` via series.
- `app_fetcher/app/queries/options/item_filter_option.rb` — renamed from
  `item_filter_field.rb`, class renamed.
- `app_fetcher/app/controllers/api/v1/inventory_values_controller.rb` —
  replace `ALLOWED_PERIODS` with `InventoryValueLog::SUPPORTED_PERIODS` and
  `PricePeriod.resolve`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` — replace
  `ALLOWED_PERIODS` with `PriceLog::SUPPORTED_PERIODS` and
  `PricePeriod.resolve`; use `for_period` for the non-cached branch.
- `app_fetcher/spec/models/price_period_spec.rb` — `since`/`since_date`/
  `resolve`.
- `app_fetcher/spec/models/inventory_value_log_spec.rb` — period scope.
- `app_fetcher/spec/models/price_log_spec.rb` — create if absent; period
  scope.
- `app_fetcher/spec/queries/appliers/sort_applier_spec.rb` — rewrite for
  relation-in/relation-out.
- `app_fetcher/spec/queries/appliers/filter_applier_spec.rb` — renamed
  enum reference.
- `app_fetcher/spec/queries/options/item_filter_option_spec.rb` — renamed
  from `item_filter_field_spec.rb`.
- `app_fetcher/spec/queries/inventory_catalog_query_spec.rb` — pagination
  through `apply` (page/offset coverage).
- `app_fetcher/spec/queries/inventory_detail_query_spec.rb` — period
  resolution/`for_period`, unsupported 24h, live total independence.
- `app_fetcher/spec/queries/inventory_valuation_spec.rb` — series filtering
  through the scope.
- `app_fetcher/spec/queries/item_catalog_query_spec.rb` — unchanged
  behavior, verify invalid sort still raises.
- `app_fetcher/spec/requests/api/public/inventories_spec.rb` — invalid
  `range` and 24h rejection coverage.
- `app_fetcher/spec/requests/api/v1/inventory_values_spec.rb` — invalid
  period and 24h rejection coverage.
- `app_fetcher/spec/requests/api/v1/item_prices_spec.rb` — 24h remains
  supported through the new resolver.
- `app_fetcher/sorbet/rbi/dsl/inventory_value_log.rbi` — regenerate.
- `app_fetcher/sorbet/rbi/dsl/price_log.rbi` — regenerate.
- `agent/styleguides/fetcher/list-query-objects.md` — new SortApplier
  contract, `FilterOption` name, period/`SUPPORTED_PERIODS`/`for_period`,
  `pagination.apply`.
- `agent/styleguides/ruby-sorbet.md` — remove the
  `T.type_parameter(:Enum)` exception, update the generic-deserialization
  `T.unsafe` exception and period/`ALLOWED_PERIODS` guidance.
- `agent/styleguides/fetcher/public-api-controllers.md` — update
  closed-enum/period references from `ALLOWED_PERIODS` to
  `SUPPORTED_PERIODS`; clarify `SortApplier` handles sort only.

## Files To Create

- `app_fetcher/app/queries/options/item_filter_option.rb` — renamed
  `T::Enum`; replaces `item_filter_field.rb`.
- `app_fetcher/spec/queries/options/item_filter_option_spec.rb` — renamed
  spec.
- `app_fetcher/spec/models/price_log_spec.rb` — model-level coverage for
  the new scope (directory currently has no `PriceLog` spec).

## Test Plan

Model specs:

- `PricePeriod#since`/`#since_date`: 24h/7d/30d/1y produce the expected
  cutoff; `all` returns nil.
- `PricePeriod.resolve`: blank → default; supported value → member;
  unknown → nil; known but unsupported (24h for inventory periods) → nil.
- `InventoryValueLog.for_period`: includes `log_date` on/after the cutoff
  and excludes earlier rows; `all` returns every row.
- `PriceLog.for_period`: same semantics keyed on `created_at`; `24h`
  includes only recent rows.

Applier/query specs:

- `Appliers::SortApplier`: default ordering, recognized ordering, invalid
  value raises `UnsupportedParamError`, custom `param_name` appears in the
  message, and the return value is a relation.
- `Options::ItemFilterOption` spec unchanged except the class name.
- `InventoryCatalogQuery`: page 2 respects offset/limit; sort behavior
  unchanged.
- `InventoryDetailQuery`: default 7d; `all`; 24h rejected; invalid
  `range` raises the same message; `total_value_cents` still comes from
  live valuation when the only stored logs are outside the range.
- `InventoryValuation.series`: period filtering still behaves as before,
  now through `for_period`.

Request specs:

- Public inventory detail: `range=all` accepted, invalid and `24h`
  rejected with `400` and `Unsupported range: ...`.
- V1 inventory values: default `all`, `30d`/`7d` filtering, invalid and
  `24h` rejected.
- V1 item history: `24h` still returns only in-window points; invalid
  period still `400`.

## Implementation Steps

1. Add `PricePeriod#since`, `#since_date`, `.resolve` and model specs.
2. Add `SUPPORTED_PERIODS`/`for_period` to `InventoryValueLog` and
   `PriceLog` with model specs.
3. Rewrite `Appliers::SortApplier` and its spec; update `ItemCatalogQuery`,
   `InventoryCatalogQuery`, and `InventoryDetailQuery` call sites.
4. Rename `Options::ItemFilterField` to `Options::ItemFilterOption` across
   class, file, spec, and `FilterApplier` spec.
5. Replace `InventoryCatalogQuery`'s manual limit/offset with
   `pagination.apply`.
6. Switch `InventoryValuation.series` to `for_period`.
7. Switch `InventoryDetailQuery` `range` resolution to `PricePeriod` and
   add period/24h/history specs.
8. Switch both `Api::V1` controllers to `SUPPORTED_PERIODS` +
   `PricePeriod.resolve`; use `for_period` in item history; add request
   coverage.
9. Regenerate Tapioca DSL RBIs for the two models.
10. Update the three styleguides.
11. Run the focused specs, then the full `app_fetcher` suite, RuboCop, and
    `srb tc`.

## Verification

- `docker compose run --rm app_fetcher bundle exec rspec spec/models/price_period_spec.rb spec/models/inventory_value_log_spec.rb spec/models/price_log_spec.rb spec/queries spec/requests/api/v1/inventory_values_spec.rb spec/requests/api/v1/item_prices_spec.rb spec/requests/api/public/inventories_spec.rb`
- `docker compose run --rm app_fetcher bundle exec rspec`
- `docker compose run --rm app_fetcher bin/rubocop`
- `docker compose run --rm app_fetcher bundle exec srb tc`
- Confirm `git diff` shows only the intended rename, scope, contract, and
  documentation changes.

## Risks

- `Api::V1` inherits `ApplicationController`, which only rescues
  `StandardError`; period resolution there must return nil and keep the
  inline `:bad_request` branch, not raise `Api::Public::UnsupportedParamError`.
- `scope :for_period` must not force a cutoff for `PricePeriod::All`;
  otherwise history silently loses rows.
- The RBI regeneration must run after the scopes exist, or `srb tc` will
  not see `Model.for_period`.
- Renaming `ItemFilterField` is a file/class rename; a stale Zeitwerk
  constant or spec filename will fail loudly under `srb tc`/specs.

## Applicable Styleguides

- `agent/styleguides/fetcher/list-query-objects.md` — constrains the
  `SortApplier` contract, `Options::ItemFilterOption` naming, period
  resolution through `PricePeriod.resolve` + `SUPPORTED_PERIODS`/
  `for_period`, and `Pagination#apply` in every query object.
- `agent/styleguides/ruby-sorbet.md` — constrains sigils/sigs, the
  localized `T.unsafe` at the `try_deserialize` → `#apply` boundary,
  `T::Enum`/period handling, and Tapioca DSL regeneration.
- `agent/styleguides/fetcher/public-api-controllers.md` — constrains the
  closed-enum validation split between `SortApplier` and
  `PricePeriod.resolve`, and the resulting `400` shape.
- `agent/styleguides/rails-layering.md` — constrains the
  Controller → query object → model direction; no controller may absorb
  query logic.
- `agent/styleguides/rspec-conventions.md` — constrains spec levels,
  arrange/act/assert structure, aggregate failures, and the rule against
  stubbing the database.
- `agent/styleguides/ci-and-coverage.md` — constrains verification through
  `docker compose` and the same checks CI runs.

## Assumptions

- `InventoryDetailQuery#total_value_cents` keeps its current source, the
  live `InventoryValuation.current` sum, independent of `range`. The plan
  request phrased it as "the last log outside the selected range", but the
  current code (after `inventory-valuation-consistency`) already uses the
  live sum; this plan preserves that behavior rather than reintroducing a
  log-based total.
- `PricePeriod.resolve` is a domain-specific resolver on `PricePeriod`,
  not the generic `ParamResolver` the review asked to avoid.
- `ItemPricesController#history` keeps its 30-day cache branch; only the
  non-cached branch moves to `PriceLog.for_period`.

## Completion Criteria

- `SortApplier` no longer resolves or returns enums; it sorts a scope.
- Period resolution is shared through `PricePeriod.resolve` +
  model `SUPPORTED_PERIODS`; history uses `for_period`.
- `InventoryCatalogQuery` pages through `Pagination#apply`.
- `Options::ItemFilterOption` is the only name in code, specs, and
  styleguides.
- Tapioca RBIs and styleguides are updated.
- Focused and full `app_fetcher` specs, RuboCop, and `srb tc` pass.

## Implementation Summary

### Implemented

- `PricePeriod` now exposes `#since`, `#since_date`, and the
  domain-specific `.resolve(raw_value, supported:, default:)`.
- `InventoryValueLog` owns `SUPPORTED_PERIODS` (no `24h`) and
  `scope :for_period` over `log_date`; `PriceLog` owns all periods and
  `scope :for_period` over `created_at`.
- `InventoryValuation.series` filters logs through `for_period` in SQL.
- `Appliers::SortApplier` is scope-in/scope-out
  (`call(scope, params, enum_class:, default:, param_name:) →
  ActiveRecord::Relation`), with no `T.type_parameter` and no period
  resolution.
- `InventoryCatalogQuery` uses `pagination.apply(scope)`;
  `ItemCatalogQuery` and `InventoryDetailQuery` keep it.
- `InventoryDetailQuery` resolves `range` via `PricePeriod.resolve`
  against `InventoryValueLog::SUPPORTED_PERIODS` and raises
  `Api::Public::UnsupportedParamError` on nil.
- Both `Api::V1` controllers use `PricePeriod.resolve` + the owning
  model's `SUPPORTED_PERIODS`; item history uses `PriceLog.for_period`.
- `Options::ItemFilterField` was renamed to
  `Options::ItemFilterOption` across class, file, spec, and references.
- Tapioca DSL RBIs were regenerated for `InventoryValueLog` and
  `PriceLog`.
- The three affected styleguides were amended before implementation.

### Tests

Added or updated:

- `spec/models/price_period_spec.rb` — `since`, `since_date`, `resolve`.
- `spec/models/inventory_value_log_spec.rb` — `for_period` and
  `SUPPORTED_PERIODS`.
- `spec/models/price_log_spec.rb` — new; `for_period` and
  `SUPPORTED_PERIODS`.
- `spec/queries/appliers/sort_applier_spec.rb` — rewritten for
  relation-in/relation-out, default, invalid value, `param_name`.
- `spec/queries/options/item_filter_option_spec.rb` — renamed.
- `spec/queries/appliers/filter_applier_spec.rb` — renamed enum.
- `spec/queries/inventory_catalog_query_spec.rb` — page-2 offset.
- `spec/queries/inventory_detail_query_spec.rb` — 24h rejection and
  range-independent live total.
- `spec/requests/api/public/inventories_spec.rb` — 24h range rejection.
- `spec/requests/api/v1/inventory_values_spec.rb` — 24h period rejection.

Commands executed:

```text
docker compose -f docker-compose.yml -f docker-compose.ci.yml run --rm --no-deps app_fetcher bundle exec rspec
docker compose -f docker-compose.yml -f docker-compose.ci.yml run --rm --no-deps app_fetcher bundle exec srb tc
docker compose -f docker-compose.yml -f docker-compose.ci.yml run --rm --no-deps app_fetcher bin/rubocop
```

### Verification

- Full `app_fetcher` suite: 469 examples, 0 failures.
- `srb tc`: no errors.
- RuboCop: 153 files inspected, no offenses.
- `sorbet/rbi/dsl/inventory_value_log.rbi` and `price_log.rbi` now
  expose `for_period`.

### Deviations

- `ItemCatalogQuery` computes its aggregate counts before applying the
  sort. Applying `ORDER BY change_24h_cents` before the aggregate `pluck`
  caused a PostgreSQL `GROUP BY` error; sorting the filtered scope just
  before pagination preserves both the stats and the ordering.
- `InventoryCatalogQuery` passes the plucked column list as one array to
  `pluck` instead of splatting it, which avoids Sorbet's
  "splats are only supported where the size is known statically" error.
- `total_value_cents` remains the live `InventoryValuation.current` sum,
  not a stored log value, as noted in Assumptions.

### Remaining Issues

None.
