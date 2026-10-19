---
description: app_fetcher's app/queries/ (per-resource list/detail/history query objects, shared concern queries, plus Appliers:: and Options:: subfolders) and app/serializers/ layers — shared filter/sort/pagination mechanics, aggregate projection ownership, timestamp/type boundaries, and pure Public/V1/concern response shaping.
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

The `app/serializers/` half of this layer is broader than the
list/detail pairs below. Any action whose response body requires
non-trivial shaping — per-item math, omission rules, nested
current/history/change structures — gets a serializer even when there is
no matching `<Resource>ListQuery`/`<Resource>DetailQuery`, and even
when only one action calls it. The serializer still only maps
already-resolved data; it never becomes a second query layer.

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
belongs here, as a concern query (`InventoryValueQuery`), not as a third
per-resource list/detail class. The same test applies: a single
caller with a one-off aggregate should stay inline or in that resource's
own query object.

The serializer half is different: response shaping is worth extracting
for a single action when the controller would otherwise own branching
per-item math, omission rules, or nested envelope construction. Do not
extract a serializer for a plain one-key render (`{ message: "..." }`)
or a bare list of already-shaped records.

## Structure

- **`app/queries/<resource>_list_query.rb`** (flat root, e.g.
  `ItemListQuery`, `InventoryListQuery`) — one class per resource/endpoint,
  not one generic class across resources. Named `<Resource>ListQuery`,
  never a bare `<Resource>Query` — the name should signal that the class
  may carry resource-specific business logic (aggregates, enrichment
  lookups) that won't generalize to other resources, not imply a reusable
  abstraction that isn't there. Its result struct is named by contents,
  not transport shape: `<Resource>ListQuery::<ContentName>` (e.g.
  `InventoryListQuery::InventorySummaries` for a page of inventory
  summaries, `ItemListQuery::ItemCatalog` for a catalog of items), never
  `Page` or `Listing`.
- **`app/queries/<resource>_detail_query.rb`** (flat root, e.g.
  `InventoryDetailQuery`) — the sibling shape for a *detail* endpoint:
  one resource looked up by an identifier (e.g. `steam_id`), not a page
  of many. Named `<Resource>DetailQuery`, the same naming logic as
  `<Resource>ListQuery` above. Its result struct is named by contents
  (`InventoryDetailQuery::InventoryDetails`), with an embedded
  paginated/sorted sub-collection as its own content-named struct (e.g.
  `InventoryDetailQuery::InventoryItems`), never `Detail` or `Page`. May
  still compose `Appliers::Pagination`/`Appliers::SortApplier`/`Options::*`
  for that sub-collection, on top of whatever bespoke scalar aggregates the
  resource needs.
- **`app/queries/<resource>_history_query.rb`** (flat root, e.g.
  `ItemPriceHistoryQuery`, `InventoryValueHistoryQuery`) — a
  time-series read for one resource: resolves the `Options::DateRange`
  param, applies the range's cutoff to the queried log model, and
  returns a content-named result struct of points plus the resolved
  `range` (e.g. `ItemPriceHistoryQuery::ItemPriceHistory`,
  `InventoryValueQuery::InventoryValue`), never a bare `Page`. Named
  `<Resource>HistoryQuery` because it is neither a filtered list of
  resources (`ListQuery`) nor a single-resource detail (`DetailQuery`).
  It never reads a response-payload cache; the controller decides whether
  to use a cache at all.
- **`app/queries/<concern>_query.rb`** (flat root, e.g.
  `InventoryValueQuery`) — a shared, read-only calculation over
  already-persisted data whose result is consumed by more than one query
  object, controller action, or cross-Scenario service, rather than
  shaping one endpoint's response. Named for the concern with a `Query`
  suffix when the concern is a calculation, not as
  `<Resource>ListQuery`/`<Resource>DetailQuery`, because it is not an
  endpoint query. Its primary entry point is `.call(...)`; lower-level named
  helpers (`snapshot_for`, `history`, `delta_for`, `with_aggregates`) are
  allowed only when they serve genuinely distinct callers. It returns
  `T::Struct`s (never a response hash), names them for their contents
  (`ValueSnapshot`, `ValueDelta`, `ValueHistory`, `InventoryValue`), and
  owns the SQL aggregate expressions shared by the single-resource and
  bulk/list paths. It exposes a `with_aggregates(scope)` projection API
  instead of public aggregate column constants. It may be called by a
  `<Resource>ListQuery`/`<Resource>DetailQuery`, an `Api::V1::`
  controller action, and a cross-Scenario service; it never calls a
  controller or a service, never writes, and never caches a response
  payload.
