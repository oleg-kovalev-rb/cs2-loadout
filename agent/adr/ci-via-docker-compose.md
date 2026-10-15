# CI Runs Through Docker Compose, with Coverage via Codecov

## Status

Accepted

## Context

The monorepo holds two Rails apps (`app_fetcher`, `app_core`) that share
one runtime: Postgres (`db_core`, `db_fetcher`, referenced by each app's
`config/database.yml`), Redis, and a set of bridge-secret/origin env
vars, all declared in `docker-compose.yml`. Every app's test suite and
linters need exactly that runtime to run.

CI today does not run at all: the Rails-generated workflows live at
`app_core/.github/workflows/ci.yml` and `app_fetcher/.github/workflows/ci.yml`,
but GitHub only reads `<repo-root>/.github/workflows/`. Those files are
dead. They also contain steps that don't fit the apps (`bin/importmap
audit` with no `bin/importmap`; a `test`/`test:system` job with no
`test/` directory — the suites are RSpec + vitest).

The repo is public, so GitHub Actions minutes and Codecov are free for
it. GitHub Actions has no native equivalent of GitLab's `coverage:`
regex: a coverage percentage in a PR requires a service.

## Decision

CI config lives **only** at the repository root, in
`.github/workflows/ci.yml`.

The pipeline runs **through docker compose**, not on bare GitHub Actions
runners. A dedicated `docker-compose.ci.yml` override adds healthchecks
(`db_core`, `db_fetcher`, `redis`), sets `CI=1`, and gives `app_core` an
anonymous `/app/node_modules` volume so the bind-mounted source (which
Compose merges and cannot remove) doesn't shadow the image's
`node_modules`. Each check is invoked as
`docker compose ... run --rm <service> <command>`.

The workflow has three jobs: **`linters`** and **`tests`** (both
blocking) and a non-blocking **`coverage`** job. Coverage is reported by
uploading SimpleCov/vitest cobertura output to **Codecov** with
per-stack flags, so the percentage and an informational status appear on
the PR.

## Alternatives Considered

### Alternative: Bare GitHub Actions runners with `services:` (the generated templates' shape)

Use `ruby/setup-ruby`, a `postgres` service, a `redis` service, and
`setup-node` directly on the runner, as the generated per-app workflows
attempted.

Rejected because:

- It re-declares the Postgres/Redis/env stack that `docker-compose.yml`
  already defines, so the CI environment and the dev environment drift
  independently — a compose change (a new env var, a new service) doesn't
  propagate to CI.
- It duplicates the same Ruby/Node setup and package-install steps across
  two apps' jobs, all of which the Dockerfiles already encode.

### Alternative: One job that runs every check sequentially

A single `test` job running linters then both test suites.

Rejected because:

- It loses fast failure and the linters/tests split the project asked
  for: a style failure shouldn't wait behind both full suites, and the
  two stages should surface as distinct checks.

### Alternative: Coverage as a job-summary/PR-comment without a service

Write the percentage to `$GITHUB_STEP_SUMMARY` and/or post it as a PR
comment via a third-party action.

Rejected because:

- It's the closest GitHub-native option, but it doesn't give the
  GitLab-like persistent percentage/status the project wants.
- Codecov is free for this public repo and provides the status and
  comment natively, so the zero-account option isn't worth the weaker
  result here.

### Alternative: Coveralls instead of Codecov

Rejected because:

- Coveralls is only weakly free (a single private repo on the paid tier),
  whereas Codecov is free for open source / limited private tiers and
  offers more configurable status checks and patch-coverage.

## Consequences

### Positive

- One runtime definition (`docker-compose.yml`) is the single source of
  truth for both dev and CI, so a service/env change reaches CI for free.
- Each app's Docker image is the CI harness — no per-app CI scaffolding
  to keep in sync when an app is added or changed.
- The root workflow is the only CI config; adding a third app means
  adding a compose service and a job step, not a new `.github/`.
- Fast-fail and clear check names via the two-stage split.

### Negative

- CI is heavier than bare runners: each job builds the app images
  (gems + npm) before running anything.
- Docker (and the compose stack) is now required not just for dev but for
  the git `pre-commit` hook, which invokes the same containers.
- The compose override must be maintained — the anonymous
  `/app/node_modules` volume is load-bearing: without it the bind-mounted
  source shadows the image's `node_modules` and `vitest`/`eslint` break.

### Risks

- Image build time/flakiness on CI runners; mitigable later with a buildx
  layer cache.
- If any check is run against the base compose (bind mounts) instead of
  `docker-compose.ci.yml`, the mounted source shadows the image's
  `node_modules` and vitest/ESLint fail. All CI invocations must use the
  override.
- Making `srb tc` blocking requires the apps to be green first — several
  pre-existing `srb tc` errors (`agent/styleguides/fix_me.md`) must be
  fixed before the linter job can pass.
- Codecov is an external dependency; the coverage job is non-blocking so
  an outage cannot fail CI, but the PR percentage is unavailable during
  one.

## Implementation Constraints

- CI config exists only at `.github/workflows/`; per-app `.github/`
  directories must not be reintroduced.
- `docker-compose.ci.yml` adds healthchecks to `db_core`/`db_fetcher`/
  `redis` (gating `up --wait`), gives `app_core` an anonymous
  `/app/node_modules` volume, and sets `CI=1` (matched by
  `config/environments/test.rb`'s `eager_load = ENV["CI"].present?`).
  Note Compose **merges** `volumes` across files, so the base source bind
  mount cannot be removed — the anonymous volume is what protects
  `node_modules`.
- The workflow supplies dummy non-empty values for the compose-
  interpolated env (`APP_BRIDGE_JWT_SECRET`,
  `APP_ADMIN_BRIDGE_JWT_SECRET`, `APP_FETCHER_PUBLIC_URL`,
  `APP_CORE_ORIGIN`) via its `env:` block — no committed secrets, no
  CI-specific `.env`.
- Blocking checks — `linters`: `rubocop`, `srb tc`, `brakeman`,
  `bundler-audit` (both apps), `eslint`, `prettier --check` (`app_core`);
  `tests`: `rspec` (both apps), `vitest` (`app_core`).
- Coverage is never a required status; `codecov.yml` marks it
  informational and lists the ignored paths.
- Each app's `bin/ci` / `config/ci.rb` stays the local equivalent of CI
  and must be extended alongside it (adding `srb tc`, frontend
  lint/format, and coverage), so a green local `bin/ci` predicts a green
  CI.

## Related

- `agent/styleguides/ci-and-coverage.md` — the "how" companion to this
  "why"
- `agent/adr/git-hooks-with-lefthook.md` — the local pre-commit half of
  the same automated-checks story
- `agent/plans/add-ci-and-git-hooks.md` — the plan that surfaced this
  decision
- `.github/workflows/ci.yml`, `docker-compose.ci.yml`, `codecov.yml`
