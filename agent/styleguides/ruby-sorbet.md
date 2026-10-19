---
description: Sorbet typing discipline and Ruby idioms for hand-written Ruby files in app_fetcher/app_core — sigils, sig, T.let, generics, guard clauses.
---

# Ruby & Sorbet Conventions

## Purpose

How Ruby code is typed and structured with Sorbet in this monorepo, plus
a handful of Ruby idioms used consistently across both `app_fetcher` and
`app_core`.

Generic formatting (quotes, spacing, indentation) is already owned by
`rubocop-rails-omakase` — both apps inherit the identical `.rubocop.yml`.
This guide only covers what rubocop doesn't check: Sorbet typing
discipline and a few Ruby-level idioms.

## When to Use

Applies to every hand-written Ruby file in `app_fetcher` and `app_core` —
models, controllers, jobs/workers, schedulers, parsers/builders, `lib/`
classes, actions.

Does not apply to Rails-generated framework base classes left at their
scaffolded default (`ApplicationRecord`, `ApplicationJob`,
`ApplicationMailer`, `ApplicationHelper`) — those stay untyped until they
gain real custom logic.

## Structure

- Every file's first line (after any `require`) is a Sorbet sigil
  comment.
- `extend T::Sig` is the first line inside the class/module body, before
  any constant or method.
- A `sig { ... }` block immediately above every method definition —
  instance, class (`self.`), and private methods alike.
- `app_core`'s Steam-related classes live under a `Steam::` module
  (`Steam::LoginUser`, `Steam::Authenticator`, `Steam::ProfileFetcher`,
  `Steam::BridgeToken`). In `app_fetcher`, `Steam::` is reserved for the
  `lib/steam/` integration boundary (`Steam::Client`, `Steam::Response`
  and its DTOs); its `app/` layers stay flat/top-level even when
  Steam-specific (`ItemParser`, `PriceLogBuilder`, services, workers,
  schedulers).

## Rules

### MUST

- `# typed: strict` on every hand-written file (see When to Use for the
  framework-boilerplate exception). This applies to controllers too —
  `app_fetcher`'s controllers prove `strict` works fine there; there's no
  established case for a lower sigil on a hand-written file.
- `extend T::Sig` before using `sig`.
- A `sig` on every method, no exceptions — under `typed: strict` a method
  without one is a `srb tc` error, not a style nit.
- After adding anything Sorbet can't see statically on an
  `ActiveRecord::Base` model — a `scope`, a new `store_accessor` key, an
  association, an enum — regenerate that model's DSL RBI with `bundle
  exec tapioca dsl <Model>` and commit the result under
  `sorbet/rbi/dsl/`. `tapioca` is already in the Gemfile (`dev` group)
  for exactly this; don't hand-write an RBI shim for something `tapioca`
  already generates, and don't add a second DSL-RBI tool (e.g.
  `sorbet-rails`) alongside it. See `Item`'s `sorbet/rbi/dsl/item.rbi`,
  generated after `scope :marketable`/`:stale_or_unpriced`/
  `:due_for_price_update` were added — before that RBI existed, `srb tc`
  couldn't resolve even `Item`'s plain column attributes
  (`market_hash_name`, `current_price_cents`), because no model in either
  app had ever had its DSL RBI generated before.
- Wrap every class-level constant in `T.let(value, Type)`, even ones a
  literal-inference-savvy reader might expect Sorbet to infer on its own
  (e.g. a frozen string or a `Regexp`) — see `Steam::Client::BASE_URL`,
  `Steam::BridgeToken::ALGORITHM`/`TTL`,
  `PriceLogBuilder::PRICE_REGEXP`. Whether a specific literal
  actually needs `T.let` to pass `srb tc` is inconsistent (a bare
  `Regexp#freeze` needs it, a bare string often doesn't) — wrap all of
  them, consistently, rather than relying on `srb tc` to tell you which
  ones matter.
- Type generic collections explicitly: `T::Array[String]`,
  `T::Hash[String, T.untyped]` — never a bare `Array`/`Hash`.
- For a hash with a fixed, known set of keys, use a Sorbet shape type
  (`{key: Type, ...}`, typically behind a `T.type_alias`) instead of
  `T::Hash[String, T.untyped]` — see `ItemParser::ItemDto` and
  `Steam::ProfileFetcher::ProfileData`. Reserve `T::Hash[KeyType,
  ValueType]` for genuinely dynamic hashes — an unknown/varying number of
  keys of the same value type, e.g. the raw parsed JSON body handed to
  `DataClassMethods#from_hash`.
- Nilable values are `T.nilable(X)`, never a bare type with an implicit
  possible-nil.
