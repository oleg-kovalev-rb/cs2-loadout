# A `queries`/`serializers` Layer for List-Endpoint Query Objects, Shared Across `Api::Public::` Controllers

## Status

Proposed

## Context

`Api::Public::ItemsController#catalog` (`agent/plans/public-items-catalog-endpoint.md`)
shipped with every piece of filter/sort/pagination/serialization logic
written directly in the controller action — `normalized_filters`,
`clamp_param`, `compute_page`, `item_json`. This was deliberate: the
author committed it in that shape specifically to have working code to
refactor against, not as a considered final design. `architecture-layers.md`'s
own "When to Use" carve-out ("a plain AR query with no parsing/building
involved") was cited at the time to justify this, on the stated reasoning
that the feature had "exactly one caller."

That reasoning no longer holds. At least two more `Api::Public::` list
endpoints (filter + sort + pagination + serialization, over different
models) are expected in the near term, with this controller to serve as
the reference implementation they copy. An admin panel may add further
callers later, with unknown shape — not planned concretely enough to
design for yet. The question is where filter/sort/pagination/serialization
logic belongs once more than one controller needs the same mechanics.

No existing layer's documented criterion fits this reuse axis.
`app/services/` (`agent/adr/fetcher/cross-scenario-service-layer.md`)
is explicitly scoped to logic "needed identically by two or more
Scenarios" — concretely, a controller and a worker. Every list endpoint
in question here is Scenario 1 only; the reuse is *across controllers
within one Scenario*, a dimension `app/services/` was never designed to
cover. Reusing it by analogy would misrepresent what that ADR actually
decided.

A closely related, narrower pattern already exists, undocumented:
`app_fetcher/app/models/price_period.rb` (`PricePeriod < T::Enum`, a
`case self` method with an `else T.absurd(self)` exhaustiveness guard),
used inline by `ItemPricesController#history` and
`InventoryValuesController` to validate a closed-enum query param. It
demonstrates the right *mechanism* (a `T::Enum` where each value carries
its own behavior, checked exhaustively by Sorbet) but has never been
generalized beyond a single param on two controllers, and covers only
"resolve a closed-enum param," not filtering, pagination, or response
serialization.

This project has twice declined to extract a shared abstraction before a
third real example existed (`agent/adr/fetcher/public-api-namespace.md`'s
duplicated base-controller `rescue_from`; the deferred base-service
`Result` class) specifically to avoid guessing the right shape from too
few data points. This decision knowingly proceeds anyway, for a narrower
reason: the *shapes* being shared here — bounded-numeric / open-string-set
/ closed-enum / boolean query params — are not being guessed at all;
they're already fully enumerated in `public-api-controllers.md`,
independent of which resource an endpoint serves. What stays deliberately
*unshared* (see Decision) is exactly the part that would require guessing
from one example: the per-resource orchestrating class.

## Decision

Introduce two new top-level `app/` layers in `app_fetcher`:

- **`app/queries/`** — per-resource query objects (`ItemCatalogQuery`
  today), plus two subfolders of resource-agnostic mechanics:
  `app/queries/appliers/` (→ `Appliers::` namespace) and
  `app/queries/options/` (→ `Options::` namespace).
- **`app/serializers/`** — pure, I/O-free response-shaping functions.

**`Options::*`** (`app/queries/options/`) are `T::Enum` subclasses, one
per resource per concern (`Options::ItemSortOption`,
`Options::ItemFilterField`). Each enum value implements its own behavior
via `#apply(scope)` / `#apply(scope, params)`, dispatched with `case
self` and closed with `T.absurd(self)` so Sorbet statically guarantees
every value is handled — the same mechanism `PricePeriod` already uses,
generalized to filtering and sorting. An `Options::*` enum closes over
the **names** of filterable/sortable fields for a resource (a genuinely
closed set — "Item can be filtered by category, rarity, stattrak,
search"), never over the **values** those fields accept. Open-string-set
filter values (`category`, `rarity`) stay unvalidated, per
`public-api-controllers.md`'s existing rule — this decision does not
change that, it operates on an orthogonal axis.

**`Appliers::*`** (`app/queries/appliers/`) are the genuinely
resource-agnostic mechanism — the part this decision guarantees is
reused verbatim by every future `Api::Public::` list endpoint, because
it never references a specific model or enum member:

- `Appliers::Pagination` — a plain value object (not `T::Enum`/Strategy;
  clamping a number into a range isn't a choice between named
  behaviors). Owns the shared defaults/bounds.
- `Appliers::SortApplier.call(raw_value, enum_class:, default:,
  param_name:)` → a resolved `T::Enum` member, never nilable. Raises
  `Api::Public::UnsupportedParamError` itself on an unrecognized value —
  callers never branch on a nil/Result return.
- `Appliers::FilterApplier.call(scope, params, enum_class:)` → reduces
  `enum_class.values` over the scope, each value applying itself.

**`<Resource>CatalogQuery`** (flat, `app/queries/` root — e.g.
`ItemCatalogQuery`) is one class per resource, not one generic class
parameterized across resources. It composes the `Options::*`/`Appliers::*`
pieces above plus whatever is genuinely specific to that resource (for
`Item`: price-change aggregates, 7-day trend lookup, catalog freshness).
Naming is deliberately resource-specific (`ItemCatalogQuery`, not
`ItemQuery`) so the name itself signals "this may contain business logic
that won't generalize," rather than implying a reusable abstraction that
isn't there yet. `.call(params)` returns a `T::Struct` describing the
data a response needs — never a `Result`-shaped success/error wrapper,
since the only failure mode (an invalid closed-enum param) is already
raised, not returned, by `Appliers::SortApplier`. A `<Resource>CatalogQuery`
has no knowledge of HTTP or caching — those stay the controller's job.

**Shared concern queries** (flat, `app/queries/` root — e.g.
`InventoryValuation`) are read-only calculations over already-persisted
data whose result is consumed by more than one query object, an
`Api::V1::` read action, or a cross-Scenario service. They are not
endpoint queries: they return `T::Struct`s, never a response hash, and
they own the SQL aggregate expressions shared by a single-resource path
and a bulk/catalog path so those two cannot drift. A concern query may
be called by `<Resource>CatalogQuery`/`<Resource>DetailQuery`, an
`Api::V1::` controller action, and a cross-Scenario service; it never
calls a controller, service, serializer, or response-payload cache, and
it performs no writes. This is a third shape in the layer, not a
generalization of the per-resource catalog/detail classes: the reuse
axis is "the same read-only calculation", not "the same endpoint
mechanics."

**`app/serializers/`** classes (flat, e.g. `ItemCatalogSerializer`) are
pure functions from an already-fetched data struct to a response hash.
No database or cache access is permitted inside this layer — that is
this layer's one hard boundary.

A `namespace :public do ... end` subfolder under an autoloaded `app/`
root becomes a Zeitwerk namespace automatically (already precedented by
`app/serializers/admin/` → `Admin::`, just not previously used for
anything but the admin API) —
`app/queries/appliers/sort_applier.rb` resolves to
`Appliers::SortApplier`, not a flat `SortApplier`, by the same rule.

## Alternatives Considered

### Alternative: extend `app/services/` to cover this

Treat the new query/filter/sort/paginate logic as more `app/services/`
classes, since it's "extracted business logic out of a controller."

Rejected: `cross-scenario-service-layer.md`'s qualifying criterion is
explicit and narrow — needed identically by two or more Scenarios. Every
consumer here is a Scenario-1 controller. Placing this in `app/services/`
would silently widen that layer's documented meaning for every future
reader, rather than recognizing this as a different reuse axis that
needs its own layer.

### Alternative: generic, config-driven dispatch keyed by string/constant

Model filters and sorts as data (e.g. a hash of `{field_name => {column:,
match_type:}}`) with one fully generic engine interpreting that
configuration, or dispatch a raw string param to a scope method by name
(`model.public_send(scope_name, value)`).

Rejected on two grounds specific to this codebase. First, `ruby-sorbet.md`
mandates `typed: strict` and a `sig` on every method everywhere in this
app; dynamic dispatch by string/`public_send` is invisible to Sorbet,
giving up static checking for the one piece of this design most worth
checking (did every enum value actually get handled?). Second, this
codebase's existing filter/sort logic already has irregular cases a
naive declarative config can't express without escape hatches —
`Options::ItemSortOption`'s `NameAsc` value orders by a raw-SQL jsonb
expression, not a plain column, and each value's `#apply` is arbitrary
Ruby rather than a column/order pair. A config-driven engine would need
an escape hatch for exactly this on its first real resource. `T::Enum`
with a per-value method body has no such limitation: each value's `#apply`
is arbitrary Ruby, the "genericity" is confined to *how a value gets
resolved and iterated*, never to *what it's allowed to do*.

### Alternative: one `Constants`-style file enumerating every resource's options

A single file (or a couple of files, one for sort options and one for
filter options) with every resource's `T::Enum` nested inside, so "all
filterable/sortable fields across the whole app" are visible in one
place — modeled on a prior project's `FilterNames`/`SortNames` pattern.

Rejected: every existing layer in this codebase (`app/services/`,
`app/caching/`, `app/workers/`, `app/schedulers/`, `app/parsers/`) holds
exactly one class per file; a shared multi-class file would be the only
exception. At the scale this project is at (one resource today, at least
three expected) this buys nothing yet and creates an avoidable magnet
for merge conflicts across unrelated resources' PRs as the number of
resources grows. `Options::<Resource><Concern>`, one file each under
`app/queries/options/`, keeps the existing one-class-per-file convention
and remains trivially greppable by name.

### Alternative: a single generic `CatalogQuery` facade for every resource

Rather than one `<Resource>CatalogQuery` class per resource, a single
generic class parameterized by `{model:, sort_enum:, filter_enum:,
serializer:}`, so adding endpoint #2/#3 is "pass different config," not
"write a new class."

Rejected for now: this project has a standing precedent
(`public-api-namespace.md`) of not generalizing a shape from fewer than
three real examples, specifically because guessing wrong is more
expensive to unwind than writing one more small class. `Item`'s
resource-specific extras (price-change aggregates, trend lookup,
freshness timestamp) are the only concrete data point available today
for "what does a catalog query need beyond items+count+pagination" — not
enough to design a generic facade's extension points against. The
per-resource `<Resource>CatalogQuery` shape can be revisited once a
second real resource exists to validate it against, without having
locked in a wrong generic contract first.

### Alternative: `Result`/outcome wrapper objects on `SortApplier` and `<Resource>CatalogQuery`

Have `Appliers::SortApplier` return a `Result` (`success`/`error`/
`scope`), and have `<Resource>CatalogQuery.call` similarly return a
`Result` (`success`/`error`/`payload`), so callers branch on a return
value instead of rescuing an exception.

Rejected: an unrecognized closed-enum value is a genuinely exceptional
client error, not a normal outcome of calling these methods — wrapping
it in a `Result` forced every caller to carry an `if result.success`
branch for a case that, once validation is centralized in
`Appliers::SortApplier`, has exactly one place it can originate and
exactly one place it's handled (`Api::Public::BaseController`'s
`rescue_from`). Earlier drafts of this design also tried threading ETag
and cache-key data through the same `Result`, which mixed HTTP/caching
concerns into a class that should only ever answer "is this sort value
valid" or "what's on this page" — removing the wrapper entirely, in
favor of a raised exception and a cache-free return struct, kept each
class's return type honestly scoped to what it actually computes.

### Alternative: cache read/write inside `<Resource>CatalogQuery`

Have the query object check `ItemCatalogCache` itself, computing and
caching its own payload, so the controller only ever makes one call.

Rejected: this conflates two independent concerns — "what are the
correct rows/aggregates for this request" and "should we skip
recomputing that because a recent answer is cached" — inside one class,
and ties a data-retrieval class to a specific caching strategy it
shouldn't need to know exists. Caching and conditional-GET (`stale?`,
`ETag`) are both already the controller's job for every other endpoint
in this app; keeping them there for this one too, rather than
special-casing list endpoints, keeps "where does caching happen" a
single, consistent answer.

