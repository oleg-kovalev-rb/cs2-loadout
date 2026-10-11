---
description: app_fetcher's app/queries/ (per-resource query objects, plus Appliers:: and Options:: subfolders) and app/serializers/ layers — shared filter/sort/pagination mechanics and response-shaping for Api::Public:: list endpoints.
---

# List Query Objects (`app/queries/`, `app/serializers/`)

See `.claude/adr/fetcher/list-query-objects-layer.md` for why this is a
new layer rather than an extension of `app/services/`, and why the
per-resource query class is deliberately not generalized into one
config-driven facade yet. This file covers how code in these layers is
written, once that decision is taken as given.

## Purpose

Give every `Api::Public::` list endpoint (filter + sort + pagination +
response shaping over a paginated resource) a consistent, reusable place
for each piece of that mechanics, instead of writing it inline in the
controller action. What belongs here: resolving/validating closed-enum
query params, applying named filters to a scope, clamping pagination,
fetching the data a response needs, and shaping that data into a
response hash. What does not: anything with a notion of caller identity
(that's `Api::V1::`'s job, if it ever needs this pattern), persisting
data, or calling `Steam::Client` — this layer only ever reads
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

## Structure

- **`app/queries/<resource>_catalog_query.rb`** (flat root, e.g.
  `ItemCatalogQuery`) — one class per resource/endpoint, not one generic
  class across resources. Named `<Resource>CatalogQuery`, never a bare
  `<Resource>Query` — the name should signal that the class may carry
  resource-specific business logic (aggregates, enrichment lookups) that
  won't generalize to other resources, not imply a reusable abstraction
  that isn't there.
- **`app/queries/appliers/`** → `Appliers::` namespace (Zeitwerk:
  subfolder of an autoloaded `app/` root becomes a namespace, same rule
  already used by `app/parsers/steam/` → `Steam::`). Fully
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
  raw_per_page)` clamps silently (see `public-api-controllers.md`'s
  bounded-numeric rule — never raises/rejects). Instance methods
  `#page`, `#per_page`, `#offset`, `#total_pages(total_count)`.
- **`Appliers::SortApplier.call(raw_value, enum_class:, default:,
  param_name: "sort")`** → a resolved `T::Enum` member (never nilable).
  Raises `Api::Public::UnsupportedParamError` on an unrecognized,
  present value — absence always resolves to `default`, never an error.
- **`Appliers::FilterApplier.call(scope, params, enum_class:)`** →
  `ActiveRecord::Relation`, by reducing `enum_class.values` over the
  scope.
- **`<Resource>CatalogQuery.call(params)`** → a `T::Struct` (e.g.
  `ItemCatalogQuery::Page`) carrying everything a response needs — items,
  pagination, counts, any resource-specific extras. Never a `Result`-style
  success/error wrapper: the one failure mode (invalid `sort`) is raised
  by `Appliers::SortApplier`, not returned, so `.call` either returns a
  valid struct or doesn't return at all.
- **`<Resource>CatalogSerializer.call(<query-result-struct>)`** →
  `T::Hash[Symbol, T.untyped]`. Pure function — no argument may be
  anything that requires a database or cache read; all data must already
  be resolved by the time this is called.

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
- `<Resource>CatalogSerializer` owns response-shape mapping only.
- The controller owns: calling the query object, calling the serializer,
  `ItemCatalogCache`-style response caching, and conditional-GET
  (`stale?`/`ETag`) — none of that belongs in any class above.

## Dependencies

One-directional: `<Resource>CatalogQuery` may depend on `Appliers::*`,
`Options::*`, model scopes, and existing `app/caching/` *data* caches
(e.g. `ItemTrendCache` — bulk read-through caches for already-known
lookups, per `caching.md`), but never on a response-payload cache like
`ItemCatalogCache` or anything HTTP-related. `<Resource>CatalogSerializer`
depends on nothing but its input struct. `Appliers::*` depend on nothing
resource-specific — not even indirectly, by referencing a concrete
`Options::*` class by name inside an `Appliers::*` file. `Options::*`
depend only on the model scopes they call from `#apply`.

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

### SHOULD

- Name the per-resource query class `<Resource>CatalogQuery`, not
  `<Resource>Query` — see Structure.
- Keep `<Resource>CatalogQuery.call`'s return type a plain `T::Struct`,
  not a `Result`/outcome wrapper — see the ADR's "Alternatives
  Considered" for why that was tried and reverted.

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

The only failure mode this layer produces is an unrecognized closed-enum
value, raised as `Api::Public::UnsupportedParamError` from
`Appliers::SortApplier` (or, in principle, from an `Options::*` value's
own `#apply` if a future resource ever needs a closed-enum-shaped
filter — the mechanism is the same). This layer never catches that
exception itself; it propagates to the controller's base class. See
`public-api-controllers.md`'s Error Handling section for the exception's
definition, location (`lib/api/public/`), and the `rescue_from` that
catches it — not restated here.

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

## Canonical Implementations

None yet — `ItemCatalogQuery`/`ItemCatalogSerializer`/
`Options::ItemSortOption`/`Options::ItemFilterField`/`Appliers::Pagination`/
`Appliers::SortApplier`/`Appliers::FilterApplier`
(`.claude/plans/item-catalog-query-refactor.md`) are this layer's first
members. Update this section once that plan is implemented.

## Related ADR

`.claude/adr/fetcher/list-query-objects-layer.md`