- For a closed set of string tags that each carry their own associated
  behavior/value (not just a fixed-keys *hash*, which the shape-type rule
  above covers), use a `T::Enum` instead of a plain
  `T::Hash[String, ...]` constant — see `PricePeriod`
  (`app_fetcher/app/models/price_period.rb`): one member per period tag
  (`"24h"`, `"7d"`, ...), with a `#duration` instance method mapping each
  to its `ActiveSupport::Duration` (or `nil` for `"all"`). Parse an
  incoming param with `.try_deserialize` (returns `nil` for an unknown
  value — branch on that, don't rescue `KeyError` from `.deserialize`).
  Reuse the same enum class across multiple controllers/endpoints that
  share the same tag vocabulary, even if each endpoint only accepts a
  subset of members — declare that subset on the model that owns the
  rows (`InventoryValueLog::SUPPORTED_PERIODS`,
  `PriceLog::SUPPORTED_PERIODS`) rather than forking the enum or
  re-declaring it per controller. Resolve a period param through
  `PricePeriod.resolve(raw_value, supported:, default:)`, which returns
  nil for an unknown or unsupported value so each caller can choose its
  own failure shape.
- Private class methods are declared inside `class << self; extend
  T::Sig; private; ...; end` (see `PriceLogBuilder`), not
  `private_class_method`.

### SHOULD

- Use Ruby 3.1 hash-value shorthand (`market_hash_name:,` not
  `market_hash_name: market_hash_name,`) whenever the local variable name
  matches the key (see `ItemParser.parse`,
  `PriceLogBuilder.build`).
- Prefer guard clauses (`return ... if ...`) over nested conditionals for
  early exits (see `PriceLogBuilder.to_cents`,
  `PriceUpdateWorker#perform`).
- Rescue at the end of the method body (no explicit `begin`/`end`) when
  the whole method's failure modes are known upfront (see
  `Steam::Client#perform_request`,
  `Api::V1::BaseController#authenticate_bridge_token!`,
  `Steam::ProfileFetcher.call`).

### MUST NOT

- Don't add a runtime type check or manual `raise ArgumentError` for
  something a `sig` already statically guarantees — that's what `typed:
  strict` is for.
- Don't reach for `T.untyped` to make a `sig` pass instead of expressing
  the real type, except at genuine external-data boundaries (parsed
  JSON, a hash of args from an untyped source) where `T.untyped` is the
  honest answer — see `Steam::Client#perform_request`'s `dto_class:
  T.untyped`.

## Exceptions

Sanctioned deviations from the rules above. Each entry names the rule it
excepts and the concrete case that justifies it. Add a case here rather
than widening a `MUST`/`MUST NOT` into a one-off.

- **`T.unsafe` at a generic-deserialization boundary.** The one place the
  "don't reach for `T.untyped`" MUST NOT doesn't cover is a resource-agnostic
  applier whose body cannot name the concrete enum: `try_deserialize`
  returns `T.nilable(T::Enum)`, and the resource-specific `#apply(scope)`
  lives on the resolved member's subclass, so the dispatch goes through a
  single localized `T.unsafe(option)`. Not a licence to use `T.unsafe`
  anywhere else. See `Appliers::SortApplier.call`.
- **Hand-written gem RBI when Tapioca emits an unusable stub.** The
  "don't hand-write an RBI shim for something `tapioca` already generates"
  MUST has one carve-out: when the generated file is an empty stub (the
  "THIS IS AN EMPTY RBI FILE" header — Tapioca couldn't attribute any
  constant, e.g. `connection_pool` is loaded transitively by `sidekiq`
  before Tapioca's require pass), add a minimal `# typed: false` shim under
  `sorbet/rbi/shims/` for only the constants/methods the app calls, and add
  the gem to `gem.exclude` in `sorbet/tapioca/config.yml`. See
  `sorbet/rbi/shims/ffi_shim.rbi`; don't reach for a shim for a gem whose
  RBI Tapioca generates correctly.
- **`T::Sig::WithoutRuntime.sig` for Tapioca relation types.** A
  Tapioca-generated relation type (`Model::PrivateRelation`,
  `PrivateAssociationRelation`, `PrivateCollectionProxy`) exists only in
  the RBI, not at runtime, so putting it in a normal `sig` passes `srb tc`
  but raises `NameError` the first time the method runs. When a signature
  genuinely needs the relation type to see a model's scopes, declare it
  with `T::Sig::WithoutRuntime.sig { ... }` — same static checking, no
  runtime check — rather than falling back to `ActiveRecord::Relation` +
  `T.unsafe`, which would hide the scope methods and give up the static
  guarantee. See `Options::ItemFilterOption#apply`.

## Error Handling

Method-level `rescue` (no explicit `begin`) is the default for known,
enumerable failure modes at the end of a method — see the SHOULD rule
above. Reserve `begin/rescue/end` for the rarer case where only part of a
method needs to be guarded.

## Canonical Implementations

- `app_fetcher/lib/steam/client.rb`, `app_fetcher/lib/steam/response.rb`
- `app_fetcher/app/builders/price_log_builder.rb`
- `app_core/lib/steam/bridge_token.rb`,
  `app_core/lib/steam/profile_fetcher.rb`
- `app_core/app/actions/steam/login_user.rb`,
  `app_core/app/models/user.rb`
- `app_fetcher/app/models/price_period.rb` — the `T::Enum` pattern for a
  closed set of API-param tags, plus `#since`/`#since_date` and
  `.resolve`
- `app_fetcher/app/models/item.rb` + `app_fetcher/sorbet/rbi/dsl/item.rbi`
  — the `tapioca dsl` regeneration workflow for a model that gained a new
  `scope`
- `app_fetcher/app/queries/appliers/sort_applier.rb` — the scope-in/
  scope-out sort dispatcher (see Exceptions for the localized `T.unsafe`)
- `app_fetcher/sorbet/rbi/shims/ffi_shim.rbi` — the minimal `# typed:
  false` gem shim (see Exceptions)
