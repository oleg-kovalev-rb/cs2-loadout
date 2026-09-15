# Steam API Client: Result Objects Over Exceptions, Centralized Rate Limiting

## Status

Accepted

## Context

`app_fetcher` calls Steam's public (undocumented, informally rate-limited)
HTTP endpoints from multiple call sites — a Sidekiq worker
(`PriceUpdateWorker`) and an internal API controller
(`InventoriesController`), with more call sites expected as more Steam
data is ingested. Steam enforces its own rate limits and returns several
distinct failure shapes: HTTP 429, non-200 statuses, and technically-200
responses with `success: false` in the body. Network and JSON-parsing
failures are also expected occasionally.

Each new call site needs the same three things — rate limiting, HTTP
transport, and a consistent way to represent "the call didn't work, here's
why" — without re-deriving them independently.

## Decision

All outbound Steam HTTP calls go through a single `Steam::Client`, which:

- throttles every request through `Prop.throttle!` **before** issuing it,
  using a two-tier (requests-per-minute + requests-per-day) limit keyed
  per endpoint and configured centrally in
  `config/initializers/prop.rb`;
- returns a generic `Steam::Response[T]` result struct (`status`, `data`,
  `error`, `success?`) instead of raising for any of the expected failure
  modes (rate limited, Steam-side error, malformed/absent JSON, network
  error).

Callers branch on `response.success?` / `.data` / `.error`. None of the
expected failure modes ever reach a caller as a raised exception.

The DTOs that `Response#data` holds
(`Steam::Response::Data::ItemPriceData`,
`Steam::Response::Data::InventoryData`) live in a `Data` namespace nested
under `Steam::Response`, since they only exist to be a `Response`'s
payload. They plug into the contract via `extend
Steam::Response::DataClassMethods` — a Sorbet `interface!` module
providing the abstract `self.from_hash` — not by inheriting from a shared
base class. See "Alternative: shared base class for DTOs" below for why;
short version, it's not a style preference, sorbet-runtime forbids it
outright.

Rate limiting here is deliberately request-count throttling via `Prop`,
not a Faraday middleware — that's a separate, complementary mechanism
(`Faraday::UserAgentRotator` rotates the User-Agent header to reduce the
chance of Steam blocking on a fixed fingerprint; see
`app_fetcher/lib/steam/README.md`). The two are not alternatives to each
other.

## Alternatives Considered

### Alternative: Rate limiting at each call site

Each worker/controller calls `Prop.throttle!` itself before invoking a
plain Faraday/Net::HTTP call.

Rejected because:

- duplicates limit-key bookkeeping at every call site;
- trivially easy to forget when adding a new call site, silently
  producing an un-throttled call against Steam;
- no single place to audit or change limits.

### Alternative: Exceptions for failure modes

Raise typed exceptions (e.g. `Steam::RateLimitedError`,
`Steam::ApiError`) and let each caller rescue them.

Rejected because:

- Steam rate limiting and transient API errors are expected, frequent
  conditions, not exceptional ones — modeling them as exceptions pushes
  the same rescue boilerplate into every caller;
- a result object keeps "this call can fail in known ways" visible in the
  return type instead of hidden in a `rescue` a caller might forget.

### Alternative: shared base class for DTOs

Give every DTO a common ancestor (e.g. `class ItemPriceData <
Steam::Responses::Base`, with `Base < T::Struct`) that implements — or
forces via `abstract!` — `from_hash`, instead of `extend`-ing an
interface module into each DTO.

Rejected — not on style grounds, but because it was actually tried and
sorbet-runtime refuses it outright:

```
RuntimeError:
  Steam::Responses::Base is a subclass of T::Struct and cannot be subclassed
```

`T::Struct` explicitly disallows a second level of subclassing — a class
that is itself a `T::Struct` subclass cannot be subclassed further. Since
a DTO's data shape requires `T::Struct` as its superclass (for `const`
fields, the generated constructor, equality), there is no room in Ruby's
single-inheritance chain for an intermediate `Base < T::Struct` that DTOs
then subclass — `T::Struct` reserves that one inheritance slot for itself
and refuses to sit in the middle of a chain.

Working around this (e.g. building DTOs on raw `T::Props` +
`T::Props::Constructor` instead of `T::Struct`, which isn't guarded the
same way) was considered and rejected too: it would depart from the
`T::Struct` idiom used everywhere else in this codebase for a single
family of DTOs, trading a well-understood, widely-used pattern for a
lower-level one to satisfy inheritance for its own sake.

`extend Response::DataClassMethods` sidesteps the problem entirely: it
expresses `from_hash` as a capability ("can be built from a Steam hash"),
not an identity, as a class-method contract enforced by Sorbet's
`interface!` — independent of what the class inherits from, so it never
competes with `T::Struct` for the inheritance slot.

### Alternative: One client class per endpoint

`Steam::PriceClient`, `Steam::InventoryClient`, etc., instead of one
`Steam::Client` with multiple methods.

Rejected because:

- only two endpoints exist today, and both share the exact same
  transport, rate-limiting, and error-mapping shape;
- splitting now would be speculative — see Implementation Constraints for
  when to revisit this.

## Consequences

### Positive

- One place to change transport concerns (headers, timeouts, middleware).
- One place to audit or adjust rate limits across all Steam endpoints.
- Callers get a uniform, exception-free contract — the same
  `success?`/`data`/`error` branching regardless of which endpoint they
  called.
- Adding a new endpoint is mechanical: add a method, a DTO, and a
  `limit_key` pair, following the existing shape.

### Negative

- `Steam::Client` accumulates every Steam endpoint in one class; nothing
  currently forces a split if it grows into unrelated concerns.
- `perform_request` returns `T.untyped` internally (cast to
  `Steam::Response[SpecificDtoClass]` at each call site) — Sorbet's
  guarantees are weaker at that one internal boundary than everywhere
  else in the class.

## Implementation Constraints

- New Steam endpoints must go through `perform_request` (or an equivalent
  single choke point) — no bypassing rate limiting with a direct
  Faraday/Net::HTTP call.
- Every new endpoint gets its own Prop `limit_key`, with matching
  `_rpm`/`_rpd` `Prop.configure` entries added to
  `config/initializers/prop.rb`.
- DTOs must implement `Steam::Response::DataClassMethods#from_hash`;
  neither `Steam::Client` nor `Steam::Response` may depend on
  ActiveRecord models.
- If `Steam::Client` grows past a handful of endpoints, or starts serving
  clearly distinct Steam sub-APIs (e.g. store vs. community vs. partner),
  treat that as a signal to revisit this decision and split by
  sub-domain — not a rule to apply pre-emptively today.

## Related

- `app_fetcher/lib/steam/README.md` — how the client, rate limiting, and
  middleware actually work today.
- `.claude/styleguides/fetcher/steam-response-objects.md` — rules for
  `Steam::Response` and its DTOs.
- `app_fetcher/lib/steam/client.rb`,
  `app_fetcher/lib/steam/response.rb`,
  `app_fetcher/lib/steam/response/data/item_price_data.rb`,
  `app_fetcher/lib/steam/response/data/inventory_data.rb`,
  `config/initializers/prop.rb`
