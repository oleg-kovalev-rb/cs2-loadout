---
status: implemented
app: fetcher
goal: Capture each Steam inventory item's marketable/tradable flags and rarity tag into Item.metadata
created: 2026-10-09
---

# Development Plan

## Goal

Extend the user-inventory sync pipeline so each item's `marketable`,
`tradable`, and rarity (from Steam's `tags` array) — present in Steam's raw
inventory response today but discarded before reaching `ItemParser` — are
captured into `Item#metadata` as new keys, available to any future consumer
(not implemented here; this is prep for "Skip fetching non-marketable items"
and "Tiered price-fetch priority").

## Expected Behavior

- Normal: when `UserInventorySyncService` backfills a new `Item` from a
  Steam inventory sync, the item's `marketable` (bool), `tradable` (bool),
  and `rarity` (string, e.g. `"Mil-Spec Grade"`, `"Consumer Grade"`) are
  stored in `metadata` alongside the existing parsed fields, and returned by
  `GET /api/v1/inventories/me` / `POST /api/v1/inventories/refresh` inside
  `metadata.marketable` / `metadata.tradable` / `metadata.rarity`.
- Edge case — Steam sends `marketable`/`tradable` as integer `0`/`1`, not a
  JSON boolean: both must be coerced the same defensive way
  `InventoryData.from_hash` already coerces `more_items`
  (`!!hash["more_items"]`) — a literal `0` is truthy in Ruby, so a naive
  truthy check would store `true` for a non-marketable/non-tradable item.
  Confirmed from a real captured response (see Assumptions) that both
  fields are always present as `0`/`1` on every description entry observed.
- Edge case — no `Rarity` entry in a description's `tags` array (observed:
  `tags` entries are not in a fixed order or fixed category set across item
  types): `rarity` is `nil`, matching how `condition` is already `nil` when
  absent from a name — not an error, not a default string.
- Edge case — a description has no `tags` key at all: treated the same as
  an empty array; `rarity` is `nil`.
- Edge case — unknown item whose Steam description happens to be missing
  `marketable`/`tradable` keys entirely (not observed live, but `from_hash`
  must stay defensive per `steam-response-objects.md`): coerces to `false`
  via the same `!!` pattern, never raises.
- Unchanged: every existing `Item#metadata` field (`weapon_type`,
  `item_name`, `condition`, `stattrak`, `souvenir`, `icon_url`), the
  `ItemParser` name-string parsing logic, and the overall
  `InventoriesController#show`/`#refresh` → `UserInventorySyncService` →
  `Item.upsert_all` flow.
- Unchanged: no dashboard/`app_core` rendering of these fields — this task
  is backend capture only (see Scope).

## Scope

### In Scope

- `Steam::Response::Data::InventoryData`: one new derived method reshaping
  `descriptions` into a `market_hash_name → {marketable:, tradable:,
  rarity:}` lookup.
- `ItemParser`: `.parse` accepts `marketable:`, `tradable:`, `rarity:`
  directly as parameters (same shape as the existing `icon_url:` parameter)
  and includes them in the `metadata:` hash it returns; `ItemDto`'s type
  alias updated to match.
- `Item`: three new `metadata` keys (`marketable`, `tradable`, `rarity`)
  via `store_accessor` — no migration, `metadata` is already `jsonb`.
- `UserInventorySyncService`: resolve the new lookup once per sync and pass
  the three fields into `ItemParser.parse` for each missing item, the same
  point in the flow where `icon_url` is already resolved and passed.
- Tests for all of the above, at every layer already covered for
  `icon_url` (`inventory_data_spec.rb`, `item_parser_spec.rb`,
  `user_inventory_sync_service_spec.rb`, `inventories_spec.rb`).
- Resetting the local `app_fetcher` dev DB after the `Item`/metadata shape
  is finalized, mirroring `item-icon-url.md`'s precedent (same situation:
  pre-existing `Item` rows won't have the new keys until re-synced, and
  nothing is deployed) — flagged in Risks since this plan doesn't re-ask
  for confirmation already given once for the identical situation.

