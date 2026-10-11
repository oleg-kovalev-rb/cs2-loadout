---
status: implemented
app: fetcher
goal: Skip scheduling price updates for non-marketable items, via a model-owned scope composition instead of ad-hoc scheduler SQL
created: 2026-10-11
---

# Development Plan

## Goal

`PriceScheduler` should stop enqueuing `PriceUpdateWorker` for `Item`s that
aren't marketable on Steam (medals, pins, etc.) — those calls can never
succeed and burn the shared, global Steam price rate-limit budget (`Prop`:
20/min, 1000/day) for nothing. The filtering logic — "is this item
marketable" and "does this item's price need refreshing" — should live
entirely on `Item` as composed scopes, so `PriceScheduler#perform` itself
contains zero query/aggregation logic, just a single scope call and a
fan-out loop.

## Expected Behavior

- Normal: an `Item` with `metadata["marketable"] == true` that is stale
  (`updated_at` older than the staleness threshold) or has no price yet
  (`current_price_cents IS NULL`) gets a `PriceUpdateWorker` job enqueued,
  exactly as today.
- Changed: an `Item` with `metadata["marketable"] == false` is **never**
  enqueued by `PriceScheduler`, regardless of staleness or missing price.
- Edge case: an `Item` whose `metadata` has no `marketable` key at all
  (hash doesn't contain the key) is treated the same as `marketable:
  false` — excluded. This can't currently occur for any `Item` created
  through the live code path (`UserInventorySyncService` always passes an
  explicit `marketable:` boolean into `ItemParser.parse`, default `false`)
  and the dev DB has been reset since the key was introduced, but the
  scope's own behavior should still be well-defined and tested rather than
  left as "whatever `nil` happens to do."
- Unchanged: the staleness/no-price condition itself (`updated_at <
  1.hour.ago OR current_price_cents IS NULL`) is not changing — only
  relocating from the scheduler into the model, and only `AND`-ed with the
  new marketability filter.
- Unchanged: `PriceUpdateWorker`, `Steam::Client`, `Prop` throttling,
  `PriceUpdateService` — nothing downstream of the scheduler's query
  changes.

## Scope

### In Scope

- `Item.marketable` — new scope, filters to items with
  `metadata["marketable"] == true`. Named exactly as requested by the
  task, kept as its own standalone public scope (not inlined only inside
  a combined scope) so the follow-up "Tiered price-fetch priority" task
  can reuse it directly.
- `Item.stale_or_unpriced` — new scope, extracted verbatim (same
  condition, same 1-hour threshold) from `PriceScheduler`'s current
  `.where(...)` call. Pure relocation, not a behavior change.
- `Item.due_for_price_update` — new scope composing the two above
  (`marketable.stale_or_unpriced`). This is the single scope
  `PriceScheduler` calls.
- `PriceScheduler#perform` — collapses to `Item.due_for_price_update
  .find_each { |item| PriceUpdateWorker.perform_async(item.id) }`, no
  inline query/aggregation logic left in the scheduler.
- `spec/factories/items.rb` — default `:item` factory gains an explicit
  `metadata: { marketable: true }` (today it builds items with `metadata:
  {}`, which would make every existing `create(:item)` in the suite
  invisible to the new `marketable` scope); a new `:non_marketable` trait
  for the negative-path tests.
- `spec/models/item_spec.rb` — new file (first model spec for `Item`),
  covering all three scopes.
- `spec/schedulers/price_scheduler_spec.rb` — new context asserting a
  stale-but-non-marketable item is never enqueued.

### Out of Scope

- Anything that *uses* `marketable` for priority/ordering (the "Tiered
  price-fetch priority" follow-up task) — this plan only gates whether an
  item is scheduled at all, not in what order.
- Backfilling or data-migrating any pre-existing `Item` row — moot, per
  the project owner: the dev DB was reset after the prerequisite
  marketability-capture task, so every current row already has an
  explicit `marketable` boolean.
- Any change to `PriceUpdateWorker`, `Steam::Client`, `PriceUpdateService`,
  or the Prop rate-limit configuration itself.
- Any change to `InventoryValueScheduler` or other schedulers — only
  `PriceScheduler` is in scope.
- A Sorbet `sig` convention for `scope` lambdas in general — this is the
  first `scope` in the codebase; whether/how to type it is left for
  `styleguides-check` to decide, not pre-decided here.

## Implementation Approach

Move all of the scheduler's query logic into `Item` as three composed
scopes, per the project owner's explicit direction (the current raw-SQL
`.where(...)` in `PriceScheduler` predates the `marketable` concept
existing at all — it's being "caught up" now that the concept exists, not
newly designed).

- **`Item.marketable`**: filter via jsonb containment —
  `where("metadata @> ?", { marketable: true }.to_json)`. Chosen over a
  `->>` text-equality check (`metadata->>'marketable' = 'true'`) for two
  reasons: `marketable` is stored as a real JSON boolean (confirmed via
  `ItemParser`/existing specs — `expect(backfilled.metadata["marketable"])
  .to be(true)`, not a string), so containment is the semantically direct
  comparison; and `items`'s existing `index_items_on_metadata` is a plain
  GIN index on the whole `metadata` column, which supports containment
  (`@>`) queries, not arbitrary `->>` text comparisons — so this shape can
  actually use the index that's already there.
- **`Item.stale_or_unpriced`**: same condition as today
  (`"updated_at < ? OR current_price_cents IS NULL"`), moved as-is. The
  `1.hour` threshold becomes a named constant on `Item`
  (`PRICE_STALE_AFTER`, `T.let`-wrapped per `ruby-sorbet.md`) since it's
  now a model-level business rule with a name, not an inline literal
  buried in a scheduler.
- **`Item.due_for_price_update`**: composes the two above —
  `marketable.stale_or_unpriced` — plain `scope` chaining, as originally
  planned.
- **All three implemented as `scope` macros, per the original plan — not
  plain class methods** (an intermediate pivot during implementation
  tried class methods instead, to work around a `srb tc` gap; that pivot
  was itself reverted once the real fix was found — see the Implementation
  Summary's Deviations for the full account). The real fix:
  `app_fetcher`'s Gemfile already has `tapioca` (dev group) — the
  actively-maintained tool for generating DSL RBIs for ActiveRecord's
  dynamic methods (`scope`, `store_accessor`, associations, etc.); it had
  simply never been run for any app model. Running `bundle exec tapioca
  dsl Item` generates `sorbet/rbi/dsl/item.rbi`, which makes all three
  scopes (and `store_accessor`'s existing `marketable`/`weapon_type`/etc.
  keys, and even `Item`'s plain column attributes) fully resolvable under
  `srb tc`, both chained internally and called externally from
  `PriceScheduler`. No new gem needed — adding `sorbet-rails` alongside
  the already-present `tapioca` would have been redundant and
  architecturally messy (two DSL-RBI generators doing overlapping work).
- **`PriceScheduler#perform`** becomes a one-liner query + fan-out, with
  no SQL fragment of its own — consistent with
  `.claude/styleguides/fetcher/architecture-layers.md`'s framing of a
  scheduler as something that "queries local model state" (now literally
  just naming that query on the model) rather than constructing it
  inline.
- A missing `marketable` key is excluded by construction: jsonb
  containment (`metadata @> '{"marketable": true}'`) simply does not match
  a hash that lacks the key, so no special nil-handling branch is needed
  in the scope itself — the "missing key → excluded" edge case is a
  natural consequence of the containment query, not a separate code path
  to write.

## Files To Modify

- `app_fetcher/app/models/item.rb`
  - Add `PRICE_STALE_AFTER = T.let(1.hour, ActiveSupport::Duration)`.
  - Add `scope :marketable, -> { where("metadata @> ?", { marketable: true
    }.to_json) }`.
  - Add `scope :stale_or_unpriced, -> { where("updated_at < ? OR
    current_price_cents IS NULL", PRICE_STALE_AFTER.ago) }`.
  - Add `scope :due_for_price_update, -> { marketable.stale_or_unpriced }`.
  - Reason: centralizes the "does this item need a price refresh"
    business rule on the model, per the project owner's explicit
    direction, instead of split between a scheduler's raw SQL and a
    model-level concept that didn't exist when that SQL was written.
- `app_fetcher/app/schedulers/price_scheduler.rb`
  - Replace `Item.where("updated_at < ? OR current_price_cents IS NULL",
    1.hour.ago)` with `Item.due_for_price_update`.
  - Reason: removes all query/aggregation logic from the scheduler; it
    now only names the scope and fans out, matching the project owner's
    "no aggregation logic inside the worker" instruction.
- `app_fetcher/spec/factories/items.rb`
  - Add `metadata { { marketable: true } }` to the base `:item` factory.
  - Add a `trait :non_marketable do; metadata { { marketable: false } };
    end`.
  - Reason: every existing spec using a plain `create(:item)`/`build(:item)`
    (scheduler spec, any future consumer) must remain marketable by
    default, or the new `marketable` scope would silently exclude them
    and break existing assertions about what gets enqueued. Confirmed via
    grep that no existing spec asserts `item.metadata == {}` or otherwise
    depends on an empty default metadata hash.
- `app_fetcher/spec/schedulers/price_scheduler_spec.rb`
  - Add a new context: a stale, `:non_marketable` item is not enqueued.
  - Existing contexts (`stale_item`, `unpriced_item`, `fresh_item`, the
    3-item list) need no behavior change — they'll pick up `marketable:
    true` automatically from the updated factory default — but should be
    re-run to confirm.
  - Reason: keeps integration-level coverage of the task's literal,
    user-facing behavior ("non-marketable items are not scheduled"), not
    just a model-level unit test of the scope in isolation.

## Files To Create

- `app_fetcher/spec/models/item_spec.rb`
  - Responsibility: unit-test the three new scopes directly on `Item`
    (first model spec for `Item`; matches `rspec-conventions.md`'s
    Model → Unit spec-level mapping).
  - Reason: `PriceScheduler`'s own spec is the right place to assert
    scheduler-level behavior, but the scopes themselves are reusable model
    behavior (the `marketable` scope in particular is meant to be reused
    by the "Tiered price-fetch priority" follow-up) and deserve direct,
    isolated coverage independent of the scheduler.

## Test Plan

`spec/models/item_spec.rb`:

- `describe ".marketable"`
  - an item with `metadata: { marketable: true }` is included;
  - an item with `metadata: { marketable: false }` is excluded;
  - an item with `metadata: {}` (no `marketable` key at all) is excluded
    — guards the edge case explicitly, even though it's unreachable via
    the current live code path.
- `describe ".stale_or_unpriced"`
  - an item with a stale `updated_at` is included;
  - an item with `current_price_cents: nil` is included;
  - a fresh item with a price is excluded.
  (Mirrors the three existing `price_scheduler_spec.rb` cases, now also
  covered directly at the model layer since the condition now lives
  there.)
- `describe ".due_for_price_update"`
  - marketable + stale → included;
  - non-marketable + stale → excluded (the core behavior this task adds);
  - marketable + fresh + priced → excluded.

`spec/schedulers/price_scheduler_spec.rb`:

- New context: `with a stale, non-marketable item` → `PriceUpdateWorker`
  is not enqueued for it.
- Existing three contexts re-verified to still pass against the new
  factory default and the scheduler's new query.

All new test data via `FactoryBot` (`:non_marketable` trait, existing
`:stale`/`:without_price` traits), per `rspec-conventions.md` — no new
fixtures.

## Implementation Steps

1. Write RED spec for `Item.marketable` in `spec/models/item_spec.rb`
   (including the "missing key" case).
2. Implement `Item.marketable` (jsonb containment scope).
3. Write RED spec for `Item.stale_or_unpriced`.
4. Implement `PRICE_STALE_AFTER` constant and `Item.stale_or_unpriced`,
   extracted from `PriceScheduler`'s current `.where(...)`.
5. Write RED spec for `Item.due_for_price_update`.
6. Implement `Item.due_for_price_update` as `marketable.stale_or_unpriced`.
7. Run `bundle exec tapioca dsl Item` to generate `sorbet/rbi/dsl/item.rbi`
   (needed so `srb tc` can resolve the three new scopes, both chained
   internally and called externally from `PriceScheduler`); commit the
   generated file.
8. Update `spec/factories/items.rb`: default `metadata: { marketable: true
   }`, add `:non_marketable` trait.
9. Update `PriceScheduler#perform` to use `Item.due_for_price_update
   .find_each`, removing the inline SQL entirely.
10. Add the new non-marketable context to
    `spec/schedulers/price_scheduler_spec.rb`; re-run its existing contexts
    against the updated factory/scheduler.
11. Run the full `app_fetcher` suite, `srb tc`, and `rubocop` on touched
    files; diff against baseline the same way the prerequisite
    marketability-capture task did; log any newly-surfaced (not newly
    introduced) `srb tc` error in files outside this change's scope to
    `fix_me.md` rather than fixing it inline.

## Verification

- `bundle exec rspec spec/models/item_spec.rb spec/schedulers/price_scheduler_spec.rb`,
  then the full `app_fetcher` suite for regressions.
- `srb tc` on touched `# typed: strict` files (`item.rb`,
  `price_scheduler.rb`); diff the error count/list against the
  pre-change baseline, same process as the prerequisite plan — any
  genuinely new error gets logged in `fix_me.md`, not silently fixed,
  unless small and isolated to a line this plan already touches.
