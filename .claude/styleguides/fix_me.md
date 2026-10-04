# Style Deviations

Files that deviate from an established convention or styleguide rule,
found while writing/updating a styleguide, doing research, or
implementing a plan.

This is not a task backlog and not a place to design a fix. It exists so:

- a deviation found while extracting a styleguide doesn't get silently
  folded in as an "alternative" convention, or fixed on the spot (out of
  scope for `create-styleguide`/`create-styleguide-from-scratch`);
- anyone who later touches one of these files already knows it's
  non-conforming, instead of re-deriving that from scratch.

Format: one line per file —

```
- <path> — <which rule/convention it deviates from, in one line>
```

Group entries under the scope they belong to (mirrors
`.claude/styleguides/` itself). Once a file is brought into compliance,
delete its entry — don't leave a stale line behind.

`implement-plan` checks this file for any file it's about to touch: if the
fix is small and within the styleguide already being followed for that
change, fix it as part of that change and remove the entry. Don't expand
a change's scope just because an unrelated file is flagged here.

---

## Shared

(none yet)

## `app_fetcher`

- `app_fetcher/app/parsers/steam/item_parser.rb` — `CONDITION_EXTRACT_REGEX`
  and `CONDITION_CLEANUP_REGEX` are plain `Regexp#freeze` literals, not
  wrapped in `T.let`, unlike every other constant-bearing file in the
  codebase (`Steam::Client::BASE_URL`, `Steam::PriceLogBuilder::PRICE_REGEXP`,
  etc.). Confirmed as a real `srb tc` error (`7027: Constants must have
  type annotations with T.let when specifying # typed: strict`), not just
  a style nit.
- `app_fetcher/app/models/item.rb` — the `stattrak` override method has no
  `sig` and the class has no `extend T::Sig`, unlike every other method in
  a `typed: strict` file. Confirmed as a real `srb tc` error (`7017: The
  method 'stattrak' does not have a 'sig'`).
- `app_fetcher/app/schedulers/price_scheduler.rb`,
  `app_fetcher/app/schedulers/inventory_value_scheduler.rb` —
  `sidekiq_options` has no `retry:` on either, unlike both workers
  (`PriceUpdateWorker: retry: 5`, `InventoryValueUpdateWorker: retry: 3`), so
  both silently fall back to Sidekiq's default of 25 retries over ~3
  weeks. Not confirmed by a tool the way the two entries above are (this
  is a Sidekiq runtime default, not a static check) — judgment call based
  on the other two jobs always setting it explicitly. New schedulers
  (e.g. `UserInventorySyncScheduler`) set an explicit `retry:` per this
  reading; these two existing ones weren't touched by that change and
  still need it. See `.claude/styleguides/fetcher/background-jobs.md`.
- `app_fetcher/spec/fixtures/items.yml`, `price_logs.yml` — Rails
  fixtures; `.claude/styleguides/rspec-conventions.md` now standardizes
  on `FactoryBot` for test data. Existing rows (`redline`,
  `redline_recent`, etc.) stay loaded and referenced by their current
  specs; don't add new fixture rows here — use a factory instead. See
  `.claude/adr/fetcher/rspec-testing-strategy.md`.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `price_histories_spec.rb` — `inventories_spec.rb` hand-writes a
  `WebMock` `stub_request` body for a Steam API call at the request
  level; `rspec-conventions.md` now requires a VCR cassette at that
  level (unit specs keep using `WebMock` directly). Not migrated here;
  migrate the next time either file is otherwise touched.

## `app_core`

- `app_core/lib/steam/authenticator.rb` — missing a Sorbet `# typed:`
  sigil entirely; every sibling in `lib/steam/` (`bridge_token.rb`,
  `profile_fetcher.rb`) is `typed: strict`.
- `app_core/app/controllers/application_controller.rb` — no Sorbet sigil
  at all.
- `app_core/app/controllers/sessions_controller.rb` — `typed: true`
  instead of `typed: strict`.
  Both are real, hand-written controllers with actual logic, not
  boilerplate — `app_fetcher`'s controllers prove `strict` works fine on
  controllers, so this isn't a justified exception, just drift. See
  `.claude/styleguides/ruby-sorbet.md`.
- `app_core/spec/fixtures/users.yml` — Rails fixture; same deviation and
  same rationale as the `app_fetcher` fixtures entry above. Existing
  `users(:one)` reference stays as-is; new scenarios use a `FactoryBot`
  factory instead.
- `app_core/lib/steam/profile_fetcher.rb` — `require 'net/http'`/
  `require 'uri'` use single-quoted string literals; `bin/rubocop`
  confirms `Style/StringLiterals` (double-quoted preferred) actually
  applies to this file (a sibling file added in the same session,
  `inventory_value_trigger.rb`, hit and autocorrected the identical
  offense) — this is real drift, not an intentional exception. Not fixed
  here since this file wasn't otherwise being touched.