### Out of Scope

- Any business logic that *acts* on `marketable`/`tradable`/`rarity`
  (skipping non-marketable items, tiered price-fetch priority) — those are
  the two follow-up tasks this prep work exists for.
- Any `app_core`/dashboard change — these fields are not rendered anywhere
  in this task; `InventoriesController` needs no change since
  `as_json(only: [:market_hash_name, :metadata])` already passes the full
  `metadata` hash through.
- Backfilling `marketable`/`tradable`/`rarity` for any `Item` row that
  survives past this task via a data migration — the dev DB reset (In
  Scope) makes this moot locally, same reasoning as `item-icon-url.md`.
- A defensive `nil`-coercing override method on `Item` for `marketable`/
  `tradable` (the `stattrak`/`souvenir` pattern) — see Implementation
  Approach for why this isn't needed.
- Capturing any other newly-visible field from the live sample response
  (`commodity`, `sealed`, `market_tradable_restriction`,
  `market_marketable_restriction`, `name_color`, `background_color`, etc.)
  — not requested by this task.
- Migrating `inventories_spec.rb`/`user_inventory_sync_service_spec.rb` off
  hand-written `WebMock` stubs onto VCR — explicitly deferred by the
  project owner to a separate, later task covering all endpoints at once.

## Implementation Approach

This follows the exact shape of `agent/plans/item-icon-url.md`
(commit `fcac918`), the most recent precedent for "a new field on a Steam
description needs to reach `Item.metadata`," including a refinement that
came out of that task's code review: `ItemParser.parse` takes the extra
field(s) as parameters and includes them directly in the `metadata:` hash
literal it builds, rather than having the service mutate the parsed result
afterward.

**Lookup-method shape (explicit decision):** `InventoryData` currently
exposes one single-purpose lookup method per derived field
(`market_hash_names`, `icon_urls_by_name`), each its own pass over
`descriptions`. Adding `marketable`, `tradable`, and `rarity` the same way
would mean three more single-field methods and three more O(n) passes.
Instead, this plan adds **one combined method**,
`item_attributes_by_name`, returning
`T::Hash[String, { marketable: T::Boolean, tradable: T::Boolean, rarity:
T.nilable(String) }]` — one pass producing all three new fields per name.
Reasoning:

- These three fields are always sourced from the same description record,
  in the same pass, and are always consumed together at the one call site
  that needs them (`UserInventorySyncService#call`, feeding into one
  `ItemParser.parse` call per item) — unlike `icon_urls_by_name` and
  `market_hash_names`, which serve genuinely distinct purposes
  (`market_hash_names` drives the known/missing split; `icon_urls_by_name`
  only feeds the icon).
- `icon_urls_by_name` is left completely untouched — this avoids retrofitting
  a new nested-hash shape onto an existing, already-reviewed, working
  method. The inconsistency this introduces (one combined method sitting
  alongside two single-field methods) is judged smaller than either (a)
  three redundant extra passes for data that's always used together, or
  (b) folding `icon_url` into the same combined shape and touching a
  method with no reason to change.
- The per-sync cost difference (3 passes vs. 1) is not performance-critical
  either way — `UserInventorySyncService` only runs on a cache miss or an
  explicitly rate-limited refresh (`REFRESH_DEDUP_TTL = 1.day`), over an
  inventory capped at Steam's own `count: 2000` — but a single combined
  pass is the more natural seam given the fields' shared origin and shared
  consumer, not primarily a perf optimization.

**Rarity extraction:** a private helper on `InventoryData`
(`rarity_tag(desc)`) finds the `tags` array entry where `category ==
"Rarity"` (position is not fixed — observed 5th of 6 tags on a weapon skin,
4th of 4 on a sticker) and returns its `localized_tag_name` (the
human-readable value, e.g. `"Mil-Spec Grade"`), not `internal_name` (
confirmed inconsistent across item types for the same effective rarity —
e.g. `Rarity_Rare_Weapon` for a Mil-Spec weapon vs. `Rarity_Rare` for a
High-Grade sticker). Matches `ItemParser`/`Item.metadata`'s existing
convention of storing human-readable strings (`weapon_type`, `condition`),
not Steam's internal codes.