- `rubocop` on every touched file.
- No `app_core`/browser verification needed — no API response shape or
  frontend change; this is an internal scheduling-query change only.

## Risks

- **Resolved during implementation, not left as a risk**: the plan's
  `scope :marketable`/`:stale_or_unpriced`/`:due_for_price_update` macros,
  as first written, broke `srb tc` — it couldn't resolve `marketable`
  called from inside `due_for_price_update`'s own lambda, nor
  `Item.due_for_price_update` called from `PriceScheduler`. Root cause:
  `app_fetcher`'s Gemfile already has `tapioca` (the standard DSL-RBI
  generator for ActiveRecord dynamics), but it had never been run for any
  app model, so Sorbet had zero visibility into `scope`/`store_accessor`
  output anywhere — confirmed via grep that no production code had ever
  called a `store_accessor`-generated reader either, which is why this
  gap was invisible until `scope` needed exactly that. Two intermediate
  fixes were tried and reverted (a `ruby-sorbet.md` sig-exemption for
  macro-generated methods; then plain `class << self` methods instead of
  `scope`) before landing on the actual fix: run `bundle exec tapioca dsl
  Item` and commit the generated `sorbet/rbi/dsl/item.rbi`. This let the
  plan's original `scope`-based design stand unchanged. See the
  Implementation Summary's Deviations for the full account, including two
  newly-*surfaced* (not newly-introduced) `srb tc` errors in unrelated
  files, now logged in `fix_me.md`.
