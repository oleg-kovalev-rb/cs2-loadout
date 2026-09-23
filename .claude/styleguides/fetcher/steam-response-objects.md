---
description: Steam::Response/DTO conventions — Steam::Client's typed result objects, built via from_hash, consumed instead of raised exceptions.
---

# Steam Response Objects (`Steam::Response` + DTOs)

## Purpose

A uniform way to represent the outcome of a call to a Steam endpoint:
either a typed piece of data, or an error — never an exception. Every
`Steam::Client` method returns one of these.

## When to Use

Use this pattern for the return value of any `Steam::Client` method, and
for any new data shape Steam returns that needs to flow back to a caller.
Don't use it for internal `app_fetcher` domain data (e.g. `Item`,
`PriceLog`) — those are ActiveRecord models, not Steam response DTOs.

## Structure

- DTOs live in a `Data` namespace nested under `Steam::Response` (they
  only exist to be a `Response`'s payload):
  `Steam::Response::Data::ItemPriceData`,
  `Steam::Response::Data::InventoryData`.
- One class per file, named after the class in `snake_case`, under
  `lib/steam/response/data/` (`Steam::Response::Data::ItemPriceData` →
  `lib/steam/response/data/item_price_data.rb`,
  `Steam::Response::Data::InventoryData` →
  `lib/steam/response/data/inventory_data.rb`). Do not add a new DTO
  class into `response.rb` itself — that file holds only the generic
  `Steam::Response[DataClass]` struct, its `DataClassMethods` interface,
  and the `SteamDataObjects` type alias.
- Define each DTO with the **compact class-path form**:
  `class Steam::Response::Data::ItemPriceData < T::Struct ... end`, and
  use the **fully-qualified name inside the class body too**
  (`Steam::Response::Data::ItemPriceData.new(...)`, not bare
  `ItemPriceData.new(...)`) — compact-path class definitions don't add
  the intermediate namespaces to Ruby's constant-lookup nesting, so a
  bare reference inside the body won't resolve.
- Do not define a DTO by reopening `Response` (`module Steam; class
  Response < T::Struct; class ItemPriceData < T::Struct; ...; end; end;
  end`), and do not give DTOs a shared `T::Struct`-based base class to
  inherit from — both are broken by Sorbet in different ways. See the ADR
  below for the full explanation.
- `# typed: strict`, `extend T::Sig` on every DTO and on `Response`
  itself.

## Interface

- `Steam::Response[DataClass]` — generic `T::Struct` with `const :status,
  Integer`, `const :data, T.nilable(DataClass)`, `const :error,
  T.nilable(String)`, and `#success?` (`status == 200`).
- Every DTO is a `T::Struct` with `const` fields only — never `prop`.
  Fields are `T.nilable` unless Steam is known to always return them.
- Every DTO `extend`s `Steam::Response::DataClassMethods` and implements
  `self.from_hash(hash)` as its only constructor path for real Steam data.
  Never build a DTO with hand-picked hash keys at the call site — always
  go through `from_hash`. This is a mixin (`extend`), not inheritance from
  a shared base class — see the ADR for why.

## Responsibilities

A DTO's `from_hash` owns turning Steam's raw JSON hash into typed fields.
It does not own: validation beyond defensive presence checks, business
logic, or persistence. Turning a DTO into a persisted record is a
different layer's job (e.g. `Steam::PriceLogBuilder`).

## Dependencies

DTOs and `Steam::Response` must not depend on ActiveRecord or any
`app_fetcher` domain model — they only know about the shape of Steam's
JSON.

## Rules

### MUST

- One class, one file, under `lib/steam/response/data/`, defined with the
  compact `class Steam::Response::Data::X < T::Struct` form (see
  Structure) using fully-qualified names inside the body — never by
  reopening `Response` and never via a shared `T::Struct`-based ancestor.
- `extend Response::DataClassMethods` and implement `self.from_hash`.
- Use `const`, not `prop` — DTOs are immutable once built.
- Access the raw hash defensively: `hash["key"] || default` (see
  `InventoryData.from_hash`'s `hash["assets"] || []`), since Steam's JSON
  shape isn't contractually guaranteed.

### SHOULD

- Keep derived read methods (e.g. `InventoryData#market_hash_names`) on
  the DTO itself when they only reshape the DTO's own fields, rather than
  pushing that logic onto callers.

### MUST NOT

- Do not construct a DTO with `.new(...)` from a raw Steam hash outside
  of `from_hash`.
- Do not give a DTO knowledge of HTTP status codes or rate limiting —
  that's `Steam::Client`'s job; a DTO only knows how to parse a body it's
  handed.

## Error Handling

DTOs don't handle errors — by the time `from_hash` runs, `Steam::Client`
has already confirmed the response was a success. A DTO's `from_hash`
should tolerate missing/null fields (via the defensive-access rule above)
but never raise; if a field truly can't be recovered, leave it `nil` (for
`T.nilable` fields) or an empty collection.

## Interaction With Other Layers

```text
Steam::Client#perform_request
    ↓ HTTP 200 + parsed JSON body
DtoClass.from_hash(body)
    ↓
Steam::Response[DtoClass].new(status: 200, data: dto)
    ↓ .success? / .data / .error
Worker / Controller
```

## Canonical Implementations

- `app_fetcher/lib/steam/response.rb` — `Steam::Response`,
  `DataClassMethods`
- `app_fetcher/lib/steam/response/data/item_price_data.rb` —
  `Steam::Response::Data::ItemPriceData`
- `app_fetcher/lib/steam/response/data/inventory_data.rb` —
  `Steam::Response::Data::InventoryData`

## Related ADR

`.claude/adr/fetcher/steam-client-response-objects-and-rate-limiting.md` — why failures are
represented as result objects instead of raised exceptions, and why DTOs
join the contract via `extend` rather than inheriting from a shared base
class.
