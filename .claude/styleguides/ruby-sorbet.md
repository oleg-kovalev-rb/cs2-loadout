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
- Domain-specific classes (anything Steam-related) live under a
  `Steam::` module regardless of which app they're in
  (`Steam::ItemParser`, `Steam::Client` in `app_fetcher`;
  `Steam::LoginUser`, `Steam::Authenticator` in `app_core`).

## Rules

### MUST

- `# typed: strict` on every hand-written file (see When to Use for the
  framework-boilerplate exception). This applies to controllers too —
  `app_fetcher`'s controllers prove `strict` works fine there; there's no
  established case for a lower sigil on a hand-written file.
- `extend T::Sig` before using `sig`.
- A `sig` on every method, no exceptions — under `typed: strict` a method
  without one is a `srb tc` error, not a style nit.
- Wrap every class-level constant in `T.let(value, Type)`, even ones a
  literal-inference-savvy reader might expect Sorbet to infer on its own
  (e.g. a frozen string or a `Regexp`) — see `Steam::Client::BASE_URL`,
  `Steam::BridgeToken::ALGORITHM`/`TTL`,
  `Steam::PriceLogBuilder::PRICE_REGEXP`. Whether a specific literal
  actually needs `T.let` to pass `srb tc` is inconsistent (a bare
  `Regexp#freeze` needs it, a bare string often doesn't) — wrap all of
  them, consistently, rather than relying on `srb tc` to tell you which
  ones matter.
- Type generic collections explicitly: `T::Array[String]`,
  `T::Hash[String, T.untyped]` — never a bare `Array`/`Hash`.
- For a hash with a fixed, known set of keys, use a Sorbet shape type
  (`{key: Type, ...}`, typically behind a `T.type_alias`) instead of
  `T::Hash[String, T.untyped]` — see `Steam::ItemParser::ItemDto` and
  `Steam::ProfileFetcher::ProfileData`. Reserve `T::Hash[KeyType,
  ValueType]` for genuinely dynamic hashes — an unknown/varying number of
  keys of the same value type, e.g. the raw parsed JSON body handed to
  `DataClassMethods#from_hash`.
- Nilable values are `T.nilable(X)`, never a bare type with an implicit
  possible-nil.
- Private class methods are declared inside `class << self; extend
  T::Sig; private; ...; end` (see `Steam::PriceLogBuilder`), not
  `private_class_method`.

### SHOULD

- Use Ruby 3.1 hash-value shorthand (`market_hash_name:,` not
  `market_hash_name: market_hash_name,`) whenever the local variable name
  matches the key (see `Steam::ItemParser#parse`,
  `Steam::PriceLogBuilder.build`).
- Prefer guard clauses (`return ... if ...`) over nested conditionals for
  early exits (see `Steam::PriceLogBuilder.to_cents`,
  `PriceUpdateWorker#perform`).
- Rescue at the end of the method body (no explicit `begin`/`end`) when
  the whole method's failure modes are known upfront (see
  `Steam::Client#perform_request`,
  `ApplicationController#authenticate_bridge_token!`,
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

## Error Handling

Method-level `rescue` (no explicit `begin`) is the default for known,
enumerable failure modes at the end of a method — see the SHOULD rule
above. Reserve `begin/rescue/end` for the rarer case where only part of a
method needs to be guarded.

## Canonical Implementations

- `app_fetcher/lib/steam/client.rb`, `app_fetcher/lib/steam/response.rb`
- `app_fetcher/app/builders/steam/price_log_builder.rb`
- `app_core/lib/steam/bridge_token.rb`,
  `app_core/lib/steam/profile_fetcher.rb`
- `app_core/app/actions/steam/login_user.rb`,
  `app_core/app/models/user.rb`