- **`app/queries/rarity_breakdown_query.rb`** (flat root) — a shared concern
  query when the same enrichment (per-inventory rarity counts) is needed
  by more than one endpoint query. Its `.call(user_inventory_ids)` returns
  typed counts, never a response hash, and it follows the same
  no-write/no-response-cache rules as any other concern query.
- **`app/queries/appliers/`** → `Appliers::` namespace (Zeitwerk:
  subfolder of an autoloaded `app/` root becomes a namespace, same rule
  already used by `app/serializers/admin/` → `Admin::`). Fully
  resource-agnostic classes — never reference a specific model or a
  specific `Options::*` member by name.
- **`app/queries/options/`** → `Options::` namespace. One `T::Enum`
  subclass per resource per concern (e.g. `Options::ItemSortOption`,
  `Options::ItemFilterOption`), named `<Resource><Concern>` —
  `SortOption` / `FilterOption`.
- **`app/serializers/<resource>_list_serializer.rb`** (flat root,
  e.g. `ItemListSerializer`, `InventoryListSerializer`) — one per
  resource/endpoint, pure function style, same flat-root convention as
  `app/services/`/`app/caching/`; its input is the matching
  `<Resource>ListQuery` result struct.
- **`app/serializers/<resource>_detail_serializer.rb`** (flat root, e.g.
  `InventoryDetailSerializer`) — `<Resource>DetailQuery`'s serializer
  counterpart; same pure-function rule as `<Resource>ListSerializer`.
- **`app/serializers/<resource>_history_serializer.rb`** (flat root,
  e.g. `ItemPriceHistorySerializer`) — `<Resource>HistoryQuery`'s pure
  point-list serializer, used when the endpoint returns a bare array
  rather than an envelope. It maps the query result's points to response
  hashes and nothing else.
- **`app/serializers/<concern>_serializer.rb`** (flat root, e.g.
  `InventoryValueSerializer`) — shapes a shared concern query's
  result struct (`InventoryValueQuery::InventoryValue`) for an action that has no
  `<Resource>ListQuery`/`<Resource>DetailQuery` of its own. The name
  follows the concern query it serializes, not a nonexistent endpoint
  query.
- **`app/serializers/<resource>_<action>_serializer.rb`** (flat root,
  e.g. `ItemPriceDynamicsSerializer`) — action-specific response shaping
  for an action assembled from already-fetched data plus scalar counts,
  when no list/detail/concern-query class fits. The controller still
  owns every read, cache call, and enqueue; the serializer owns only the
  final hash.
- **`app/serializers/<resource>_serializer.rb`** (flat root, e.g.
  `InventorySerializer`) — the same pure shaping for a resource whose
  only endpoint renders one simple envelope around an already-fetched
  collection (`{ items_count, items }`). Use it instead of leaving that
  envelope inline in the controller; do not create a list/detail
  query class solely to justify it.
- **`app/serializers/<shared_concept>_serializer.rb`** (flat root, e.g.
  `ItemMetadataSerializer`, `RarityBreakdownSerializer`) — a pure,
  reusable response fragment shared by more than one endpoint serializer
  (public item metadata; 7-tier rarity breakdown). It takes already-
  resolved values (an `Item`, a typed counts hash) and returns a hash or
  array; it performs no I/O and owns no query.
- **`app/serializers/<calculation>.rb`** (flat root, e.g.
  `PriceChangePercent`) — a pure calculation shared by several
  serializers when the same derived value would otherwise be duplicated
  (e.g. `change_24h_percent`). It is a function-style class, not a
  resource serializer, and must be free of I/O.

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
- **`Appliers::SortApplier.call(scope, params, enum_class:, default:,
  param_name: "sort")`** → the sorted `ActiveRecord::Relation`. Reads
  `params[param_name]`; absence resolves to `default`, a present
  unrecognized value raises `Api::Public::UnsupportedParamError`. The
  resolved enum member's own `#apply(scope)` performs the ordering —
  this applier only resolves, validates, and dispatches, so `enum_class`
  must be an `Options::*` sort enum (or another enum whose members
  implement `#apply(scope)`), never a plain value enum such as
  `Options::DateRange`.