**No `Item` override methods for `marketable`/`tradable`:** unlike
`stattrak`/`souvenir` (always computed from the name string, never absent),
`marketable`/`tradable` are only known once an item has been synced through
this new code path. A pre-existing `Item` row re-read before its next sync
will have `metadata["marketable"]` simply absent (`nil` via
`store_accessor`) — the exact same situation `icon_url` is already in today
(no override, no backfill, resolved by a dev DB reset). Adding a
nil-coalescing override now, before either consumer task exists, would be
designing for a requirement neither task has specified yet (e.g. "is nil
`false`, or 'unknown, needs re-sync'?" is a decision for whichever follow-up
task actually branches on this field). Plain `store_accessor` keeps this
task's scope to capture only.

## Files To Modify

- `app_fetcher/lib/steam/response/data/inventory_data.rb` — add
  `item_attributes_by_name` (`sig { returns(T::Hash[String, ItemAttributes])
  }`, with `ItemAttributes` a `T.type_alias` for the inline shape above,
  defined the same way `ItemParser::ItemDto` already type-aliases an inline
  hash shape) and a private `rarity_tag(desc)` helper (own `sig`, per
  `ruby-sorbet.md`'s "every method, including private ones" rule under
  `typed: strict`). Built the same defensive way as `icon_urls_by_name`:
  skip entries with no `market_hash_name`; `!!desc["marketable"]` /
  `!!desc["tradable"]` for the boolean coercion; `(desc["tags"] ||
  []).find { ... }&.dig("localized_tag_name")` for rarity. Reason: the DTO
  owns reshaping its own raw fields (`steam-response-objects.md`); this is
  the Steam-knowledge boundary.
