---
description: Root CI/CD conventions for the monorepo — where CI config lives, the linters/tests/coverage job split, running checks through docker compose, build caching, and coverage reporting via Codecov.
---

# CI & Coverage

## Purpose

The one place that governs the monorepo's automated verification: where
CI config lives, how it provisions the runtime, which checks block a
change, and how coverage is reported. It replaces the per-app
Rails-generated workflows, which never ran.

See `agent/adr/ci-via-docker-compose.md` for why CI runs through docker
compose rather than bare runners.

## When to Use

Applies to any change to the repo's automated verification:

- adding/removing a CI job or step;
- changing which linter or test suite is blocking;
- changing how CI provisions Postgres/Redis/env;
- changing coverage reporting.

Does not apply to an individual app's own local `bin/ci` step ordering or
its `.rubocop.yml` contents (the app's own config) — though `bin/ci`
should stay aligned with what CI runs (see Rules).

## Structure

- **CI config lives only at the repo root:** `.github/workflows/`.
  GitHub reads no other location — a workflow under `app_core/.github/`
  or `app_fetcher/.github/` is dead config and must not be reintroduced.
- Three jobs, as `jobs:` keys: `linters`, `tests`, and `coverage`.
- The runtime is `docker-compose.yml` (base) plus `docker-compose.ci.yml`
  (CI override). CI never runs on bare runners.
- `codecov.yml` at the root configures coverage reporting.
- Each app keeps `bin/ci` + `config/ci.rb` as its local "run everything"
  entry point.

## Interface

`docker-compose.ci.yml` is an *override*, applied as
`docker compose -f docker-compose.yml -f docker-compose.ci.yml ...`. It
must be used for every CI and local-equivalent invocation; the base file
alone is a development-only variant (see Rules → MUST NOT).

## Rules

### MUST

- Put every CI workflow at the repo root (`.github/workflows/`). Add no
  new `.github/` under an app.
- Run CI through docker compose, using the `docker-compose.ci.yml`
  override on every `docker compose` call.
- Keep exactly two blocking jobs — `linters` and `tests` — and one
  non-blocking `coverage` job.
- `linters` runs, for **both** apps: `rubocop`, `srb tc`, `brakeman`,
  `bundler-audit`; and for `app_core` additionally `eslint` and
  `prettier --check`.
- Keep a disabled Brakeman check narrow and per-app: disable it in that
  app's `config/brakeman.yml` via `skip_checks`, never with
  `--no-exit-on-warn` (which unblocks *every* warning, not one check).
  Only disable a check no code change can clear, name it by its class
  (`CheckEOLRails` — not the `EOLRails` display name the report prints),
  and leave the reason — and what removes it — in the file.
- `tests` runs `rspec` for **both** apps and `vitest` for `app_core`.
- In `docker-compose.ci.yml`, give each app with a Node toolchain
  (`app_core`) an anonymous `/app/node_modules` volume, so the base source
  bind mount (which Compose merges and cannot remove) doesn't shadow the
  image's `node_modules`. The source stays bind-mounted: the container runs
  the checkout, and coverage output lands on the runner.
- Add healthchecks to `db_core`, `db_fetcher`, and `redis`, and gate the
  app services' `depends_on` on those healthchecks, so a test run can't
  race database startup.
- Supply dummy non-empty values for every compose-interpolated env var
  (`APP_BRIDGE_JWT_SECRET`, `APP_ADMIN_BRIDGE_JWT_SECRET`,
  `APP_FETCHER_PUBLIC_URL`, `APP_CORE_ORIGIN`) via the workflow's `env:`
  block — never commit secrets and never add a CI-only `.env`.
- Trigger on `pull_request` and `push` to `main`; add a `concurrency`
  group that cancels superseded runs on the same ref.

### SHOULD

- Cache docker build layers (buildx) and the RuboCop cache to keep the
  image-build cost from dominating job time.
- Keep each app's `bin/ci` equal to the set of checks CI runs for that
  app, so a green local `bin/ci` predicts a green CI.
- Keep a check's configuration in the app/tool (e.g. `.rubocop.yml`,
  `eslint.config.js`) — see `agent/styleguides/git-commits.md`'s
  `Tooling` tag — and only the *invocation* in CI — see the `CI/CD` tag.

### MUST NOT

- Don't run a CI check against the base `docker-compose.yml`
  (bind mounts): the mounted source shadows the image's `node_modules`
  and breaks `vitest`/`eslint`/`prettier`. (The `pre-commit` hook is the
  deliberate exception — it *must* see the working tree; see
  `agent/styleguides/git-hooks.md`.)
- Don't pass `--ensure-latest` to Brakeman (Rails' `bin/brakeman`
  generator adds it by default): the flag fails the run whenever upstream
  releases a new Brakeman, independent of our code, which is a red CI we
  cannot fix on our side. The scanner version is pinned by
  `Gemfile.lock` instead — refresh it with `bundle update brakeman` in
  each app.
- Don't make `coverage` a blocking or required status check.
- Don't re-declare the Ruby/Node/Postgres/Redis setup inline in the
  workflow — it belongs in the Dockerfiles and `docker-compose.ci.yml`.
- Don't add a per-app `.github/` or a second CI system alongside the
  root workflow.

## Coverage

- Ruby: `simplecov` + `simplecov-cobertura` in each app's `test` group,
  started in `spec_helper.rb` only when `ENV["COVERAGE"]` is set (so
  normal local runs aren't slowed), producing cobertura XML under
  `coverage/`.
- Frontend: `@vitest/coverage-v8`, configured in `vite.config.ts`, with
  the cobertura reporter writing to a separate reports directory.
- The `coverage` job downloads both reports and uploads them to Codecov
  with per-stack flags (`app_fetcher`, `app_core`, `frontend`).
- `codecov.yml` marks the status **informational** so coverage never
  blocks a merge, and lists ignored paths.
- `CODECOV_TOKEN` is optional for this public repo but is set as a
  fallback secret.

## Interaction With Other Layers

```text
push / pull_request
    ↓
.github/workflows/ci.yml  (root only)
    ↓ docker compose -f docker-compose.yml -f docker-compose.ci.yml
    ├── linters  → run --rm app_fetcher/app_core  rubocop | srb tc | brakeman | bundler-audit | eslint | prettier
    ├── tests    → run --rm app_fetcher/app_core  rspec | (app_core) npm run test:coverage
    └── coverage → Codecov upload (flags: app_fetcher, app_core, frontend)
```

## Canonical Implementations

- `.github/workflows/ci.yml` — the root workflow (linters/tests/coverage)
- `docker-compose.ci.yml` — the CI override
- `codecov.yml` — coverage reporting config
- `app_fetcher/config/ci.rb`, `app_core/config/ci.rb` — each app's local
  equivalent
- `app_fetcher/bin/brakeman`, `app_core/bin/brakeman` — the Brakeman
  wrappers CI calls; no `--ensure-latest` (see Rules → MUST NOT)
- `app_fetcher/config/brakeman.yml`, `app_core/config/brakeman.yml` — the
  per-app Brakeman config, incl. any `skip_checks` (see Rules → MUST)

## Related ADR

- `agent/adr/ci-via-docker-compose.md` — why CI runs through docker
  compose and why Codecov, rather than bare runners / no service.