- **Period params (`Options::DateRange`)** are resolved by a
  per-call `Options::DateRange::Param`, not by `Appliers::SortApplier`.
  `Options::DateRange < T::Enum` owns the tag vocabulary
  (`24h`/`7d`/`30d`/`1y`/`all`) and the cutoff conversion (`#duration`,
  `#since`, `#since_date`; `AllTime` has no cutoff).
  `Options::DateRange::Param.new(allowed_ranges:, default:,
  error_class:).parse(raw)` returns a `DateRange` member or raises
  `error_class` with `"Unsupported period: <raw>"`; blank input
  resolves to `default`, and a recognized-but-disallowed member (e.g.
  `24h` for daily inventory values) is an error, never a silent
  fallback. Each query object constructs its own `Param` inside `.call`
  — there is no shared param constant. The caller chooses the error
  class: `InventoryDetailQuery` uses
  `Api::Public::UnsupportedParamError`; V1 query objects use
  `Api::V1::UnsupportedParamError`, which `Api::V1::BaseController`
  renders as `:bad_request` (no inline render branch in the action).
- **Concern aggregate projection**: a concern query that owns shared SQL
  aggregates exposes `with_aggregates(scope)` → `ActiveRecord::Relation`,
  appending its aliased aggregate columns to an already grouped scope, and
  a named `snapshot_from(record)`/equivalent reader for those aliases. The
  SQL expressions/aliases stay private constants; endpoint queries never
  concatenate or destructure them. Aliases needed by an
  `Options::*SortOption` must remain in the `SELECT` list.
- **`Appliers::FilterApplier.call(scope, params, enum_class:)`** →
  `ActiveRecord::Relation`, by reducing `enum_class.values` over the
  scope.
- **`<Resource>ListQuery.call(params)`** → a `T::Struct` (e.g.
  `ItemListQuery::ItemCatalog`, `InventoryListQuery::InventorySummaries`)
  carrying everything a response needs — items/inventories, pagination,
  counts, any resource-specific extras. Never a `Result`-style success/error
  wrapper: the one failure mode (invalid `sort`) is raised by
  `Appliers::SortApplier`, not returned, so `.call` either returns a valid
  struct or doesn't return at all.