- **Naming overlap, not a conflict**: `item.marketable` (instance method,
  from the existing `store_accessor`, returns the raw boolean/nil) and
  `Item.marketable` (new class-level scope) share a name but have
  different receivers — no functional collision, but worth a one-line
  note in the implementation commit since it reads unusually on first
  glance.
- **jsonb containment depends on exact JSON type**: the `marketable`
  scope only matches a real JSON boolean `true`, not a string `"true"` or
  integer `1`. Confirmed this is how every current write path
  (`ItemParser`) already stores it; if a future write path ever stored a
  different representation, the scope would silently stop matching it.
  Not defended against here — no such path exists today.
- **Factory-wide default change**: adding `metadata: { marketable: true }`
  to the base `:item` factory affects every spec using `create(:item)`/
  `build(:item)`, not just the scheduler spec. A grep confirmed no
  existing spec depends on a bare/empty `metadata` hash, but this is
  flagged since it's a blanket default change rather than a narrowly
  scoped one.
- Pre-existing-data nil-handling (a deployed `Item` row predating the
  `marketable` key) is not a current risk per the project owner's
  confirmation (dev DB reset) — the scope's "missing key → excluded"
  behavior is simply what happens if that situation ever recurs post-
  deploy, not something specially engineered for it.

## Assumptions

