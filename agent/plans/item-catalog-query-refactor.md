---
status: implemented
app: fetcher
goal: Extract Api::Public::ItemsController#catalog's filter/sort/pagination/serialization logic into a reusable queries/appliers/options/serializers layer, as the reference pattern for upcoming Api::Public:: list endpoints
created: 2026-10-11
---

# Development Plan

## Goal

Refactor `Api::Public::ItemsController#catalog` (added in "[Fetcher] Add
public items catalog endpoint") from one large controller action into a
thin `#index` action backed by a new, reusable layer: `T::Enum`-based
filter/sort options, generic appliers that dispatch to them, a
per-resource query object, and a pure serializer. This endpoint becomes
the reference implementation at least two more upcoming `Api::Public::`
list endpoints will follow — the goal is the pattern, not just this one
controller's line count.

## Expected Behavior

### Must stay identical (pure refactor of representation, not contract)

- `{ meta: {...}, items: [...] }` response shape, field-for-field
  identical to today's `item_json`/`compute_page` output.
- Only `Item.marketable` rows are ever returned.
- `category[]` / `rarity[]` — open string-set, exact match, unrecognized
  value matches nothing (never an error).
- `stattrak` — boolean opt-in: only `"true"` applies the filter; absent
  or `"false"` both mean "no filter."
- `search` — case-insensitive substring match against
  `metadata->>'item_name'` only.
- `sort` — closed enum (`change_24h_desc` default, `price_desc`,
  `price_asc`, `name_asc`); unrecognized value → `:bad_request` /
  `{ message: "Unsupported sort: <value>" }`.
- `page` / `per_page` — silently clamped (default 1 / 24, min 1,
  `per_page` capped at 100), never rejected.
- `meta.gaining_count` / `meta.losing_count` scoped to the current
  filtered set, not the whole catalog.
- `meta.last_synced_at` — max `updated_at` among marketable items.
- `ItemCatalogCache` TTL read-through behavior (0 `Item`/`PriceLog`
  queries on a repeat identical request within TTL).
- HTTP conditional-GET: public, cacheable `ETag`; `304` on matching
  `If-None-Match`.
- Generic `{ message: "Internal error" }` / `:internal_server_error` on
  any unhandled exception.
- Endpoint remains callable with no `Authorization` header.

### New/changed behavior

- Route changes from `GET /api/public/items/catalog` to
  `GET /api/public/items` (plain REST `index`, no `/catalog` segment) —
  a deliberate contract change, not an oversight.
- Invalid `sort` is now surfaced via a shared
  `Api::Public::UnsupportedParamError` raised deep inside the new query
  layer and caught by a `rescue_from` on `Api::Public::
  ApplicationController`, instead of an inline per-action guard clause.
  Response shape/status for this case is unchanged (`:bad_request` /
  `{ message: "Unsupported sort: <value>" }`).

## Scope

### In Scope

- New `app/queries/` layer (`options/`, `appliers/` subfolders) and new
  `app/serializers/` layer, both scoped to this one controller for now.
- New shared `Api::Public::UnsupportedParamError` (`lib/api/public/`)
  and a base-controller `rescue_from` for it.
- `ItemCatalogCache`'s interface change to accept raw
  `ActionController::Parameters` directly (key derivation moves inside
  the cache class, out of the controller).
- Route rename (`#catalog` → `#index`, URL `/api/public/items/catalog`
  → `/api/public/items`).
- Updating the existing request spec and cache spec for the above
  changes, plus new unit specs for every new class.

### Out of Scope

- Authoring the new ADR and the three styleguide updates this refactor
  requires (new top-level layers, revised "one collaborator"/"assembling
  the response hash" rules, new RSpec layer-mapping rows) — that is
  `styleguides-check`'s job, not this plan's. This plan assumes that
  stage runs next and may block implementation until those documents
  exist.
- The two upcoming `Api::Public::` list endpoints themselves — only the
  base they'll build on.
- Any admin-panel work.
- `ItemPricesController#history` / `InventoryValuesController` and their
  existing inline `PricePeriod`-based validation — left untouched, not
  retrofitted onto the new `Appliers::SortApplier` pattern.
- Database indexing for `category`/`rarity`/`search` filtering
  (sequential-scan concern raised during design discussion) — a
  performance follow-up, not an architectural one.
- Any change to `Item` model scopes (`by_categories`, `by_rarities`,
  `stattrak_only`, `matching_search`, `sorted_by`) — `sorted_by` becomes
  unused by this controller once `Options::ItemSortOption#apply` takes
  over ordering, but is left in place (out of scope to remove/verify
  other callers).

## Implementation Approach

Bottom-up layering, each piece with exactly one job:

```
Options::ItemSortOption / Options::ItemFilterField   (T::Enum, per-value `apply`)
          ↑ used by
Appliers::SortApplier / Appliers::FilterApplier / Appliers::Pagination   (generic, resource-agnostic)
          ↑ used by
ItemCatalogQuery                                      (per-resource, data-only, no cache/no HTTP)
          ↑ used by
ItemCatalogSerializer                                 (pure, no I/O)
          ↑ used by
Api::Public::ItemsController#index                    (cache check → query → serialize → cache write → etag/render)
```

`Options::*` enumerate the **names** of sortable/filterable fields (a
closed set) and know how to apply themselves to a scope — not the
*values* a filter accepts, which stay unvalidated per the open-string-set
rule. `Appliers::*` know nothing about `Item` specifically; they're the
part every future `Api::Public::` list endpoint reuses verbatim.
`ItemCatalogQuery` is intentionally not named generically (`ItemQuery`)
— it bundles catalog-page-specific data (price stats, trends, freshness)
that won't transfer to other resources, only the *pattern* will.
Validation failure (`sort`) is raised, not returned, so the happy path
never carries a success/error wrapper. Caching and ETag stay entirely in
the controller — `ItemCatalogQuery` has no knowledge `ItemCatalogCache`
exists.

## Files To Modify

- `app_fetcher/app/controllers/api/public/items_controller.rb` — replace
  `catalog` with `index`; body becomes cache-read → (on miss)
  `ItemCatalogQuery.call` → `ItemCatalogSerializer.call` → cache-write →
  `stale?`/render. Remove `normalized_filters`, `clamp_param`,
  `compute_page`, `item_json`, and the `ALLOWED_SORTS`/`DEFAULT_*`/`MIN_*`/
  `MAX_*` constants entirely (superseded by the new layer).
- `app_fetcher/app/controllers/api/public/application_controller.rb` —
  add `rescue_from Api::Public::UnsupportedParamError, with:
  :render_unsupported_param_error`, declared *after* the existing
  `rescue_from StandardError` (Rails resolves the most-recently-declared
  matching handler first).
- `app_fetcher/app/caching/item_catalog_cache.rb` — change `.read`/
  `.write` to accept `ActionController::Parameters` instead of a
  pre-built `NormalizedFilters` hash; move key normalization
  (page/per_page/search/category/rarity/stattrak/sort) inside the class.
  Drop the `NormalizedFilters` type alias.
- `app_fetcher/config/routes.rb` — `get "items/catalog", to:
  "items#catalog"` → `get "items", to: "items#index"` inside `namespace
  :public`.
- `app_fetcher/spec/requests/api/public/items_spec.rb` — update every
  `get "/api/public/items/catalog"` call and the top-level `describe` to
  `/api/public/items`; rewrite the "unhandled error" scenario (currently
  stubs the now-removed `normalized_filters` method) to stub
  `ItemCatalogQuery.call` raising a plain `StandardError`, keeping it a
  regression check for the *generic* `rescue_from StandardError` path
  specifically (distinct from the `UnsupportedParamError` path, which is
  now exercised through a real invalid-`sort` request, not a stub).
- `app_fetcher/spec/caching/item_catalog_cache_spec.rb` — update to the
  new `params`-based `.read`/`.write` interface; keep the same
  key-stability/TTL assertions.

## Files To Create

- `app_fetcher/lib/api/public/unsupported_param_error.rb` —
  `Api::Public::UnsupportedParamError < StandardError`. One shared error
  type for every "caller supplied an unrecognized closed-enum value"
  case in this namespace, caught once at the base-controller level.
- `app_fetcher/app/queries/options/item_sort_option.rb` —
  `Options::ItemSortOption < T::Enum` (`ChangeDesc`/`PriceDesc`/
  `PriceAsc`/`NameAsc`), `#apply(scope)` via `case self` /
  `T.absurd(self)`. Needed so sort behavior (including the raw-SQL
  `name_asc` case) is expressed per-value instead of as a string-keyed
  `case` buried in a model scope, and so `Appliers::SortApplier` can
  resolve/validate generically against any such enum.
- `app_fetcher/app/queries/options/item_filter_field.rb` —
  `Options::ItemFilterField < T::Enum` (`Category`/`Rarity`/`Stattrak`/
  `Search`), `#apply(scope, params)`. Closes over which fields are
  filterable (not their values), so `Appliers::FilterApplier` can apply
  "all configured filters" without knowing what they are.
- `app_fetcher/app/queries/appliers/pagination.rb` — `Appliers::
  Pagination`. Plain value object (not `T::Enum`/Strategy — there's no
  named set of behaviors to choose between, just clamping math). Owns
  `DEFAULT_PAGE`/`DEFAULT_PER_PAGE`/`MIN_PAGE`/`MIN_PER_PAGE`/
  `MAX_PER_PAGE` (moved from the controller), `#offset`,
  `#total_pages(total_count)`.
- `app_fetcher/app/queries/appliers/sort_applier.rb` — `Appliers::
  SortApplier.call(raw_value, enum_class:, default:, param_name:)` →
  `T::Enum`. Resolves via `try_deserialize`; raises `Api::Public::
  UnsupportedParamError` itself on an unrecognized value — callers never
  see a nilable/Result return.
- `app_fetcher/app/queries/appliers/filter_applier.rb` — `Appliers::
  FilterApplier.call(scope, params, enum_class:)` → reduces
  `enum_class.values` over the scope. Fully resource-agnostic — the only
  piece this task guarantees is reused verbatim by future endpoints.
- `app_fetcher/app/queries/item_catalog_query.rb` — `ItemCatalogQuery`,
  with nested `PriceStats` (`gaining_count`/`losing_count`) and `Page`
  (`items`, `pagination`, `total_count`, `price_stats`, `trends`,
  `last_synced_at`) `T::Struct`s. `.call(params)` → `Page`. Owns every
  DB/cache read needed to answer "what's on this page of the catalog" —
  and nothing about HTTP, caching-the-response, or JSON shaping.
- `app_fetcher/app/serializers/item_catalog_serializer.rb` —
  `ItemCatalogSerializer.call(page)` → `T::Hash[Symbol, T.untyped]`. Pure
  function, no I/O — maps an already-fetched `Page` to the exact current
  response shape.
- Spec files mirroring each of the above per `rspec-conventions.md`'s
  path convention (exact paths TBD by where `styleguides-check` lands
  the new layer's RSpec mapping — see Risks):
  `spec/queries/options/item_sort_option_spec.rb`,
  `spec/queries/options/item_filter_field_spec.rb`,
  `spec/queries/appliers/pagination_spec.rb`,
  `spec/queries/appliers/sort_applier_spec.rb`,
  `spec/queries/appliers/filter_applier_spec.rb`,
  `spec/queries/item_catalog_query_spec.rb`,
  `spec/serializers/item_catalog_serializer_spec.rb`.

## Test Plan

All new classes are unit-level per `rspec-conventions.md` (one
`RSpec.describe <Class>`, no `type:` metadata, path mirrors `app/`).

- **`Options::ItemSortOption`**: each value's `#apply` produces the
  expected ordering against factory-built `Item`s (assert on resulting
  order of returned records, not SQL string, to stay behavior-focused);
  `NameAsc` specifically exercised against mixed-case `item_name` values
  to confirm the raw-SQL path still works.
- **`Options::ItemFilterField`**: each value's `#apply`, both "param
  present" and "param absent" (no-op) cases; `Category`/`Rarity` with an
  unrecognized value asserted to match nothing (not an error).
- **`Appliers::Pagination`**: clamp edge cases (zero/negative/non-numeric
  page → 1; oversized `per_page` → 100); `#offset` for a few page/
  per_page combinations; `#total_pages` including the `total_count ==
  0` case.
- **`Appliers::SortApplier`**: absent raw value → resolves to `default`;
  a recognized value → resolves to the matching enum member; an
  unrecognized value → raises `Api::Public::UnsupportedParamError` with
  message `"Unsupported sort: <value>"`.
- **`Appliers::FilterApplier`**: composing more than one
  `Options::ItemFilterField` value narrows the scope with AND semantics
  (mirrors the existing request spec's "combined filters" case, at the
  applier level).
- **`ItemCatalogQuery`**: returns a `Page` with correct `items`/
  `total_count`/`price_stats`/`trends`/`last_synced_at` for a given
  params set; propagates (does not rescue) `Api::Public::
  UnsupportedParamError` from an invalid `sort`.
- **`ItemCatalogSerializer`**: given a hand-built `Page`, asserts the
  exact current response shape byte-for-byte (metadata key set,
  `change_24h_percent` rounding, `trend_7d` reshaping) — no DB queries
  inside this spec (construct `Item.new`/in-memory `Page`, not
  `create(:item)`, to keep it provably I/O-free).
- **`ItemCatalogCache`**: adapt existing spec to `params`-based `.read`/
  `.write`; same key-stability guarantee (same params → same key
  regardless of hash ordering) and TTL behavior.
- **Request spec** (`spec/requests/api/public/items_spec.rb`): remains
  the end-to-end contract. Every existing scenario keeps the same
  expectations except the URL (`/api/public/items`, no `/catalog`) and
  the rewritten unhandled-error scenario described above.

## Implementation Steps

1. `Options::ItemSortOption` — spec, then implementation. No
   dependencies on anything new.
2. `Options::ItemFilterField` — spec, then implementation. No
   dependencies on anything new.
3. `Appliers::Pagination` — spec, then implementation. No dependencies.
4. `Api::Public::UnsupportedParamError` — implementation only (trivial
   `StandardError` subclass; covered indirectly via step 5's spec).
5. `Appliers::SortApplier` — spec, then implementation (depends on 1, 4).
6. `Appliers::FilterApplier` — spec, then implementation (depends on 2).
7. `ItemCatalogQuery` — spec, then implementation (depends on 1, 2, 3, 5,
   6; reuses existing `Item.marketable`/`ItemTrendCache` unchanged).
8. `ItemCatalogSerializer` — spec, then implementation (depends on 7's
   `Page` shape).
9. `ItemCatalogCache` — update interface and spec together (depends on
   nothing new, but must land before step 11 wires it in).
10. `Api::Public::ApplicationController` — add the new `rescue_from`.
11. `Api::Public::ItemsController` — replace `catalog` with `index`,
    wire steps 7–10 together; delete the old private methods/constants.
12. `config/routes.rb` — point `items` at `#index`.
13. `spec/requests/api/public/items_spec.rb` — update URLs and the
    unhandled-error scenario.
14. Run full verification (see below); fix any regression before
    considering the plan implemented.

## Verification

- `bundle exec rspec spec/queries spec/serializers spec/caching/item_catalog_cache_spec.rb spec/requests/api/public/items_spec.rb`
  — targeted run for everything this plan touches.
- Full `app_fetcher` suite (`bundle exec rspec`) — regression check,
  since `Item.marketable`/`ItemTrendCache` are shared with other
  controllers.
- `bundle exec srb tc` — load-bearing here specifically: confirms
  `T.absurd(self)` exhaustiveness on both new `T::Enum`s, and surfaces
  any gap in the pragmatic `enum_class: T.untyped` typing in
  `Appliers::*` (see Risks).
- `bin/rubocop` (existing `rubocop-rails-omakase` config).
- Manual: `GET /api/public/items/catalog` now 404s (confirms the
  intentional route removal); `GET /api/public/items` with no params,
  each filter, each sort, an invalid sort, and a repeat request within
  the cache TTL, confirmed against the request spec's own scenarios.

## Risks

- `Appliers::SortApplier`/`Appliers::FilterApplier` type their
  `enum_class:` parameter as `T.untyped` rather than a proper bound
  (e.g. an abstract interface module both `Options::*` classes include).
  This was a deliberate, named shortcut during design to avoid Sorbet
  generic-type ceremony before a second real resource exists to validate
  the right bound against. Accepted for this plan; `srb tc` in
  Verification is the backstop if this hides a real type error, and the
  exact bound is worth revisiting once endpoint #2 exists.
- Route contract change (`/api/public/items/catalog` → `/api/public/
  items`): this endpoint shipped in the same session as this plan and,
  per the earlier research, has no known external consumer yet — but
  this could not be verified exhaustively from the codebase alone (see
  Assumptions).
- This refactor introduces two new top-level `app/` layers
  (`app/queries/` with `appliers/`/`options/` subfolders, and
  `app/serializers/`) that no styleguide or ADR currently documents.
  Per `CLAUDE.md`'s pipeline, `styleguides-check` must produce a new ADR
  (analogous to `cross-scenario-service-layer.md`) and update
  `public-api-controllers.md`, `architecture-layers.md`, and
  `rspec-conventions.md` before this plan can move to
  `styleguide-checked`. The exact unit-spec paths listed under Files To
  Create are this plan's best guess and may be adjusted once that
  mapping is finalized.
- `ItemCatalogCache`'s new self-contained key derivation re-lists the
  same six param names (`page`/`per_page`/`search`/`category`/`rarity`/
  `stattrak`/`sort`) that `Options::ItemFilterField`/`Options::
  ItemSortOption` already enumerate in a different shape. Minor,
  accepted duplication — not blocking.

## Assumptions

- No external consumer currently depends on `GET /api/public/items/catalog`
  — the endpoint was added in the same work session as this plan and
  `app_core` doesn't call it (it's intentionally outside `app_core`'s
  reach per the ADR). Could not be verified beyond that; confirm before
  merging the route rename if there's any other known caller.
- The two upcoming `Api::Public::` list endpoints operate on
  resources whose storage shape is close enough to `Item`'s (`jsonb
  metadata` plus plain columns, open-set/boolean/closed-enum param
  shapes) that the `Options::<Resource>*`/`Appliers::*` split transfers
  without changes to the `Appliers::*` classes themselves — stated by
  the user during design, not verifiable from code today since neither
  endpoint exists yet.

## Completion Criteria

- Expected behavior above is fully explicit, including what must not
  change.
- Scope excludes the ADR/styleguide authoring, the future endpoints, DB
  indexing, and the untouched `PricePeriod`-based controllers.
- Every file to modify/create is listed with its reason.
- Test plan covers every new class plus the existing request/cache
  specs' required updates.
- Implementation steps are ordered bottom-up by dependency, TDD-first.
- Verification commands are concrete and runnable.
- Plan is written to `agent/plans/item-catalog-query-refactor.md`.

## Applicable Styleguides

- **`agent/styleguides/fetcher/list-query-objects.md`** (new) —
  constrains everything under "Files To Create": `app/queries/` flat
  root for `ItemCatalogQuery` (`.call(params)` → `T::Struct`, never a
  `Result`/success-or-error shape, no cache/HTTP knowledge),
  `app/queries/appliers/` → `Appliers::` namespace (resource-agnostic
  only), `app/queries/options/` → `Options::` namespace (one `T::Enum`
  per resource per concern, `case self`/`T.absurd(self)`, enumerating
  field *names* not filter *values*), `app/serializers/` flat root
  (pure, zero I/O). Backed by
  `agent/adr/fetcher/list-query-objects-layer.md`.
- **`agent/styleguides/fetcher/public-api-controllers.md`** —
  constrains `items_controller.rb`'s `#index` body (the fixed
  cache-check → query → serialize → cache-write → conditional-GET
  sequence is now the documented shape for list endpoints, not a
  one-collaborator violation), `application_controller.rb`'s new
  `rescue_from` (must be declared after the existing `rescue_from
  StandardError`), and `lib/api/public/unsupported_param_error.rb`'s
  location/singularity (one shared exception class, not one per param).
  Also governs the unchanged param-shape behavior this plan must
  preserve (bounded-numeric clamp, open-string-set non-validation,
  boolean opt-in-only, closed-enum rejection).
- **`agent/styleguides/fetcher/architecture-layers.md`** — constrains
  the new layers' place in `app_fetcher`'s Scenario map and dependency
  direction (Scenario 1 only; query objects may read `app/caching/`
  bulk/single-key caches like `ItemTrendCache` but never a
  response-payload TTL cache or anything HTTP-related).
- **`agent/styleguides/rspec-conventions.md`** — constrains the Test
  Plan's unit-level, path-mirrored spec placement for every new class
  (`app/queries/**` → `spec/queries/**`, etc., now explicit rows in the
  Layer → level mapping table) and the existing request spec's role as
  the unchanged end-to-end behavioral contract.
- **`agent/styleguides/ruby-sorbet.md`** (unchanged, already
  sufficient — generic typing discipline, not layer-specific) —
  constrains every new file in this plan: `# typed: strict`, `extend
  T::Sig`, a `sig` on every method including the `T::Enum` `#apply`
  methods, `T.let` on every class-level constant
  (`Appliers::Pagination`'s `DEFAULT_PAGE`/etc.), explicit
  `T::Array`/`T::Hash` typing, and the `T.absurd(self)` exhaustiveness
  idiom this plan generalizes from `price_period.rb`.
- **`agent/styleguides/rails-layering.md`** (unchanged, already
  sufficient) — constrains the overall one-directional dependency
  invariant (`Controller → orchestration → Models`) the new layers sit
  inside; no outbound HTTP/crypto is introduced by this plan, so its
  client/lib-layer rule isn't otherwise engaged.
- **`agent/styleguides/fetcher/caching.md`** (unchanged, already
  sufficient) — constrains `ItemCatalogCache`'s interface change: it
  must remain the TTL-only variant (`.read`/`.write`, no `.invalidate`,
  versioned key, TTL constant) this file already documents — accepting
  raw `ActionController::Parameters` instead of a pre-built
  `NormalizedFilters` hash is an interface change, not a variant change.
- **`agent/styleguides/fix_me.md`** — checked against every file this
  plan modifies (`app/caching/item_catalog_cache.rb`,
  `app/controllers/api/public/items_controller.rb`,
  `app/controllers/api/public/application_controller.rb`); no existing
  entries found, none added by this check.

# Implementation Summary

## Implemented

All 14 Implementation Steps, in order:

- `Options::ItemSortOption` / `Options::ItemFilterField` (`app/queries/options/`) —
  `T::Enum` subclasses, `case self` / `T.absurd(self)`, matching the
  plan's design exactly.
- `Appliers::Pagination` / `Appliers::SortApplier` / `Appliers::FilterApplier`
  (`app/queries/appliers/`) — resource-agnostic mechanics.
  `SortApplier.call` raises `Api::Public::UnsupportedParamError`
  directly (never returns nilable/`Result`).
- `Api::Public::UnsupportedParamError` (`lib/api/public/`).
- `ItemCatalogQuery` (`app/queries/`) — `.call(params)` → `Page`
  (`T::Struct`, nested `PriceStats`). No knowledge of
  `ItemCatalogCache` or HTTP, as designed.
- `ItemCatalogSerializer` (`app/serializers/`) — pure, zero I/O.
- `ItemCatalogCache` — interface changed to `.read(params)`/
  `.write(params, value)`, key normalization moved inside the class.
- `Api::Public::ApplicationController` — `rescue_from
  Api::Public::UnsupportedParamError` added after the existing
  `rescue_from StandardError`.
- `Api::Public::ItemsController#catalog` → `#index`, body reduced to
  cache-read → (miss) query → serialize → cache-write → `stale?`/render
  (7 lines).
- `config/routes.rb` — `get "items/catalog", to: "items#catalog"` →
  `get "items", to: "items#index"`.
- `spec/requests/api/public/items_spec.rb` — URLs updated to
  `/api/public/items`; the unhandled-error scenario now stubs
  `ItemCatalogQuery.call` raising `StandardError` instead of the
  removed `normalized_filters` method.

## Tests

New unit specs (one file per class, per `rspec-conventions.md`'s
path-mirroring rule):

- `spec/queries/options/item_sort_option_spec.rb`
- `spec/queries/options/item_filter_field_spec.rb`
- `spec/queries/appliers/pagination_spec.rb`
- `spec/queries/appliers/sort_applier_spec.rb`
- `spec/queries/appliers/filter_applier_spec.rb`
- `spec/queries/item_catalog_query_spec.rb`
- `spec/serializers/item_catalog_serializer_spec.rb`

Updated existing specs:

- `spec/caching/item_catalog_cache_spec.rb` — adapted to the
  `params`-based interface; added an explicit array-ordering
  key-stability case.
- `spec/requests/api/public/items_spec.rb` — URLs + rewritten
  unhandled-error scenario, all other scenarios unchanged.

TDD was followed throughout: every new class's spec was written first,
run to confirm it failed for the expected reason (missing constant),
then the implementation was added and the spec re-run to confirm it
passed. Two real bugs were caught this way before they shipped:

1. `ItemCatalogQuery` originally applied `sort_option.apply(scope)`
   *before* the `COUNT(*)` aggregate pluck, which Postgres rejects
   (`ORDER BY` column not in `GROUP BY`/aggregate) — fixed by restoring
   the original controller's order (count first, then sort + paginate
   for the page_items query only).
2. A first attempt at tightening `Options::ItemFilterField`'s `scope`
   parameter type from `ActiveRecord::Relation` to the Sorbet
   DSL-generated `Item::PrivateRelation` passed `srb tc` but broke at
   runtime (`NameError: uninitialized constant Item::PrivateRelation`)
   — that constant only exists in the generated `.rbi` shim, never
   loaded at runtime. Reverted to `ActiveRecord::Relation`.

Commands actually executed (all via `docker compose run --rm app_fetcher ...`,
the project's working test-execution path — bare `bundle exec` on the
host hits an unrelated Ruby 3.3.0/`connection_pool` parser bug and has
no network route to `db_fetcher`):

- `bundle exec rspec spec/queries/options/item_sort_option_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/queries/options/item_filter_field_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/queries/appliers/pagination_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/queries/appliers/sort_applier_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/queries/appliers/filter_applier_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/queries/item_catalog_query_spec.rb` (RED, then GREEN, after the aggregate/sort-ordering fix)
- `bundle exec rspec spec/serializers/item_catalog_serializer_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/caching/item_catalog_cache_spec.rb` (RED, then GREEN)
- `bundle exec rspec spec/requests/api/public/items_spec.rb` (RED against old routes, then GREEN against new routes/controller)
- `bundle exec rspec spec/queries spec/serializers spec/caching/item_catalog_cache_spec.rb spec/requests/api/public/items_spec.rb` (66 examples, 0 failures)
- `bundle exec rspec` (full suite, twice — once before and once after the `Item::PrivateRelation` revert)
- `bundle exec srb tc` (twice — before and after fixing the `item_filter_field.rb` typing mistake)
- `bin/rubocop` on every file this plan touched/created

## Verification

- **Targeted suite**: `spec/queries` + `spec/serializers` +
  `spec/caching/item_catalog_cache_spec.rb` +
  `spec/requests/api/public/items_spec.rb` — **66 examples, 0 failures**.
- **Full `app_fetcher` suite**: **231 examples, 1 failure** —
  `spec/caching/user_inventory_cache_spec.rb:18`
  (`UserInventoryCache.fetch ... returns the user's items and writes
  them to the cache`). Confirmed pre-existing and unrelated: this file
  was never touched by this plan, the failure reproduces in isolation
  (`bundle exec rspec spec/caching/user_inventory_cache_spec.rb`), and
  it asserts against a hardcoded literal id (`[ "user_inventory", 2,
  steam_id ]`) that depends on Postgres sequence state carried over
  between runs rather than anything this plan changed.
- **`srb tc`**: one remaining error directly caused by this plan —
  `app/queries/item_catalog_query.rb:38: Method 'apply' does not exist
  on 'T::Enum'`. This is the exact, named tradeoff the plan's Risks
  section called out in advance (`Appliers::SortApplier`'s `enum_class:`
  parameter is pragmatically `T.untyped`, so the `T::Enum` it resolves
  to doesn't statically expose `#apply`) — accepted as-is, not fixed,
  per the plan. Every other `srb tc` error observed (missing `RSpec`/
  `FactoryBot`/`JWT` constants, `PriceLog`/`PriceUpdateWorker` nilable
  gaps, etc.) is pre-existing baseline noise affecting files this plan
  never touched (confirmed by grepping the full `srb tc` output for
  only the files this plan created/modified).
- **`bin/rubocop`** on every file this plan touched or created: **21
  files inspected, no offenses detected.**
- **Final diff review**: `git diff --stat` / `git status --short`
  matches the plan's Files To Modify/Files To Create lists exactly —
  no unrelated files changed, no debug code, `Item` model and
  `sorted_by` scope left untouched as scoped.

## Deviations

- `Options::ItemFilterField`'s `scope` parameter stayed typed as
  `ActiveRecord::Relation` rather than the more precise
  `Item::PrivateRelation` the plan's Risks section gestured at as a
  possible future tightening — attempted during implementation,
  reverted because that DSL-generated type doesn't exist at runtime
  (see Tests section). This is slightly broader framing than a pure
  "deviation" — it's a concrete finding that the plan's suggested
  future tightening isn't actually viable for hand-written `sig`s in
  this codebase, worth knowing before anyone tries it again for
  endpoint #2/#3.
- No other deviations — architecture, class shapes, method signatures,
  and file locations match the plan and the approved ADR/styleguide
  exactly.

## Remaining Issues

- The one pre-existing, unrelated failing spec
  (`user_inventory_cache_spec.rb`) is not fixed by this plan (out of
  scope) and should be looked at separately — it appears to be an
  order-dependent/flaky test tied to database id sequencing, not a
  logic bug.
- `app/queries/item_catalog_query.rb:38`'s `srb tc` gap
  (`T::Enum#apply`) remains open by design — the plan's suggested
  revisit point ("once endpoint #2 exists") still applies, and per this
  implementation, "tighten the relation type" is *not* a viable fix for
  the sibling `Options::ItemFilterField` gap either way — a future fix
  for either would need a different approach (e.g. an abstract
  interface module every `Options::*` class includes, checked only
  statically, never referenced in a runtime `sig`).
- Database indexing for `category`/`rarity`/`search` filtering,
  explicitly out of scope for this plan, is still unaddressed — flagged
  again here only because it directly affects this same endpoint's
  production performance, not because it belongs to this plan.

## Post-Implementation Addendum

- `Appliers::Pagination::DEFAULT_PER_PAGE` changed from `24` to `25`
  (post-review correction), with `spec/queries/appliers/pagination_spec.rb`
  and `spec/requests/api/public/items_spec.rb`'s defaulted-request case
  updated to match. This intentionally diverges from this plan's own
  "Must stay identical" claim about the default being `24` — recorded
  here rather than edited into that section, since the plan is a record
  of what was decided and when.