- **`<Concern>Query.call(...)`** → a typed `T::Struct`/typed count map for
  the concern's primary operation (e.g. `InventoryValueQuery.call(steam_id,
  range)` → `InventoryValue`, `RarityBreakdownQuery.call(ids)` → per-inventory
  counts). As with endpoint queries, `.call` raises/returns, never wraps a
  success/error result. Named lower-level helpers are secondary.
- **All query result structs** are named by contents, not transport shape:
  `<Query>::<ContentName>` (e.g. `InventoryDetails`, `InventoryItems`,
  `ItemPriceHistory`, `ValueSnapshot`, `ValueDelta`, `ValueHistory`,
  `InventoryValue`). Never `Page`, `Listing`, `Detail`, `Change`, `Snapshot`,
  or `Valuation` as the result-struct name. Compose shared concern types
  instead of copying their fields into an endpoint result.
- **Query-struct timestamps** are `Time`/`Date` values normalized to UTC,
  never pre-formatted strings. Serializers own `.iso8601`; preserve the
  endpoint's existing date-only vs timestamp contract (e.g. catalog
  `change_basis_at` is a date, detail/V1 `change_basis_at` is a timestamp).
- **`<Resource>DetailQuery.call(identifier, params)`** → a `T::Struct`
  carrying everything a detail response needs — the looked-up resource's
  own fields, any bespoke aggregates, and (if applicable) one embedded
  paginated/sorted sub-collection's items plus its own pagination. Never
  a `Result`-style wrapper, same as `<Resource>ListQuery` — its one
  extra failure mode (the identifier doesn't resolve to a record) is
  raised as `ActiveRecord::RecordNotFound` via a bang finder (`Model.
  find_by!(...)`), never returned as `nil`; see
  `public-api-controllers.md`'s Error Handling shape (4) for how the
  controller's base class catches it.
- **`<Resource>ListSerializer.call(<query-result-struct>)`** →
  `T::Hash[Symbol, T.untyped]`. Pure function — no argument may be
  anything that requires a database or cache read; all data must already
  be resolved by the time this is called.
- **`<Resource>DetailSerializer.call(<query-result-struct>)`** →
  `T::Hash[Symbol, T.untyped]`. Same pure-function rule as
  `<Resource>ListSerializer`.
- **`<Resource>HistorySerializer.call(<history-query-result>)`** →
  `T::Array[T::Hash[Symbol, T.untyped]]` when the endpoint's contract is a
  bare point array (e.g. `ItemPriceHistorySerializer`). Same zero-I/O rule.
- **`<Concern>Serializer.call(<concern-query-result>)`** and
  **`<Resource><Action>Serializer.call(<already-resolved-inputs>)`** →
  `T::Hash[Symbol, T.untyped]`. Same pure-function rule. Positional/keyword
  arguments are chosen per serializer; every argument must already be
  fully resolved (an `InventoryValueQuery::InventoryValue`, a
  `T::Hash[String, Item]` plus a scalar count, etc.). Never pass
  `ActionController::Parameters`, a relation, a model class, or a cache
  handle.
- **Shared response fragments**:
  `ItemMetadataSerializer.call(item)` → the public item-metadata hash;
  `RarityBreakdownSerializer.call(counts)` → the 7-tier breakdown array;
  `PriceChangePercent.call(current_cents:, change_cents:)` → a rounded
  percent (`0.0` when the base is zero). These are pure functions reusable
  across endpoint serializers, never a second query layer.
- **Shared enrichment queries**:
  `RarityBreakdownQuery.call(user_inventory_ids)` → typed per-inventory tier
  counts, used by both list and detail queries so the counting semantics
  cannot drift. A single-inventory caller passes `[id]` and fetches its
  entry, rather than growing a second public entry point.

## Responsibilities

- `Options::*` own per-value behavior for one named field (ordering
  logic, a `where` clause) — not param parsing, not validation of
  *whether* a value was supplied.
- `Appliers::*` own generic resolution/clamping/dispatch mechanics —
  never resource-specific logic, never which fields exist for a given
  resource.
- `Options::DateRange` owns cutoff conversion and the range vocabulary;
  the query object that owns the endpoint applies that cutoff to its
  model (`where(log_date: range.since_date..)` or
  `where(created_at: range.since..)`). Models do not declare supported
  ranges, period constants, or `for_period` scopes.
- `<Resource>ListQuery` owns every database/cache read needed to
  answer "what does this page need" — including resource-specific
  aggregates and enrichment lookups (e.g. `Item`'s price-change counts,
  trend data) — and nothing about HTTP or response-level caching.
- `<Resource>DetailQuery` owns the same kind of work as
  `<Resource>ListQuery`, scoped to one resource instead of a page: the
  lookup by identifier (raising on a miss, never returning `nil`), any
  bespoke aggregates, and composing `Appliers::*`/`Options::*` for its
  own embedded sub-collection, if it has one.
- `<Resource>ListSerializer` owns response-shape mapping only.
- `<Resource>DetailSerializer` owns response-shape mapping only, same as
  `<Resource>ListSerializer`.
- `<Resource>HistorySerializer` owns point-list response shaping only for a
  `<Resource>HistoryQuery` whose endpoint returns a bare array.
- `<Concern>Serializer`/`<Resource><Action>Serializer` own response-shape
  mapping only for actions outside the list/detail pair. The controller
  still owns fetching the data they receive (including cache reads, DB
  counts, and worker enqueues).
- A shared concern query owns its calculation and SQL projection: expose
  aggregate columns only through `with_aggregates(scope)` and typed readers,
  never as public constants for endpoint queries to concatenate.
- Shared serializers/helpers own one reusable fragment or calculation
  (`ItemMetadataSerializer`, `RarityBreakdownSerializer`,
  `PriceChangePercent`); endpoint serializers compose them instead of
  re-implementing the same math.
- `RarityBreakdownQuery` owns per-inventory tier counting for both list and
  detail queries, preserving `RarityTier` semantics.
- The controller owns: calling the query object, calling the serializer,
  `ItemListCache`-style response caching, and conditional-GET
  (`stale?`/`ETag`) — none of that belongs in any class above.

## Dependencies

One-directional: `<Resource>ListQuery` may depend on `Appliers::*`,
`Options::*`, model scopes, existing `app/caching/` *data* caches
(e.g. `ItemTrendCache` — bulk read-through caches for already-known
lookups, per `caching.md`), and shared read-only concern queries in this
same layer (e.g. `InventoryValueQuery`) and shared enrichment queries
(e.g. `RarityBreakdownQuery`), but never on a response-payload cache like
`ItemListCache` or anything HTTP-related.
`<Resource>ListSerializer` depends only on its input struct and the shared
pure serializers/helpers it composes (`ItemMetadataSerializer`,
`PriceChangePercent`, `RarityBreakdownSerializer`); the same holds for
`<Concern>Serializer`/`<Resource><Action>Serializer`, which may reference
the concern-query struct types they serialize but must perform no reads. `Appliers::*` depend on nothing resource-specific — not even indirectly,
by referencing a concrete `Options::*` class by name inside an
`Appliers::*` file. `Options::*` depend only on the model scopes they
call from `#apply`. The identical dependency rules apply to
`<Resource>DetailQuery`/`<Resource>DetailSerializer` — the shape of what
each class may depend on doesn't change between the list and detail
cases, only how many of the resource it answers for.

