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
`agent/styleguides/` itself). Once a file is brought into compliance,
delete its entry — don't leave a stale line behind.

`implement-plan` checks this file for any file it's about to touch: if the
fix is small and within the styleguide already being followed for that
change, fix it as part of that change and remove the entry. Don't expand
a change's scope just because an unrelated file is flagged here.

---

## Shared

(none yet)

## `app_fetcher`

- `app_fetcher/spec/fixtures/items.yml`, `price_logs.yml` — Rails
  fixtures; `agent/styleguides/rspec-conventions.md` now standardizes
  on `FactoryBot` for test data. Existing rows (`redline`,
  `redline_recent`, etc.) stay loaded and referenced by their current
  specs; don't add new fixture rows here — use a factory instead. See
  `agent/adr/fetcher/rspec-testing-strategy.md`.
- `app_fetcher/sorbet/rbi/gems/connection_pool@3.0.2.rbi` — an empty
  Tapioca stub ("THIS IS AN EMPTY RBI FILE"): `sidekiq` loads
  `connection_pool` transitively before Tapioca's require pass, so Tapioca
  can't attribute any constant to it. `bin/tapioca gem connection_pool`
  can't repair it either — `bin/tapioca gem` currently aborts on
  `solid_cache` resolving the `cache` connection before Rails loads its
  database config. The sanctioned workaround is the hand-written
  `sorbet/rbi/shims/connection_pool.rbi` plus listing the gem in
  `sorbet/tapioca/config.yml`'s `gem.exclude`; see
  `agent/styleguides/ruby-sorbet.md` → Exceptions.
- `app_fetcher/bin/ci` (and `app_fetcher/config/ci.rb`) — `bin/ci` requires
  `active_support/continuous_integration`, which doesn't exist in this
  app's Rails 7.2 bundle, so the local "run everything" entry point aborts
  with a `LoadError` before any step runs. `ci-and-coverage.md` expects
  `bin/ci` to mirror the CI checks (which CI runs as explicit
  `rubocop`/`srb tc`/`rspec` commands, not through `bin/ci`). Found while
  implementing the Sorbet fix; not fixed here, since that change only
  needed the individual steps.

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
  `agent/styleguides/ruby-sorbet.md`.
- `app_core/spec/fixtures/users.yml` — Rails fixture; same deviation and
  same rationale as the `app_fetcher` fixtures entry above. Existing
  `users(:one)` reference stays as-is; new scenarios use a `FactoryBot`
  factory instead.