- `app_fetcher/app/parsers/item_parser.rb` — `ItemDto`'s `metadata` type
  alias gains `marketable: T::Boolean, tradable: T::Boolean, rarity:
  T.nilable(String)`; `.parse`'s signature gains `marketable: false,
  tradable: false, rarity: nil` keyword params (defaults chosen so every
  existing call site/spec that doesn't pass them keeps working unchanged);
  both branches' `metadata:` hash literals include the three new keys
  (Ruby 3.1 shorthand, alongside `stattrak:`, `souvenir:`, `icon_url:`).
  Reason: matches the established post-review pattern from
  `item-icon-url.md` — passed into `.parse` directly, not merged onto its
  result afterward.
- `app_fetcher/app/models/item.rb` — add `:marketable, :tradable, :rarity`
  to the existing `store_accessor :metadata, ...` line. Reason: matches the
  established pattern for every other metadata field; no migration needed
  (`metadata` is `jsonb`).
- `app_fetcher/app/services/user_inventory_sync_service.rb` — alongside the
  existing `icon_by_name = response.data.icon_urls_by_name` line, resolve
  `item_attributes_by_name = response.data.item_attributes_by_name` once,
  then for each `missing_names` entry pass `marketable:`, `tradable:`,
  `rarity:` (looked up by name, defaulting to `{ marketable: false,
  tradable: false, rarity: nil }` if a name is somehow absent from the
  lookup — mirrors `icon_by_name[name]`'s existing nil-safe lookup pattern)
  into the same `ItemParser.parse(...)` call that already passes
  `icon_url:`. Reason: this is the one place that already combines
  resolved Steam-response data with parsed data before persisting; keeps
  `InventoryData` and `ItemParser` each at their existing responsibility.

## Files To Create

None. Every change fits an existing file/layer — matches `item-icon-url.md`
precedent; no new parser, builder, service, or DTO class is warranted for
three additional fields sourced the same way as an existing one.

## Test Plan

- `app_fetcher/spec/lib/steam/response/data/inventory_data_spec.rb` — new
  `describe "#item_attributes_by_name"` block: maps a description with
  `marketable: 1, tradable: 0` and a `Rarity` tag to `{ marketable: true,
  tradable: false, rarity: "..." }`; a description with `marketable: 0,
  tradable: 1` and **no** `Rarity` tag maps `rarity` to `nil` (while still
  correctly resolving the booleans — guards against the `0`-is-truthy
  coercion bug specifically); a description with no `tags` key at all
  behaves the same as an empty `tags` array; a description with no
  `market_hash_name` is skipped entirely (mirrors `icon_urls_by_name`'s
  existing defensive case); a `tags` array where `Rarity` is not the first
  element still resolves correctly (guards against an implementation that
  assumes tag order/position).
- `app_fetcher/spec/parsers/item_parser_spec.rb` — new examples: passing
  `marketable:`, `tradable:`, `rarity:` includes them unchanged in the
  returned `metadata`; omitting them defaults to `false`, `false`, `nil`
  respectively (mirrors the existing `icon_url` default-to-`nil` example).
- `app_fetcher/spec/services/user_inventory_sync_service_spec.rb` — extend
  the existing "mix of known and unknown names" context (or add sibling
  contexts, matching the file's existing per-scenario style) so the
  stubbed Steam response's `descriptions` include `marketable`, `tradable`,
  and a `Rarity`-category tag; assert the backfilled `Item`'s
  `metadata["marketable"]` / `["tradable"]` / `["rarity"]` match. Add a
  case where `marketable`/`tradable` are both `0` and assert both store as
  `false` (not `true` — the specific regression this plan calls out), and a
  case with no `Rarity` tag asserting `metadata["rarity"]` is `nil`. New
  test data via `FactoryBot`, per `rspec-conventions.md`.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — extend one
  stubbed cold-start response's `descriptions` entry to include
  `marketable`, `tradable`, and a `Rarity` tag; assert the JSON response's
  `items[0]["metadata"]` includes all three with the expected values,
  end-to-end through the real controller/service/parser chain. Keep using
  `WebMock` (no VCR migration — explicitly out of scope).

## Implementation Steps

1. Add `InventoryData#item_attributes_by_name` (+ the `ItemAttributes` type
   alias and the private `rarity_tag` helper); write its spec first
   (`inventory_data_spec.rb`), following TDD.
2. Extend `ItemParser::ItemDto`'s type alias and `.parse`'s signature/body
   to accept and emit `marketable:`/`tradable:`/`rarity:`; extend
   `item_parser_spec.rb`.
3. Add `:marketable, :tradable, :rarity` to `Item`'s `store_accessor` list.
4. Update `UserInventorySyncService#call` to resolve
   `item_attributes_by_name` and pass the three fields into each
   `ItemParser.parse` call; extend `user_inventory_sync_service_spec.rb`.
5. Extend `inventories_spec.rb` to assert end-to-end passthrough via the
   real API response.
6. Reset the local `app_fetcher` dev DB (`db:drop db:create db:migrate`,
   re-seed/re-login) now that the `Item`/metadata shape is final — per the
   `item-icon-url.md` precedent; confirm still acceptable before running
   (flagged in Risks, not pre-decided here).

## Verification

- `bundle exec rspec spec/lib/steam/response/data/inventory_data_spec.rb
  spec/parsers/item_parser_spec.rb
  spec/services/user_inventory_sync_service_spec.rb
  spec/requests/api/v1/inventories_spec.rb`, then the full `app_fetcher`
  suite for regressions.
- `srb tc` (Sorbet) on the touched `# typed: strict` files; diff the error
  count/list against the pre-change baseline the same way
  `item-icon-url.md` did (confirm no *new* unrelated errors; any genuinely
  new one gets logged in `fix_me.md`, not silently fixed, per `CLAUDE.md`'s
  process, unless small and isolated to a line this plan already touches).
- `rubocop` on every touched file.
- No `app_core`/browser verification needed — no frontend or rendering
  change in this task's scope.

## Risks