A concern query (`InventoryValueQuery`) may depend on `Appliers::*`/
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
- A period param must resolve through `Options::DateRange::Param#parse`
  with an explicit `allowed_ranges:`/`default:`/`error_class:`; never
  route it through `Appliers::SortApplier`, and never give a model a
  `SUPPORTED_PERIODS` constant or a `for_period` scope.
- `<Resource>ListQuery.call` must never reference an
  `app/caching/` response-payload cache (e.g. `ItemListCache`) or
  `ActionController`/HTTP types beyond accepting `ActionController::Parameters`
  as its input.
- `<Resource>ListSerializer` must perform zero I/O — no `ActiveRecord`
  query, no `Rails.cache` call, inside its `.call`.
- `<Resource>DetailQuery.call` must look up its resource with a bang
  finder (`Model.find_by!(...)`) and let a miss raise
  `ActiveRecord::RecordNotFound` — never check for `nil` and return early
  or build a `Result`-shaped failure value.
- `<Resource>DetailSerializer`/`<Resource>HistorySerializer` must perform
  zero I/O, same rule as `<Resource>ListSerializer`.
- `<Concern>Serializer`/`<Resource><Action>Serializer` must perform zero
  I/O too: no `ActiveRecord`, `Rails.cache`, service, or worker call
  inside `.call`. Any count, cache read, or enqueue stays in the calling
  controller.
- A shared concern query (`InventoryValueQuery`, `RarityBreakdownQuery`) must
  return typed values — `T::Struct` for composite results, typed hashes for
  lookups/counts — never a response hash; response shaping stays in the
  matching serializer. It must perform no writes and must not call a
  response-payload cache. Its primary entry point is `.call(...)`; named
  helpers are secondary and must not replace `.call` as the canonical
  operation.
- Query result structs must be named by contents
  (`InventoryDetails`, `InventoryItems`, `ItemPriceHistory`,
  `ValueSnapshot`, `ValueDelta`, `ValueHistory`, `InventoryValue`), never
  `Page`, `Listing`, `Detail`, `Change`, `Snapshot`, or `Valuation`.
- Query result structs must store `Time`/`Date` values normalized to UTC,
  never pre-formatted strings; only serializers call `.iso8601`.
- A concern query that owns shared aggregate SQL must expose it only through
  `with_aggregates(scope)` + a typed reader; aggregate expressions/aliases
  stay private.
- Shared serializers/helpers (`ItemMetadataSerializer`,
  `RarityBreakdownSerializer`, `PriceChangePercent`) must perform zero I/O,
  same as endpoint serializers.

### SHOULD

- Name the per-resource query class `<Resource>ListQuery`, not
  `<Resource>Query` — see Structure.
- Keep `<Resource>ListQuery.call`'s return type a plain `T::Struct`,
  not a `Result`/outcome wrapper — see the ADR's "Alternatives
  Considered" for why that was tried and reverted.
- Name a detail endpoint's query/serializer pair `<Resource>DetailQuery`/
  `<Resource>DetailSerializer` — the sibling convention to
  `<Resource>ListQuery`/`<Resource>ListSerializer` — and keep
  `<Resource>DetailQuery.call`'s return type a plain `T::Struct` too, for
  the same reason.

### MUST NOT

- Don't enumerate a filter's *allowed values* as `Options::*` enum
  members — only field *names* belong there. Open string-set param
  values (`category`, `rarity`) stay unvalidated inside the relevant
  enum value's own `#apply`, per `public-api-controllers.md`.