## Consequences

### Positive

- A uniform, thin shape for every `Api::Public::` list endpoint going
  forward: cache-check → query → serialize → cache-write →
  conditional-GET, each step a single-purpose, independently-testable
  class.
- Filter/sort dispatch is exhaustiveness-checked by Sorbet (`T.absurd`)
  at `srb tc` time, rather than relying on a `case`/`when` buried in a
  model scope with no compile-time guarantee every value is handled.
- The resource-agnostic `Appliers::*` classes are genuinely reusable
  immediately — endpoint #2 and #3 don't rewrite pagination clamping or
  closed-enum resolution, only their own `Options::*` enums and
  `<Resource>CatalogQuery`.

### Negative

- Two more top-level `app/` layers to learn, on top of
  parsers/builders/workers/schedulers/services/caching — `app_fetcher`'s
  layer map keeps growing.
- `Appliers::SortApplier`/`Appliers::FilterApplier` type their
  `enum_class:` parameter loosely (`T.untyped`) rather than against a
  proper bound (e.g. a shared interface module every `Options::*` class
  includes), to avoid designing that bound from a single concrete enum
  pair. This is a real, accepted gap in static checking until a second
  resource's `Options::*` classes exist to validate the right bound
  against.
- Each new resource repeats the `<Resource>CatalogQuery` *pattern*, not
  shared code — some boilerplate per new list endpoint is an accepted
  cost of not generalizing the facade yet (see Alternatives).