- `fix_me.md` already flags, in files this change touches:
  `item_parser.rb`'s untyped regex constants and a pre-existing `item_name`
  nilable-shape Sorbet error; `user_inventory_sync_service.rb`'s
  un-narrowed `response.data` across all three (soon to be four) call
  sites. Per `CLAUDE.md`, these are not fixed as part of this change unless
  small and isolated — left for `styleguides-check`/`implement-plan` to
  decide, same as `item-icon-url.md` did for the same files.
- `Item`'s existing `stattrak` override already deviates from
  `ruby-sorbet.md` (no `sig`, no `extend T::Sig` on the class) per
  `fix_me.md`. This plan deliberately adds no new override method for
  `marketable`/`tradable` (see Implementation Approach), so that deviation
  isn't expanded — but if `implement-plan`/`styleguides-check` later decide
  an override *is* needed after all, it should be added with a proper
  `sig`, not by copying the existing deviation forward.
- The dev DB reset (Implementation Steps, step 6) mirrors a reset the
  project owner already explicitly approved once for the identical
  situation (`item-icon-url.md`) — carried forward as precedent rather than
  re-confirmed from scratch in this plan; flagged here in case current
  circumstances (e.g. anything now deployed) have changed since then.
- Steam's `tags` category set observed in the live sample
  (`Type`, `Weapon`, `ItemSet`, `Quality`, `Rarity`, `Exterior`,
  `StickerCapsule`) came from only two item kinds (weapon skins, a
  sticker) — other CS2 item types (knives, gloves, cases, music kits,
  agents, graffiti, patches) were not directly observed in this session and
  may have different tag sets. The `category == "Rarity"` lookup is
  expected to generalize (Steam's economy tag system is uniform across
  `appid 730` per public documentation/community tooling), but this is an
  unverified assumption for any item type outside the 5 samples captured.

## Assumptions

- `marketable`/`tradable` are always present as integer `0`/`1` on every
  real `descriptions` entry (confirmed on all 5 items in the captured
  sample) — the `false`/`false` fallback for a missing key is purely
  defensive, per `steam-response-objects.md`'s "Steam's JSON shape isn't
  contractually guaranteed" rule, not expected to trigger in practice.
- `localized_tag_name` on the `Rarity`-category tag is stable/suitable as a
  stored value (not expected to change per-locale drift beyond the `l:
  "english"` param `Steam::Client` already fixes) — same stability
  assumption already implicitly relied on for `market_hash_name`/
  `weapon_type`/`condition`, which are likewise locale-dependent display
  strings from the same response.
- No two description entries for the same `market_hash_name` disagree on
  `marketable`/`tradable`/rarity within one inventory response (same
  per-name-key-collapse assumption `icon_urls_by_name`/`market_hash_names`
  already make today, carried forward rather than re-litigated here).

## Applicable Styleguides