- Don't generalize `<Resource>ListQuery` into one config-driven class
  shared across resources before a second resource's concrete needs
  confirm the right shared shape (see ADR, "wait for a third example").
- Don't put cache-read/write or `stale?`/`ETag` logic inside any class in
  this layer — that stays in the controller.
- Don't expose a concern query's aggregate column constants for endpoint
  queries to concatenate or destructure positionally; use
  `with_aggregates(scope)` and a named reader.
- Don't format timestamps in a query object; keep `Time`/`Date` in the
  result struct and format in the serializer.
- Don't duplicate item metadata, `change_24h_percent`, or rarity-breakdown
  shaping across serializers; use the shared serializers/helpers.
- Don't name a query result struct after its transport shape
  (`Page`/`Listing`/`Detail`/`Change`/`Snapshot`/`Valuation`).

## Error Handling

This layer produces two failure modes, neither of which it catches
itself — both propagate to the controller's base class:

1. An unrecognized closed-enum value, raised as `Api::Public::
   UnsupportedParamError` from `Appliers::SortApplier` for sort params, or
   by `Options::DateRange::Param#parse` for a period param (the query
   object passes that error class in). (In principle an `Options::*`
   value's own `#apply` may raise it too if a future resource needs a
   closed-enum-shaped filter — the mechanism is the same.)
2. For a `<Resource>DetailQuery`, an identifier that doesn't resolve to a
   record, raised as `ActiveRecord::RecordNotFound` by its bang finder
   (never returned as `nil` — see Rules).

An `Api::V1::` action that validates its own closed-enum param raises
`Api::V1::UnsupportedParamError` outside this layer, rendered by
`Api::V1::BaseController` — see `internal-api-controllers.md`'s Error
Handling.

See `public-api-controllers.md`'s Error Handling section for shapes (2)
and (4) respectively — the exceptions' definitions/sources and the
`rescue_from` pair that catches each — not restated here.

## Interaction With Other Layers

```text
Api::Public::<X>Controller#index
    ↓ ItemListCache.read(params)  — cache check, controller's job
    ↓ (on miss)
<Resource>ListQuery.call(params)
    ↓ Appliers::SortApplier.call(scope, params, ...) → relation (or raises)
    ↓ Appliers::FilterApplier.call(...) → Options::<Resource>FilterOption.values.reduce(...)
    ↓ Appliers::Pagination#apply(scope) → relation limited/offset
    ↓ model scopes, app/caching/ data caches (e.g. ItemTrendCache)
    → <Resource>ListQuery::<ContentName> (T::Struct)
<Resource>ListSerializer.call(result) → response hash
    ↓ ItemListCache.write(params, payload)  — controller's job
    ↓ stale?/render  — controller's job
```

A concern query is a read-only sub-step, not an endpoint: a
`<Resource>ListQuery`/`<Resource>DetailQuery` or an `Api::V1::` read
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
    ↓ Options::DateRange::Param#parse(...)  — period param, or raises
    ↓ Appliers::SortApplier.call(...) / Appliers::Pagination#apply(...)  — for one embedded sub-collection, if any
    ↓ model scopes, app/caching/ data caches
    → <Resource>DetailQuery::<ContentName> (T::Struct)
<Resource>DetailSerializer.call(result) → response hash
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
  (no obligation to build a throwaway test-only enum). `SortApplier`
  specs assert the relation's ordering (and the raised error), not a
  resolved enum value.
- `Options::DateRange` is a unit spec under `spec/queries/options/`:
  assert each member's `#duration`/`#since`/`#since_date`, and
  `Param#parse`'s blank-default, allowed, disallowed, and unknown cases
  with the exact error class/message. Range cutoffs are tested on the
  owning query object (`spec/queries/`), asserting inclusion/exclusion
  and that `AllTime` applies no cutoff — never on a model scope.
- `<Resource>ListQuery` specs hit the database for real (it's a query
  object) but must never stub or reference `app/caching/`'s
  response-payload cache — that cache does not exist from this class's
  point of view.
- `<Resource>ListSerializer` specs must not use `create(:record)` —
  use an unsaved/in-memory instance (e.g. `Item.new(...)`) to keep the
  spec provably free of database access, matching the class's own
  zero-I/O rule.