- `due_for_price_update` as the composed scope's name is acceptable;
  there's no existing naming convention to anchor it to since no scope
  existed in this codebase before. Trivially renamable at
  `styleguides-check`/`implement-plan` if a different name is preferred.
- Keeping `Item.marketable` as its own standalone scope (rather than only
  ever using it inlined inside `due_for_price_update`) is the right call
  for reuse by the "Tiered price-fetch priority" follow-up task mentioned
  in `.claude/plans/steam-marketability-rarity-metadata.md`'s Remaining
  Issues — that task isn't implemented yet, so this is an assumption
  about its future shape, not a verified requirement.

## Completion Criteria

- [x] Desired behavior explicit (Expected Behavior)
- [x] Scope explicit (Scope)
- [x] Affected files/components identified (Files To Modify / To Create)
- [x] Test strategy defined (Test Plan)
- [x] Implementation steps ordered (Implementation Steps)
- [x] Verification defined (Verification)
- [x] Plan written to `.claude/plans/skip-non-marketable-items.md`

## Applicable Styleguides

- `.claude/styleguides/ruby-sorbet.md` — constrains `app_fetcher/app/models/item.rb`:
  `PRICE_STALE_AFTER` must be `T.let`-wrapped (the existing
  class-constant rule). The three `scope` declarations don't need
  individual `sig`s (they're not `def`s), but this check's own addition
  to the guide now requires regenerating the model's DSL RBI via
  `bundle exec tapioca dsl Item` whenever a model gains a `scope`/new
  `store_accessor` key/association — done here, committed as
  `sorbet/rbi/dsl/item.rbi` (see Deviations for why this, not a
  `ruby-sorbet.md` sig-exemption, is the real fix). `# typed: strict`/
  `extend T::Sig` continue to apply to both touched files as
  already-established file-level requirements.
- `.claude/styleguides/rails-layering.md` — confirms the plan's core
  design choice: the "does this item need a price refresh" query/business
  rule belongs on the model (`Item`'s new scopes), not duplicated or
  decided in the controller/scheduler layer.
- `.claude/styleguides/fetcher/architecture-layers.md` — confirms
  `PriceScheduler` remains Scenario 2's entry point ("query local model
  state only, synchronously, no I/O"); replacing its inline `.where(...)`
  with `Item.due_for_price_update` is a direct instance of that existing
  rule, not a deviation from it.
- `.claude/styleguides/fetcher/background-jobs.md` — confirms
  `PriceScheduler#perform` must stay query-and-fan-out only (no Steam
  call), satisfied before and after this change. Also required adding the
  explicit `retry: 3` this file was already flagged as missing in
  `fix_me.md` — folded into this change per that file's own process
  (small, within this already-applicable styleguide, file already being
  touched); see Implementation Summary.
- `.claude/styleguides/rspec-conventions.md` — constrains the new
  `spec/models/item_spec.rb` (Model → Unit spec-level mapping, no
  `type:` metadata), the `spec/factories/items.rb` additions (traits over
  new fixtures), and the new `price_scheduler_spec.rb` context
  (`let!`-based arrange, named `subject`, `aggregate_failures` once past
  3 expectations).

# Implementation Summary

## Implemented

- `app_fetcher/app/models/item.rb`: added `PRICE_STALE_AFTER = T.let(1.hour,
  ActiveSupport::Duration)` and three `scope` declarations — `marketable`
  (jsonb containment — `where("metadata @> ?", { marketable: true }
  .to_json)`), `stale_or_unpriced` (the staleness/no-price condition
  relocated verbatim from `PriceScheduler`), and `due_for_price_update`
  (`marketable.stale_or_unpriced`, plain scope chaining) — exactly as
  originally planned.
- `app_fetcher/sorbet/rbi/dsl/item.rbi` (new, generated): `bundle exec
  tapioca dsl Item`'s output, making the three scopes (plus `store_accessor`'s
  existing keys and `Item`'s plain column attributes) resolvable under
  `srb tc` — see Deviations for why this, not a styleguide change or a
  new gem, is what the plan actually needed.
- `app_fetcher/app/schedulers/price_scheduler.rb`: `#perform` now reads
  `Item.due_for_price_update.find_each { |item| PriceUpdateWorker
  .perform_async(item.id) }` — no SQL fragment left in the scheduler.
  Also added `retry: 3` to `sidekiq_options` (folded in from `fix_me.md`,
  matching `UserInventorySyncScheduler`'s existing precedent for a
  query-and-fan-out-only scheduler).
- `app_fetcher/spec/factories/items.rb`: base `:item` factory now sets
  `metadata { { marketable: true } }`; added a `:non_marketable` trait
  (`metadata { { marketable: false } }`).
- `app_fetcher/spec/schedulers/price_scheduler_spec.rb`: added a context
  asserting a stale, `:non_marketable` item is never enqueued.
- `.claude/styleguides/ruby-sorbet.md`: added a MUST rule — after adding
  anything Sorbet can't see statically on an AR model (`scope`,
  `store_accessor` key, association, enum), regenerate that model's DSL
  RBI via `bundle exec tapioca dsl <Model>` and commit it; don't hand-write
  a shim or add a second DSL-RBI tool (`sorbet-rails`) alongside the
  already-present `tapioca`. Added `item.rb`/`item.rbi` to Canonical
  Implementations as the first worked example.
- `.claude/styleguides/fix_me.md`: removed `price_scheduler.rb` from the
  shared missing-`retry:` entry (now fixed, kept for
  `inventory_value_scheduler.rb`); added two new entries for `srb tc`
  errors *surfaced* (not introduced) by `item.rbi` now existing — see
  Deviations.

## Files To Create (completed)

- `app_fetcher/spec/models/item_spec.rb` — new file, first model spec for
  `Item`. Three `describe` blocks (`.marketable`, `.stale_or_unpriced`,
  `.due_for_price_update`), covering the marketable/non-marketable/
  missing-key cases, the stale/unpriced/fresh cases, and their
  composition.

## Tests

- `app_fetcher/spec/models/item_spec.rb` (new): 3 examples across the
  three scopes, each written RED-first against the not-yet-implemented
  scope and confirmed to fail for the expected `NoMethodError` before
  implementing.
- `app_fetcher/spec/schedulers/price_scheduler_spec.rb`: added "with a
  stale, non-marketable item" context (1 new example); the three existing
  contexts re-verified against the updated factory default and scheduler
  query.

Commands executed (via `docker compose run --rm app_fetcher ...`):

- `bundle exec rspec spec/models/item_spec.rb` — run after each of the
  three RED/GREEN steps.
- `bundle exec rspec spec/schedulers/price_scheduler_spec.rb`
- `bundle exec rspec` (full suite, run 3 times across the investigation)
- `bundle exec tapioca dsl Item` — generated `sorbet/rbi/dsl/item.rbi`
- `bundle exec srb tc` — run at baseline, after the first `scope` attempt
  (pre-`tapioca`), after an intermediate class-method pivot, and after
  the final `tapioca`-backed `scope` version (4 runs, diffed pairwise by
  sorted error-header to ignore line-shift noise)
- `bundle exec rubocop app/models/item.rb app/schedulers/price_scheduler.rb
  spec/models/item_spec.rb spec/factories/items.rb
  spec/schedulers/price_scheduler_spec.rb`

## Verification

- **RSpec**: full `app_fetcher` suite, 150 examples, 1 failure
  (`spec/caching/user_inventory_cache_spec.rb:18`) — confirmed pre-existing
  and unrelated (same spec/line already documented as a known, unrelated
  failure in the prerequisite `steam-marketability-rarity-metadata.md`
  plan's own verification).
- **Sorbet (`srb tc`)**: baseline (clean `main`) = 96 errors. Final
  implementation (scope + `item.rbi`) = 92 — *below* baseline. Diffed by
  sorted error-header: `item.rbi` fixed 8 pre-existing errors that were
  invisible before (e.g. `item_prices_controller.rb`'s calls to
  `current_price_cents`/`market_hash_name`, `price_update_service.rb`'s
  `price_logs` association — none of `Item`'s dynamic/column methods had
  ever been resolvable under `srb tc` before this). It also surfaced 3
  new, genuine (not false-positive) errors in two files outside this
  change's scope, now logged in `fix_me.md` rather than fixed inline (see
  Deviations). The only error attributable to this task's own new code is
  the expected `spec/models/item_spec.rb:3: Unable to resolve constant
  'RSpec'` — the same harmless pattern every other spec file already
  triggers.
- **Rubocop**: 5 files inspected, no offenses.
- **Manual/API verification**: not applicable — no `app_core`/dashboard or
  API-response-shape change; internal scheduling-query change only,
  confirmed via the RSpec suite above.

## Deviations

- **Investigation path before landing on the real fix.** The plan's
  original `scope :marketable`/`:stale_or_unpriced`/`:due_for_price_update`
  passed every RSpec example immediately, but `srb tc` couldn't resolve
  `marketable` called from `due_for_price_update`'s own lambda, nor
  `Item.due_for_price_update` called from `PriceScheduler`. Two fixes were
  tried and reverted before the real one: (1) a `ruby-sorbet.md` addition
  exempting macro-generated methods from the sig rule — insufficient,
  since the problem wasn't *declaring* the scope but *calling* it from
  elsewhere, which no code in this project had ever done for any
  sig-less macro-generated method before (confirmed via grep); (2) plain
  `class << self` methods with real `sig`s instead of `scope` — this
  worked and passed `srb tc` cleanly, but changed the plan's actual
  design for a tooling gap, not a real design reason. The real fix: this
  project's `Gemfile` already has `tapioca` (dev group) — the
  actively-maintained tool for generating DSL RBIs for ActiveRecord's
  dynamic methods — but it had never been run for any app model.
  `bundle exec tapioca dsl Item` generates a complete RBI covering the
  three new scopes, `store_accessor`'s existing keys, and `Item`'s plain
  column attributes. This let the original `scope`-based plan stand
  completely unchanged. Adding `sorbet-rails` (the user's initial
  suggestion) would have been redundant and architecturally messy next to
  an already-present, overlapping tool — `tapioca` was the correct answer
  already sitting in the Gemfile.
- **Two `srb tc` errors newly surfaced, not introduced, by `item.rbi`
  now existing** — logged in `fix_me.md` rather than fixed, since both
  are in files outside this change's scope: `item_prices_controller.rb`
  re-reads `item.current_price_cents` after a `nil?` guard (Sorbet can't
  carry a guard's narrowing across two separate method calls), and
  `price_update_worker.rb` passes nilable `current_price_cents`/
  `change_24h_cents` into `publish_to_stream`'s non-nilable `Integer`
  params. Both were always real type mismatches — simply invisible before,
  since `srb tc` had no type information for any of `Item`'s dynamic or
  column methods prior to this task's `item.rbi`.
- **`ruby-sorbet.md` gains a durable rule** (the `tapioca dsl`
  regeneration workflow) instead of the narrower, now-reverted
  macro-generated-method sig exemption from the first `styleguides-check`
  pass — grounded in what was actually needed and validated here, and
  directly reusable the next time any model in either app gains a
  `scope`, a `store_accessor` key, or an association.
- **Folded in `price_scheduler.rb`'s missing `retry:`** from
  `fix_me.md`'s pre-existing deviation entry, per the project's own
  "small and within an already-applicable styleguide" rule — the file was
  already being touched for this change, `background-jobs.md` was already
  an applicable styleguide, and `UserInventorySyncScheduler` gave a direct
  precedent (`retry: 3`) to follow rather than inventing a number.
  `inventory_value_scheduler.rb`'s identical, still-unfixed deviation was
  left alone (not touched by this change).

## Remaining Issues

- `spec/caching/user_inventory_cache_spec.rb:18` remains failing,
  pre-existing and unrelated — already noted as an open item in two prior
  plans, still unresolved; worth a separate look outside this task's
  scope.
- `inventory_value_scheduler.rb`'s missing `sidekiq_options retry:`
  remains logged in `fix_me.md`, unresolved — next person to touch that
  file should fix it then.
- `item_prices_controller.rb`'s nil-narrowing gap and
  `price_update_worker.rb`'s nilable-argument mismatch (both newly
  surfaced by `item.rbi`) remain logged in `fix_me.md`, unresolved — real,
  pre-existing type-safety gaps now visible for the first time, worth a
  dedicated look.
- Running `tapioca dsl` for the *rest* of the app's models (only `Item`
  was done here) would likely surface more of the same kind of
  previously-invisible gaps. Not done here — out of scope for a
  scheduler/model change limited to `Item`.
- The "Tiered price-fetch priority" follow-up task (mentioned in
  `steam-marketability-rarity-metadata.md`'s Remaining Issues) is not
  implemented — by design, out of scope here. `Item.marketable` was kept
  as its own standalone scope specifically so that task can reuse it
  directly.