- `agent/styleguides/fetcher/steam-response-objects.md` — constrains
  `InventoryData#item_attributes_by_name`: a derived method on the DTO
  itself (its own SHOULD rule — "keep derived read methods... on the DTO
  itself when they only reshape the DTO's own fields"), defensive hash
  access (`desc["marketable"]`, `desc["tags"] || []`, tolerating missing
  keys, never raising), `const`-only fields untouched, no AR/model
  knowledge inside the DTO. Also constrains the private `rarity_tag`
  helper as an internal reshaping detail of the same DTO, not pushed onto
  a caller.
- `agent/styleguides/fetcher/architecture-layers.md` — confirms where
  each piece of new logic belongs: the Steam-knowledge extraction
  (`tags`/`marketable`/`tradable` parsing) stays on the DTO, not in
  `ItemParser` (parsers "depend on nothing else" and only transform the
  name string) or in a new builder/service; `UserInventorySyncService`
  remains the one place that combines resolved Steam-response data with
  parsed data before `Item.upsert_all` — consistent with its existing role
  for `icon_url`. No new layer (builder/service) is introduced, matching
  "don't introduce a layer for a single-Scenario need."
- `agent/styleguides/rails-layering.md` — confirms the lookup-merge step
  belongs in the orchestration layer (`UserInventorySyncService`), not the
  model (`Item` stays limited to the `store_accessor` addition, no
  business logic) or the controller (no change needed there at all).
- `agent/styleguides/ruby-sorbet.md` — constrains typing on every
  touched file: `sig` on `item_attributes_by_name` *and* the private
  `rarity_tag` helper (private methods are not exempt under `typed:
  strict`); the new `ItemAttributes` type alias uses the fixed-keys shape
  form (`{key: Type, ...}` behind `T.type_alias`), matching the existing
  `ItemParser::ItemDto` pattern, not a generic `T::Hash[String,
  T.untyped]` (reserved for genuinely dynamic-key hashes, e.g. the raw
  Steam JSON itself); `T::Boolean`/`T.nilable(String)` field types;
  `T.let` on any new constant; Ruby 3.1 hash-shorthand (`marketable:,
  tradable:, rarity:`) in `ItemParser`'s `metadata:` literals, consistent
  with the existing `stattrak:, souvenir:, icon_url:` fields.
- `agent/styleguides/rspec-conventions.md` — constrains the Test Plan:
  `inventory_data_spec.rb`'s new block stays at the unit level with plain
  `T::Hash`/struct construction (no stubbing, matches "plain in-memory
  objects... never stub"); `user_inventory_sync_service_spec.rb` stays
  unit-level `WebMock` against the real `steamcommunity.com` host (never
  stubbing `Steam::Client` itself); new test data via `FactoryBot`, never
  a new fixture row. **Known, pre-accepted deviation carried forward, not
  newly introduced by this plan**: this guide's own MUST NOT rule says a
  request spec exercising a Steam API call must use a VCR cassette, not a
  hand-written `WebMock` stub — `inventories_spec.rb` already deviates
  from this today and is already logged in `fix_me.md` ("migrate the next
  time either file is otherwise touched"). This plan does touch the file,
  but the project owner has explicitly deferred that migration to a
  separate, later task covering all endpoints at once (VCR isn't in
  either Gemfile yet) — the plan's Test Plan/Out of Scope sections reflect
  that explicit decision rather than silently ignoring the rule.

## Completion Criteria

- [x] Desired behavior explicit (Expected Behavior)
- [x] Scope explicit (Scope)
- [x] Affected files/components identified (Files To Modify)
- [x] Test strategy defined (Test Plan)
- [x] Implementation steps ordered (Implementation Steps)
- [x] Verification defined (Verification)
- [x] Plan written to `agent/plans/steam-marketability-rarity-metadata.md`

# Implementation Summary

## Implemented

- `Steam::Response::Data::InventoryData#item_attributes_by_name`
  (`app_fetcher/lib/steam/response/data/inventory_data.rb`): one combined
  derived method (per the plan's explicit decision) mapping each
  `market_hash_name` to `{marketable:, tradable:, rarity:}`. `marketable`/
  `tradable` resolved via `desc["marketable"] == 1` / `desc["tradable"] ==
  1` (see Deviations — not `!!`). `rarity` resolved by a new private
  `rarity_tag(desc)` helper that finds the `tags` entry with `category ==
  "Rarity"` (constant `RARITY_TAG_CATEGORY`) and returns its
  `localized_tag_name`, defaulting to `nil` if absent. A new
  `ItemAttributes` type alias (fixed-keys shape, matching `ItemDto`'s
  existing pattern) backs the method's return type.
- `ItemParser` (`app_fetcher/app/parsers/item_parser.rb`): `ItemDto`'s
  `metadata` type alias and `.parse`'s signature/body gained `marketable:
  T::Boolean, tradable: T::Boolean, rarity: T.nilable(String)` (default
  `false, false, nil`), included directly in both branches' `metadata:`
  hash literals — matching the established post-icon-url-review pattern
  (passed into `.parse` directly, not merged onto its result afterward).
- `Item#metadata` (`app_fetcher/app/models/item.rb`): added `:marketable,
  :tradable, :rarity` to the existing `store_accessor` list. No override
  method added for nil-coalescing (per the plan's explicit reasoning — see
  plan body).
- `UserInventorySyncService#call`
  (`app_fetcher/app/services/user_inventory_sync_service.rb`): resolves
  `response.data.item_attributes_by_name` once per sync and passes
  `marketable:`/`tradable:`/`rarity:` into each `ItemParser.parse` call for
  a missing item, defaulting to `{marketable: false, tradable: false,
  rarity: nil}` if a name is somehow absent from the lookup.
- `Api::V1::InventoriesController`: no change, as planned —
  `as_json(only: [:market_hash_name, :metadata])` already passes the new
  keys through.
- `agent/styleguides/fix_me.md`: removed the now-fixed `item_parser.rb`
  T.let-constants entry and the `item.rb` missing-sig entry (both actually
  fixed, see below); updated the `user_inventory_sync_service.rb` entry's
  "all three calls" to "all four calls" to reflect the new
  `item_attributes_by_name` call site added on the same unfixed pattern;
  kept `item_parser.rb`'s `item_name` nilable-shape entry (still present,
  unrelated to and not introduced by this change).
- Folded into this change, per `fix_me.md`'s "small and within an already-
  applicable styleguide" rule (both files were already being touched):
  - `item_parser.rb`: wrapped `CONDITION_EXTRACT_REGEX`/
    `CONDITION_CLEANUP_REGEX` in `T.let(..., Regexp)` (confirmed `srb tc`
    `7027` fix).
  - `item.rb`: added `extend T::Sig` and a `sig { returns(T::Boolean) }`
    on the `stattrak` override (confirmed `srb tc` `7017` fix).
- Local `app_fetcher` dev DB reset (`db:drop db:create db:migrate`),
  confirmed with the project owner before running (see Deviations — not
  silently re-run from the `item-icon-url.md` precedent). Also hit and
  fixed the identical `cache_schema.rb` side effect documented in that
  precedent (`db:create`/`db:drop` touches the `cache` sub-database but
  `db:migrate` doesn't target it) — restored the file from git and ran
  `db:schema:load:cache` instead.

## Tests

- `app_fetcher/spec/lib/steam/response/data/inventory_data_spec.rb` — new
  `#item_attributes_by_name` block: marketable/tradable/rarity resolved
  together; both flags `0` with no Rarity tag (guards the truthy-integer
  bug specifically); no `tags` key at all; Rarity tag not in first
  position; description with no `market_hash_name` skipped.
- `app_fetcher/spec/parsers/item_parser_spec.rb` — new examples: given
  `marketable:`/`tradable:`/`rarity:` pass through unchanged; omitted
  default to `false`/`false`/`nil`.
- `app_fetcher/spec/services/user_inventory_sync_service_spec.rb` — two new
  contexts: marketable/tradable/rarity resolved and stored on the
  backfilled `Item`; both flags `0` with no Rarity tag stored as
  `false`/`false`/`nil` (not `true`).
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — new context
  asserting `marketable`/`tradable`/`rarity` pass through
  `GET /api/v1/inventories/me`'s JSON response end-to-end.

Commands executed:
- `docker compose run --rm app_fetcher bundle exec rspec` (targeted files,
  then full suite, repeated after each TDD step)
- `docker compose run --rm app_fetcher bundle exec srb tc` (baseline via
  `git stash` against unmodified `main`, then after)
- `docker compose run --rm app_fetcher bundle exec rubocop <touched files>`
- `docker compose run --rm app_fetcher bin/rails db:drop db:create
  db:migrate`, then `db:schema:load:cache`

## Verification

- **app_fetcher RSpec**: full suite, 146 examples, 1 failure
  (`spec/caching/user_inventory_cache_spec.rb:18`). Confirmed pre-existing
  and unrelated via `git stash` + re-run against unmodified `main`
  (identical failure) — same issue already noted as unresolved in
  `item-icon-url.md`'s own Remaining Issues.
- **app_fetcher Sorbet (`srb tc`)**: baseline (clean `main`) = 98 errors.
  After this change = 96. Diffed line-by-line against baseline: net -2 is
  exactly (3 errors fixed: `item.rb` missing-sig, `item_parser.rb`'s two
  T.let-constants errors) minus (1 new, expected error:
  `user_inventory_sync_service.rb`'s `item_attributes_by_name` call on
  nilable `response.data` — the anticipated 4th occurrence of the file's
  existing, intentionally-unfixed pattern). Two other baseline errors
  (`item.rb`'s `stattrak`-not-on-ancestors, `item_parser.rb`'s `item_name`
  nilable-shape mismatch) persist unchanged, just shifted to new line
  numbers — not newly introduced, not fixed, consistent with `fix_me.md`.
  Zero genuinely new, unaccounted-for errors.
- **app_fetcher Rubocop**: 8 files inspected, no offenses.
- **Manual/API-level**: no browser verification — no `app_core`/dashboard
  change in this task's scope (confirmed via the request spec's end-to-end
  JSON assertion instead).
- **Local DB reset**: `db:drop db:create db:migrate` run against
  `app_fetcher`'s development database, confirmed with the user first;
  `cache_schema.rb` side effect caught via `git status` and corrected via
  `db:schema:load:cache` (same fix as the `item-icon-url.md` precedent).

## Deviations

- **`marketable`/`tradable` coercion uses `== 1`, not `!!`, contrary to
  the plan's own Expected Behavior/Implementation Approach prose.** The
  plan's prose suggested reusing the exact `!!hash["more_items"]` pattern.
  Writing the RED test for "both flags `0` and no Rarity tag" (an edge
  case the plan's own Test Plan explicitly called for, anticipating this
  exact risk) immediately caught that `!!0` is `true` in Ruby (only `nil`/
  `false` are falsy) — so a literal port of the `!!` pattern would have
  silently stored `marketable: true` for a `marketable: 0` item, the
  precise bug the plan's Test Plan was trying to guard against. Fixed by
  using `desc["marketable"] == 1` / `desc["tradable"] == 1` instead
  (`nil`/`0`/anything-not-`1` → `false`, `1` → `true`). No behavior
  intended by the plan changed — this corrects an implementation detail
  the plan's prose got wrong, while its own specified test behavior
  (Test Plan, Expected Behavior's edge case) was exactly right and is
  what caught it.
- **Folded two `fix_me.md`-logged deviations into this change** (`item.rb`
  missing `sig`/`extend T::Sig` on `stattrak`; `item_parser.rb`'s
  un-`T.let`-wrapped regex constants) since both files were already being
  edited for this change and both fixes were small, confirmed by `srb tc`
  diff, and within `ruby-sorbet.md` (already an Applicable Styleguide).
  Removed both entries from `fix_me.md` per the project's process.
- **Dev DB reset was explicitly re-confirmed with the user**, rather than
  silently re-run on the `item-icon-url.md` precedent alone, per the
  plan's own flagged Risk. User confirmed "да, сбросить."

## Remaining Issues

- `spec/caching/user_inventory_cache_spec.rb:18` remains failing on `main`,
  pre-existing and unrelated — already noted as an open item in
  `item-icon-url.md`, still unresolved; worth a separate look outside this
  task's scope.
- `item_parser.rb`'s `item_name` nilable-shape Sorbet mismatch and
  `user_inventory_sync_service.rb`'s un-narrowed `response.data` (now four
  call sites) remain documented in `fix_me.md`, unresolved — next person
  to touch either file should check `fix_me.md` first.
- The two follow-up tasks this change exists for ("Skip fetching
  non-marketable items", "Tiered price-fetch priority") are not
  implemented — by design, out of scope here. Both will need to decide,
  when implemented, how to treat a pre-existing `Item` whose `metadata`
  predates this change and still lacks `marketable`/`tradable`/`rarity`
  (not an issue in this session since the dev DB was reset, but will
  matter again once real data accumulates post-deploy).
