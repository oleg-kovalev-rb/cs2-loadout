---
description: app_fetcher's app/queries/ (per-resource query objects, plus Appliers:: and Options:: subfolders) and app/serializers/ layers — shared filter/sort/pagination mechanics and response-shaping for Api::Public:: list and detail endpoints.
---

# List Query Objects (`app/queries/`, `app/serializers/`)

See `agent/adr/fetcher/list-query-objects-layer.md` for why this is a
new layer rather than an extension of `app/services/`, and why the
per-resource query class is deliberately not generalized into one
config-driven facade yet. This file covers how code in these layers is
written, once that decision is taken as given.

## Purpose

Give every `Api::Public::` list endpoint (filter + sort + pagination +
response shaping over a paginated resource) a consistent, reusable place
for each piece of that mechanics, instead of writing it inline in the
controller action. The same layer also covers a *detail* endpoint — one
resource looked up by an identifier, which may itself carry a single
embedded paginated/sorted sub-collection plus its own bespoke aggregates
(see Structure's `<Resource>DetailQuery`) — since it leans on the exact
same closed-enum/pagination mechanics, just applied to one resource at a
time instead of a page of many. What belongs here: resolving/validating
closed-enum query params, applying named filters to a scope, clamping
pagination, fetching the data a response needs, and shaping that data
into a response hash. What does not: anything with a notion of caller
identity (that's `Api::V1::`'s job, if it ever needs this pattern),
persisting data, or calling `Steam::Client` — this layer only ever reads
already-persisted data for a response, the same carve-out
`architecture-layers.md` already states for `PriceHistoriesController`.

## When to Use

Use this layer when a new `Api::Public::` (or, in principle, `Api::V1::`)
action needs filter/sort/pagination/response-shaping mechanics shared
with at least one other such action. For a one-off action with no
sibling needing the same mechanics, inline logic in the controller (or a
single plain scope on the model) is still preferred — do not reach for
this layer just because an action has "a few query params," the same way
`app/services/` isn't the default home for "this feels like business
logic" (see that layer's own ADR). As of this writing, three
`Api::Public::` list endpoints are expected to use this layer; a
single-endpoint feature should not pre-emptively adopt it as a header-ful
shape.

A shared read-only calculation used by more than one of those actions —
or by a query object, an action, and a cross-Scenario service — also
belongs here, as a concern query (`InventoryValuation`), not as a third
per-resource catalog/detail class. The same test applies: a single
caller with a one-off aggregate should stay inline or in that resource's
own query object.

## Structure

- **`app/queries/<resource>_catalog_query.rb`** (flat root, e.g.
  `ItemCatalogQuery`) — one class per resource/endpoint, not one generic
  class across resources. Named `<Resource>CatalogQuery`, never a bare
  `<Resource>Query` — the name should signal that the class may carry
  resource-specific business logic (aggregates, enrichment lookups) that
  won't generalize to other resources, not imply a reusable abstraction
  that isn't there.
- **`app/queries/<resource>_detail_query.rb`** (flat root, e.g.
  `InventoryDetailQuery`) — the sibling shape for a *detail* endpoint:
  one resource looked up by an identifier (e.g. `steam_id`), not a page
  of many. Named `<Resource>DetailQuery`, the same naming logic as
  `<Resource>CatalogQuery` above. May still compose
  `Appliers::Pagination`/`Appliers::SortApplier`/`Options::*` for a
  single embedded paginated/sorted sub-collection within that one
  resource (e.g. `InventoryDetailQuery`'s `top_items`), on top of
  whatever bespoke scalar aggregates the resource needs.
- **`app/queries/<concern>.rb`** (flat root, e.g.
  `InventoryValuation`) — a shared, read-only calculation over
  already-persisted data whose result is consumed by more than one query
  object, controller action, or cross-Scenario service, rather than
  shaping one endpoint's response. Named for the concern, not as
  `<Resource>CatalogQuery`/`<Resource>DetailQuery`, because it is not an
  endpoint query. It returns `T::Struct`s (never a response hash) and
  may own the SQL aggregate expressions shared by the single-resource
  and bulk/catalog paths. It may be called by a
  `<Resource>CatalogQuery`/`<Resource>DetailQuery`, an `Api::V1::`
  controller action, and a cross-Scenario service; it never calls a
  controller or a service, never writes, and never caches a response
  payload.
- **`app/queries/appliers/`** → `Appliers::` namespace (Zeitwerk:
  subfolder of an autoloaded `app/` root becomes a namespace, same rule
  already used by `app/serializers/admin/` → `Admin::`). Fully
  resource-agnostic classes — never reference a specific model or a
  specific `Options::*` member by name.
- **`app/queries/options/`** → `Options::` namespace. One `T::Enum`
  subclass per resource per concern (e.g. `Options::ItemSortOption`,
  `Options::ItemFilterField`), named `<Resource><Concern>` —
  `SortOption` / `FilterField`.
- **`app/serializers/<resource>_catalog_serializer.rb`** (flat root,
  e.g. `ItemCatalogSerializer`) — one per resource/endpoint, pure
  function style, same flat-root convention as `app/services/`/
  `app/caching/`.
- **`app/serializers/<resource>_detail_serializer.rb`** (flat root, e.g.
  `InventoryDetailSerializer`) — `<Resource>DetailQuery`'s serializer
  counterpart; same pure-function rule as `<Resource>CatalogSerializer`.

## Interface

- **`Options::*`**: a `T::Enum` subclass. Each enum value implements
  `#apply(scope)` (sort) or `#apply(scope, params)` (filter), dispatched
  internally via `case self`, closed with `else T.absurd(self)` so
  Sorbet guarantees every value is handled. An enum here closes over the
  **names** of sortable/filterable fields (a closed set) — never over
  the **values** a filter accepts. `category`/`rarity`-style open
  string-set params still match-or-don't against arbitrary caller input
  inside the enum value's own `#apply` body; the enum does not validate
  those values against anything.
- **`Appliers::Pagination`**: plain value object, not `T::Enum`. `.new(raw_page,
  raw_per_page, default_per_page: DEFAULT_PER_PAGE)` clamps silently (see
  `public-api-controllers.md`'s bounded-numeric rule — never
  raises/rejects). The `default_per_page:` keyword lets each call site
  pick its own default (e.g. `25` for an items catalog, `24` for an
  inventories list, `12` for a nested sub-collection like `top_items`)
  without forking the class — a literal default supplied by the caller
  isn't a reference to any specific resource/model/`Options::*` class, so
  this doesn't violate the "depend on nothing resource-specific" rule in
  Dependencies below. `min`/`max` stay fixed constants shared by every
  caller; only the default is overridable. Instance methods `#page`,
  `#per_page`, `#offset`, `#total_pages(total_count)`.
- **`Appliers::SortApplier.call(raw_value, enum_class:, default:,
  param_name: "sort")`** → a resolved `T::Enum` member (never nilable).
  Raises `Api::Public::UnsupportedParamError` on an unrecognized,
  present value — absence always resolves to `default`, never an error.
  `enum_class` may be *any* closed-enum `T::Enum` a param needs to
  resolve against, not only an `Options::*` sort enum whose members
  implement `#apply(scope)` — this applier's own mechanism
  (`try_deserialize` + raise + overridable `param_name:`) never actually
  depends on `#apply` existing; what the resolved member is used for
  afterward is entirely up to the call site. `PricePeriod`
  (`app_fetcher/app/models/price_period.rb`, used for a `range`-style
  param) is the precedent for this broader use: a plain `T::Enum` outside
  `Options::*` entirely, with its own `#duration` instance method instead
  of `#apply`, resolved through this same applier unchanged.
- **`Appliers::FilterApplier.call(scope, params, enum_class:)`** →
  `ActiveRecord::Relation`, by reducing `enum_class.values` over the
  scope.
- **`<Resource>CatalogQuery.call(params)`** → a `T::Struct` (e.g.
  `ItemCatalogQuery::Page`) carrying everything a response needs — items,
  pagination, counts, any resource-specific extras. Never a `Result`-style
  success/error wrapper: the one failure mode (invalid `sort`) is raised
  by `Appliers::SortApplier`, not returned, so `.call` either returns a
  valid struct or doesn't return at all.
- **`<Resource>DetailQuery.call(identifier, params)`** → a `T::Struct`
  carrying everything a detail response needs — the looked-up resource's
  own fields, any bespoke aggregates, and (if applicable) one embedded
  paginated/sorted sub-collection's items plus its own pagination. Never
  a `Result`-style wrapper, same as `<Resource>CatalogQuery` — its one
  extra failure mode (the identifier doesn't resolve to a record) is
  raised as `ActiveRecord::RecordNotFound` via a bang finder (`Model.
  find_by!(...)`), never returned as `nil`; see
  `public-api-controllers.md`'s Error Handling shape (4) for how the
  controller's base class catches it.
- **`<Resource>CatalogSerializer.call(<query-result-struct>)`** →
  `T::Hash[Symbol, T.untyped]`. Pure function — no argument may be
  anything that requires a database or cache read; all data must already
  be resolved by the time this is called.
- **`<Resource>DetailSerializer.call(<query-result-struct>)`** →
  `T::Hash[Symbol, T.untyped]`. Same pure-function rule as
  `<Resource>CatalogSerializer`.

## Responsibilities

- `Options::*` own per-value behavior for one named field (ordering
  logic, a `where` clause) — not param parsing, not validation of
  *whether* a value was supplied.
- `Appliers::*` own generic resolution/clamping/dispatch mechanics —
  never resource-specific logic, never which fields exist for a given
  resource.
- `<Resource>CatalogQuery` owns every database/cache read needed to
  answer "what does this page need" — including resource-specific
  aggregates and enrichment lookups (e.g. `Item`'s price-change counts,
  trend data) — and nothing about HTTP or response-level caching.
- `<Resource>DetailQuery` owns the same kind of work as
  `<Resource>CatalogQuery`, scoped to one resource instead of a page: the
  lookup by identifier (raising on a miss, never returning `nil`), any
  bespoke aggregates, and composing `Appliers::*`/`Options::*` for its
  own embedded sub-collection, if it has one.
- `<Resource>CatalogSerializer` owns response-shape mapping only.
- `<Resource>DetailSerializer` owns response-shape mapping only, same as
  `<Resource>CatalogSerializer`.
- The controller owns: calling the query object, calling the serializer,
  `ItemCatalogCache`-style response caching, and conditional-GET
  (`stale?`/`ETag`) — none of that belongs in any class above.

## Dependencies

One-directional: `<Resource>CatalogQuery` may depend on `Appliers::*`,
`Options::*`, model scopes, existing `app/caching/` *data* caches
(e.g. `ItemTrendCache` — bulk read-through caches for already-known
lookups, per `caching.md`), and shared read-only concern queries in this
same layer (e.g. `InventoryValuation`), but never on a response-payload
cache like `ItemCatalogCache` or anything HTTP-related.
`<Resource>CatalogSerializer` depends on nothing but its input struct.
`Appliers::*` depend on nothing resource-specific — not even indirectly,
by referencing a concrete `Options::*` class by name inside an
`Appliers::*` file. `Options::*` depend only on the model scopes they
call from `#apply`. The identical dependency rules apply to
`<Resource>DetailQuery`/`<Resource>DetailSerializer` — the shape of what
each class may depend on doesn't change between the list and detail
cases, only how many of the resource it answers for.

A concern query (`InventoryValuation`) may depend on `Appliers::*`/
`Options::*`, model scopes, and existing `app/caching/` data caches, and
may be called by the resource queries above, an `Api::V1::` read action,
or a cross-Scenario service. It must not depend on a serializer,
controller, response-payload cache, or service, and it performs no
writes. A concern query doesn't call another concern query just to
re-shape its result — compose the structs at the call site instead.

## Rules

### MUST

- One `T::Enum` subclass per resource per concern under
  `app/queries/options/`, exhaustiveness-checked with `T.absurd(self)` —
  never a plain `T.let(%w[...], T::Array[String])` + string `case` for a
  new closed-enum query param in this layer.
- `Appliers::SortApplier`/`Appliers::FilterApplier` must never reference
  a specific model, scope, or `Options::*` class by name.
- `<Resource>CatalogQuery.call` must never reference an
  `app/caching/` response-payload cache (e.g. `ItemCatalogCache`) or
  `ActionController`/HTTP types beyond accepting `ActionController::Parameters`
  as its input.
- `<Resource>CatalogSerializer` must perform zero I/O — no `ActiveRecord`
  query, no `Rails.cache` call, inside its `.call`.
- `<Resource>DetailQuery.call` must look up its resource with a bang
  finder (`Model.find_by!(...)`) and let a miss raise
  `ActiveRecord::RecordNotFound` — never check for `nil` and return early
  or build a `Result`-shaped failure value.
- `<Resource>DetailSerializer` must perform zero I/O, same rule as
  `<Resource>CatalogSerializer`.
- A shared concern query (`InventoryValuation`) must return `T::Struct`
  values, never a response hash; response shaping stays in the matching
  serializer. It must perform no writes and must not call a
  response-payload cache.

### SHOULD

- Name the per-resource query class `<Resource>CatalogQuery`, not
  `<Resource>Query` — see Structure.
- Keep `<Resource>CatalogQuery.call`'s return type a plain `T::Struct`,
  not a `Result`/outcome wrapper — see the ADR's "Alternatives
  Considered" for why that was tried and reverted.
- Name a detail endpoint's query/serializer pair `<Resource>DetailQuery`/
  `<Resource>DetailSerializer` — the sibling convention to
  `<Resource>CatalogQuery`/`<Resource>CatalogSerializer` — and keep
  `<Resource>DetailQuery.call`'s return type a plain `T::Struct` too, for
  the same reason.

### MUST NOT

- Don't enumerate a filter's *allowed values* as `Options::*` enum
  members — only field *names* belong there. Open string-set param
  values (`category`, `rarity`) stay unvalidated inside the relevant
  enum value's own `#apply`, per `public-api-controllers.md`.
- Don't generalize `<Resource>CatalogQuery` into one config-driven class
  shared across resources before a second resource's concrete needs
  confirm the right shared shape (see ADR, "wait for a third example").
- Don't put cache-read/write or `stale?`/`ETag` logic inside any class in
  this layer — that stays in the controller.

## Error Handling

This layer produces two failure modes, neither of which it catches
itself — both propagate to the controller's base class:

1. An unrecognized closed-enum value, raised as `Api::Public::
   UnsupportedParamError` from `Appliers::SortApplier` (or, in principle,
   from an `Options::*` value's own `#apply` if a future resource ever
   needs a closed-enum-shaped filter — the mechanism is the same).
2. For a `<Resource>DetailQuery`, an identifier that doesn't resolve to a
   record, raised as `ActiveRecord::RecordNotFound` by its bang finder
   (never returned as `nil` — see Rules).

See `public-api-controllers.md`'s Error Handling section for shapes (2)
and (4) respectively — the exceptions' definitions/sources and the
`rescue_from` pair that catches each — not restated here.

## Interaction With Other Layers

```text
Api::Public::<X>Controller#index
    ↓ ItemCatalogCache.read(params)  — cache check, controller's job
    ↓ (on miss)
<Resource>CatalogQuery.call(params)
    ↓ Appliers::SortApplier.call(...) → Options::<Resource>SortOption member (or raises)
    ↓ Appliers::FilterApplier.call(...) → Options::<Resource>FilterField.values.reduce(...)
    ↓ model scopes, app/caching/ data caches (e.g. ItemTrendCache)
    → <Resource>CatalogQuery::Page (T::Struct)
<Resource>CatalogSerializer.call(page) → response hash
    ↓ ItemCatalogCache.write(params, payload)  — controller's job
    ↓ stale?/render  — controller's job
```

A concern query is a read-only sub-step, not an endpoint: a
`<Resource>CatalogQuery`/`<Resource>DetailQuery` or an `Api::V1::` read
action may call it (and a cross-Scenario service may call it for its own
read step), but it never renders, caches a payload, or writes.

The detail shape follows the same sequence, just keyed by an identifier
instead of a page of filters, and with one failure branch the list shape
doesn't have:

```text
Api::Public::<X>Controller#show
    ↓ <Resource>DetailCache.read(identifier, params)  — cache check, controller's job
    ↓ (on miss)
<Resource>DetailQuery.call(identifier, params)
    ↓ Model.find_by!(identifier)  → raises ActiveRecord::RecordNotFound, or continues
    ↓ Appliers::SortApplier.call(...) / Appliers::Pagination.new(...)  — for one embedded sub-collection, if any
    ↓ model scopes, app/caching/ data caches
    → <Resource>DetailQuery::Page (T::Struct)
<Resource>DetailSerializer.call(page) → response hash
    ↓ <Resource>DetailCache.write(...)  — controller's job
    ↓ stale?/render  — controller's job
```

## Testing

Unit-level for every class in this layer, per `rspec-conventions.md`'s
default mapping and path-mirroring rule (`app/queries/**` →
`spec/queries/**`, etc. — see that file's Layer → level mapping table).
Specific to this layer:

- `Options::*` specs exercise each enum value's `#apply` against real
  (factory-built) records, not just that the right `case` branch is hit
  — confirm the resulting scope actually returns/orders the expected
  rows.
- `Appliers::*` specs should not require a specific resource's
  `Options::*` class to prove genericity — exercising them against
  whichever concrete `Options::*` class already exists is acceptable
  (no obligation to build a throwaway test-only enum).
- `<Resource>CatalogQuery` specs hit the database for real (it's a query
  object) but must never stub or reference `app/caching/`'s
  response-payload cache — that cache does not exist from this class's
  point of view.
- `<Resource>CatalogSerializer` specs must not use `create(:record)` —
  use an unsaved/in-memory instance (e.g. `Item.new(...)`) to keep the
  spec provably free of database access, matching the class's own
  zero-I/O rule.
- `<Resource>DetailQuery` specs follow the same DB-for-real,
  no-response-payload-cache rules as `<Resource>CatalogQuery`, plus one
  scenario `<Resource>CatalogQuery` doesn't need: an unknown identifier
  raising `ActiveRecord::RecordNotFound`.
- `<Resource>DetailSerializer` specs follow the same zero-I/O,
  unsaved-instance rule as `<Resource>CatalogSerializer`.
- A shared concern query (`InventoryValuation`) is a unit spec under
  `spec/queries/`, hitting the database for real (like the resource
  queries) and never referring to a response-payload cache. Cover the
  single-resource and bulk paths from the same examples where the shared
  aggregate is what guarantees they cannot drift; assert the returned
  structs, not raw rows.

## Canonical Implementations

None yet — `ItemCatalogQuery`/`ItemCatalogSerializer`/
`Options::ItemSortOption`/`Options::ItemFilterField`/`Appliers::Pagination`/
`Appliers::SortApplier`/`Appliers::FilterApplier`
(`agent/plans/item-catalog-query-refactor.md`) are this layer's first
members. Update this section once that plan is implemented.

The detail shape (`<Resource>DetailQuery`/`<Resource>DetailSerializer`),
`Appliers::SortApplier`'s generalized use against a non-`Options::*`
enum (`PricePeriod`, for a `range`-style param), and
`Appliers::Pagination`'s `default_per_page:` keyword also have no
implementation yet — `InventoryDetailQuery`/`InventoryDetailSerializer`
and `InventoryCatalogQuery` (`agent/plans/public-inventory-endpoints.md`)
will be their first examples. Update this section once that plan is
implemented.

A shared concern query has no implementation yet — `InventoryValuation`
(`agent/plans/inventory-valuation-consistency.md`) will be its first.
Update this section once that plan is implemented.

## Related ADR

`agent/adr/fetcher/list-query-objects-layer.md`
