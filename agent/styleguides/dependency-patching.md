---
description: How this monorepo patches pinned gems for security advisories — scoping the update, keeping it within the declared version lines, rebuilding the images that bake the gems, and what may not be done to make `bin/bundler-audit` pass.
---

# Dependency Patching

## Purpose

Covers the work of moving already-declared dependencies to versions
without a known advisory, and the policy around the `bundler-audit` gate.
It exists because the mechanics are non-obvious here (gems are baked into
the images at build time; the lockfile is what actually changes) and
because "make the gate green" has tempting shortcuts this project does not
take.

It answers:

- where a dependency change actually lands;
- how to scope an update so only the intended gems move;
- what may and may not be done to satisfy an audit.

It does not cover adding or removing a dependency for a feature (ordinary
`Gemfile` work), nor the definition of the CI jobs themselves — that is
`agent/styleguides/ci-and-coverage.md`.

## When to Use

Applies whenever:

- `bin/bundler-audit` reports one or more advisories in either app;
- a pinned tool gem must be refreshed (e.g. `brakeman` — see the
  `--ensure-latest` rule in `agent/styleguides/ci-and-coverage.md`);
- one gem can only be fixed by first moving another that caps it (the
  transitive-upper-bound case).

Applies identically to `app_fetcher` and `app_core`: same tooling, same
Dockerfile shape, same two lockfiles.

## Structure

- `Gemfile` — the declared constraints. Only direct dependencies appear
  here (`rails "~> 7.2.0"`, `puma ">= 5.0"`, `pg "~> 1.1"`, and
  `app_core`'s `minitest "~> 5.25"`).
- `Gemfile.lock` — the resolved graph, committed. This is the file a patch
  changes; most flagged gems are transitive and appear nowhere else.
- `config/bundler-audit.yml` — the ignore list. Both apps ship it with
  only the `CVE-THAT-DOES-NOT-APPLY` placeholder entry, which matches no
  real advisory, so the lists are effectively empty.
- `bin/bundler-audit` — the wrapper CI and `config/ci.rb` call. It appends
  `--config config/bundler-audit.yml` when invoked with no arguments or
  with `check`, so the ignore list is always consulted.
- `<app>/Dockerfile` — `COPY Gemfile*` followed by `RUN bundle install`.
  Gems are installed into the image at **build** time.

## Rules

### MUST

- Run the update from inside the container
  (`docker compose run --rm --no-deps <app> bundle update ...`). The
  checkout is bind-mounted, so the lockfile write lands in the repo.
- Rebuild the affected image(s) after the lockfile changes, before running
  the audit or a suite locally (`docker compose build <app>`). An
  unchanged image still carries the previous gems and bundler raises
  `Could not find <gem> in locally installed gems`.
- Scope the update to the gems being patched:
  `bundle update --conservative <gem> [<gem> ...]`.
- Inspect the lockfile diff afterwards: the intended gems move, nothing
  else drifts.
- Re-run the audit and `bin/brakeman` in **both** apps after a patch —
  every blocking linter that reads `Gemfile.lock` must stay green
  (`brakeman` derives its `EOLRails` finding from the lockfile).
- When an advisory's fix is unreachable because another dependency caps
  the gem below it, move that dependency too instead of reaching for an
  ignore entry.
- Run the audit the way CI does, through the CI compose override, in both
  apps.

### SHOULD

- Take the version the resolver selects inside the declared constraints,
  rather than pinning a transitive gem into the `Gemfile` to force a
  particular one — a pin we add is a constraint we then maintain.
- Stay on the declared line. A security patch does not widen a constraint
  to chase a fix (`~> 7.2.0`, `~> 2.3`). If the fix needs a new major,
  that is a separate, planned upgrade.
- Patch dev- and test-only gems as well (`yard`, reached through
  `tapioca` → `yard-sorbet`; `addressable`, reached through
  `capybara`/`webmock`) — the audit reports them like any other gem.
- Record the outcome where the follow-up is tracked — the `Remaining
  Issues` section of the plan that raised it.

### MUST NOT

- Don't add an `ignore:` entry to `config/bundler-audit.yml` while a
  fixed version is reachable. The list is for advisories that genuinely
  do not apply to the application — not for turning a red gate green.
- Don't widen or add a `Gemfile` constraint to make the audit pass.
- Don't run a blanket `bundle update` as a security fix. It moves
  unrelated gems: `puma` is declared `>= 5.0` with no upper bound and
  resolves to the next major, and `json` can leave the `2.x` line that
  `rubocop`'s `json (~> 2.3)` requires.
- Don't treat the advisory set as fixed. CI clones `ruby-advisory-db`
  into an ephemeral container on every run, so a later run can flag gems
  this one did not — that is a new patch task, not a reason to ignore.

## Verification

```bash
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.ci.yml"

$COMPOSE run --rm --no-deps app_fetcher bin/bundler-audit   # exit 0
$COMPOSE run --rm --no-deps app_core    bin/bundler-audit   # exit 0

$COMPOSE run --rm --no-deps app_fetcher bundle exec rspec
$COMPOSE run --rm --no-deps app_core    bundle exec rspec
$COMPOSE run --rm --no-deps app_core    npm run test:coverage

$COMPOSE run --rm --no-deps app_fetcher bin/brakeman --no-pager
$COMPOSE run --rm --no-deps app_core    bin/brakeman --no-pager
```

- The audit's own exit code is the acceptance test. No spec asserts
  dependency versions and none should: a lockfile patch changes no
  behavior, and the existing suites are the regression net for the gems
  the apps actually exercise (e.g. `app_fetcher`'s Steam client and
  `lib/faraday/user_agent_rotator.rb` use `faraday` directly).
- A patched gem with no test coverage needs a manual smoke check
  instead — load the path that uses it. `rack-proxy` is the standing
  example: only `vite_ruby`'s development proxy reaches it, and nothing
  in the suite does.

## Interaction With Other Layers

```text
Gemfile                (declared constraints)
    ↓ bundle update --conservative <gems>, run in a container
Gemfile.lock           (resolved graph — the artifact a patch changes)
    ↓ docker compose build   (RUN bundle install bakes the gems)
image                  ← what actually runs locally and in CI
    ↓
.github/workflows/ci.yml   → linters job: bin/bundler-audit (blocking)
<app>/config/ci.rb         → the same step locally, via bin/ci

config/bundler-audit.yml   → consulted by bin/bundler-audit; stays empty
```

## Canonical Implementations

- `app_fetcher/Gemfile.lock`, `app_core/Gemfile.lock` — the resolved
  graphs; their diff is the change.
- `app_fetcher/bin/bundler-audit`, `app_core/bin/bundler-audit` — the
  wrappers that add `--config config/bundler-audit.yml`.
- `app_fetcher/config/bundler-audit.yml`, `app_core/config/bundler-audit.yml`
  — the ignore lists, each holding only the inert placeholder entry.
- `app_fetcher/Dockerfile`, `app_core/Dockerfile` — `COPY Gemfile*` +
  `RUN bundle install`, the reason an image rebuild is required.
- `agent/plans/patch-vulnerable-gems.md` — the worked example of a scoped
  advisory patch across both apps.
- The Brakeman refresh (commit `decb749`) — a single pinned-gem update
  where the "rebuild before re-running" rule was found the hard way.