- `<Resource>DetailQuery` specs follow the same DB-for-real,
  no-response-payload-cache rules as `<Resource>ListQuery`, plus one
  scenario `<Resource>ListQuery` doesn't need: an unknown identifier
  raising `ActiveRecord::RecordNotFound`.
- `<Resource>DetailSerializer` specs follow the same zero-I/O,
  unsaved-instance rule as `<Resource>ListSerializer`.
- `<Resource>HistorySerializer` specs use an in-memory history result and
  assert the bare point-array contract when that is the endpoint shape.
- `<Concern>Serializer`/`<Resource><Action>Serializer` specs are unit
  specs with in-memory inputs — real `T::Struct` instances, unsaved
  `Item.new(...)` records, plain hashes/counts — never `create`. Cover
  the omission rules and math the serializer owns (nil values, zero
  denominators, empty input). Request specs still cover the same cases
  end-to-end, but must not be the only place a serializer edge case is
  proven.
- A shared concern query (`InventoryValueQuery`, `RarityBreakdownQuery`) is a
  unit spec under `spec/queries/`, hitting the database for real (like the
  resource queries) and never referring to a response-payload cache. Cover
  the single-resource and bulk paths from the same examples where the shared
  aggregate is what guarantees they cannot drift; assert the returned typed
  values, not raw rows.
- Query specs assert `Time`/`Date` values in result structs, not formatted
  strings; serializer specs assert the exact `.iso8601` output, including the
  endpoint's date-only vs timestamp contract.
- Shared serializers/helpers (`ItemMetadataSerializer`,
  `RarityBreakdownSerializer`, `PriceChangePercent`) are unit specs with
  in-memory inputs, same zero-I/O rule as other serializers.
- Request specs remain the contract lock for JSON keys/values; a query or
  serializer refactor must not change them beyond class/stub renames.

## Canonical Implementations

- `ItemListQuery`/`ItemListSerializer`/`Options::ItemSortOption`/
  `Options::ItemFilterOption`/`Appliers::Pagination`/
  `Appliers::SortApplier`/`Appliers::FilterApplier`
  (`agent/plans/item-catalog-query-refactor.md`).
- `InventoryListQuery::InventorySummaries`/`InventoryListSerializer` and
  `InventoryDetailQuery::InventoryDetails` + `InventoryItems`/
  `InventoryDetailSerializer`
  (`agent/plans/public-inventory-endpoints.md`,
  `agent/plans/fix-query-param-applier-consistency.md`).
- `Options::DateRange` + `Options::DateRange::Param`, with cutoff
  applied by the owning query object
  (`agent/plans/fetcher-api-cleanup-and-date-range.md`).
- `InventoryValueHistoryQuery`/`ItemPriceHistoryQuery` — the
  `<Resource>HistoryQuery` shape, returning content-named structs of points
  (`InventoryValue`, `ItemPriceHistory`)
  (`agent/plans/fetcher-api-cleanup-and-date-range.md`).
- `InventoryValueQuery` — the shared concern query with
  `ValueSnapshot`/`ValueDelta`/`ValueHistory`/`InventoryValue` and
  `with_aggregates(scope)`
  (`agent/plans/inventory-valuation-consistency.md`).
- `RarityBreakdownQuery` — the shared rarity-count concern query used by
  `InventoryListQuery`/`InventoryDetailQuery`.
- `ItemMetadataSerializer`, `PriceChangePercent`,
  `RarityBreakdownSerializer` — shared pure response fragments/calculations
  composed by endpoint serializers.
- `ItemPriceHistorySerializer` — the history query's pure point serializer.
- `InventorySerializer` — the `<Resource>Serializer` envelope case
  (`agent/plans/fetcher-api-cleanup-and-date-range.md`).
- `InventoryValueSerializer` — the `<Concern>Serializer` case,
  shaping `InventoryValueQuery::InventoryValue` for `Api::V1::InventoryValuesController`
  (`agent/plans/fetcher-controller-layer-polish.md`).
- `ItemPriceDynamicsSerializer` — the `<Resource><Action>Serializer`
  case, shaping `ItemPriceDynamics`'s already-fetched item hash plus
  `pending_count` for `Api::V1::ItemPricesController#dynamics`
  (`agent/plans/fetcher-controller-layer-polish.md`).

## Related ADR

`agent/adr/fetcher/list-query-objects-layer.md`