### Risks

- A future contributor could, on seeing a second or third
  `<Resource>CatalogQuery`, be tempted to immediately collapse them into
  the generic facade this decision explicitly deferred — doing that
  without the second example actually confirming the right generic
  shape would repeat the mistake this decision avoided. The guard is the
  same one `public-api-namespace.md` already established: generalize
  once real examples confirm the shape, not preemptively.
- `Options::*` enums could be misused to enumerate a filter's *allowed
  values* instead of its *field names*, which would silently reintroduce
  the closed-list validation `public-api-controllers.md` explicitly
  prohibits for open string-set params. Guarded by making this
  distinction explicit in the styleguide, not just this ADR.

## Implementation Constraints

- `app/queries/` (flat root): one `<Resource>CatalogQuery` class per
  resource, each a `.call(params)` class method returning a `T::Struct`,
  never a `Result`/success-or-error shape. No reference to any
  `app/caching/` class or to `ActionController`/HTTP concepts.
- `app/queries/appliers/` → `Appliers::` namespace: resource-agnostic
  only — a class here may never import or reference a specific model or
  a specific `Options::*` member by name.
- `app/queries/options/` → `Options::` namespace: one `T::Enum` subclass
  per resource per concern, `case self` / `T.absurd(self)` for
  exhaustiveness, one enum value per filterable/sortable field name,
  never per allowed value.
- `app/serializers/` (flat root): pure functions only — no
  `ActiveRecord`/`Rails.cache` calls permitted inside this layer.
- Shared concern queries (`app/queries/<concern>.rb`, e.g.
  `InventoryValuation`): return `T::Struct`s, never a response hash;
  perform no writes and never call a controller, service, serializer, or
  response-payload cache. They may be called from a resource query, an
  `Api::V1::` read action, or a cross-Scenario service's read step, and
  own the shared aggregate SQL for both the single-resource and
  bulk/catalog paths.
- The shared `Api::Public::UnsupportedParamError` raised by
  `Appliers::SortApplier` is an `Api::Public::` namespace-level concern,
  not owned by this layer — its location (`lib/api/public/`) and the
  base-controller `rescue_from` that catches it are governed by
  `public-api-controllers.md`, not restated here.
- `ItemPricesController#history` / `InventoryValuesController` and their
  existing inline `PricePeriod` usage are not migrated to
  `Appliers::SortApplier` by this decision — left as they are; a future,
  separate decision if that migration is ever wanted.

## Related

- `agent/adr/fetcher/cross-scenario-service-layer.md` — the layer this
  decision is deliberately not reusing, and whose qualifying criterion
  motivates why a new layer is needed at all.
- `agent/adr/fetcher/public-api-namespace.md` — the "wait for a third
  example" precedent this decision partially follows (mechanism-level
  genericity) and partially departs from (the per-resource facade stays
  ungeneralized), with the distinction stated explicitly in Context.
- `agent/styleguides/fetcher/list-query-objects.md` — the styleguide
  this ADR backs, covering the concrete how.
- `agent/styleguides/fetcher/public-api-controllers.md` — updated
  alongside this decision for the controller-side shape and the shared
  error class.
- `agent/styleguides/fetcher/architecture-layers.md` — updated to add
  these layers to `app_fetcher`'s layer map.
- `app_fetcher/app/models/price_period.rb` — the partial, undocumented
  precedent this decision generalizes.
- `agent/plans/item-catalog-query-refactor.md` — the plan this
  decision unblocks.
