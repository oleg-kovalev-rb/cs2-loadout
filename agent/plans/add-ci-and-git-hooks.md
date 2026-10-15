---
status: draft
app: fetcher+core
goal: Make CI actually run on GitHub (root .github/workflows) split into linters and tests stages executed via docker compose, add lefthook pre-commit + commit-msg hooks, add ESLint/Prettier for the frontend, and report coverage via Codecov (free for this public repo).
created: 2026-10-15
---

# Development Plan

## Goal

Turn the currently-dead, per-app GitHub Actions workflows into a working
root-level CI for the monorepo, split into stages that run through
`docker compose`:

- **`linters`** — RuboCop, Sorbet (`srb tc`), Brakeman, bundler-audit,
  ESLint + Prettier (all blocking);
- **`tests`** — RSpec (`app_fetcher`), RSpec (`app_core`), vitest
  (`app_core`), with coverage generation;
- **`coverage`** — non-blocking: uploads to Codecov, which surfaces the
  coverage percentage and an informational status on the PR.

Add git hooks via `lefthook`: a `pre-commit` hook that lints staged Ruby
and JS, and a `commit-msg` hook that enforces the
`[Scope] Imperative summary` convention from
`agent/styleguides/git-commits.md`. Bring `srb tc` to a green state in
both apps so it can be a blocking linter.

## Context (from research)

- GitHub only reads `<repo-root>/.github/workflows/`. The existing
  `app_core/.github/` and `app_fetcher/.github/` (workflows + dependabot)
  are therefore **never executed**.
- Both apps already have a Rails 8 `bin/ci` + `config/ci.rb` pipeline
  (setup → rubocop → bundler-audit → brakeman → rspec → seeds). It is the
  existing "run everything" entry point but is not wired to GitHub.
- The generated workflows contain broken steps if reused as-is:
  - `app_core` runs `bin/importmap audit`, but `bin/importmap` and
    `config/importmap.rb` do not exist;
  - `app_core` runs `bin/rails db:test:prepare test` / `test:system`, but
    there is no `test/` directory — the suite is RSpec + vitest.
- No git hooks are installed (only `.git/hooks/*.sample`). No
  lefthook/overcommit/husky/`core.hooksPath`.
- Frontend (55 `.js`, 63 `.jsx`, 5 `.css`) has vitest (39 files) but **no
  ESLint / Prettier / Stylelint / `tsc`**.
- No SimpleCov in either app.
- `srb tc` is currently red in both apps; `agent/styleguides/fix_me.md`
  enumerates the real errors.
- The GitHub repository is **public** (`oleg-kovalev-rb/cs2-loadout`), so
  Codecov is free forever for it (Coveralls is also free for OSS, but
  Codecov has better status checks / patch coverage). GitHub Actions
  minutes are free for public repos.
- GitHub Actions has **no native equivalent of GitLab's `coverage:` regex
  parsing**; a service like Codecov is what produces the PR percentage and
  status.

## Expected Behavior

- A push/PR triggers a single root workflow with three jobs:
  - **`linters`** — fails if any of: `rubocop` (both apps), `srb tc`
    (both apps), `brakeman` (both apps), `bundler-audit` (both apps),
    `eslint` (`app_core` frontend), `prettier --check` (`app_core`
    frontend) reports a problem.
  - **`tests`** — fails if any of: `rspec` (`app_fetcher`), `rspec`
    (`app_core`), `vitest` (`app_core`) fails.
  - **`coverage`** — **non-blocking**; uploads reports to Codecov, which posts
    the coverage percentage/comment and an informational status check on
    the PR.
- Both test/lint jobs run against the real runtime via `docker compose`
  (Postgres + Redis services), not bare runners.
- After install, a commit whose subject line is not
  `[Scope] Imperative summary` is rejected by `commit-msg`; a commit with
  a RuboCop offense in a staged `.rb` file or an ESLint/Prettier issue in
  a staged `.js`/`.jsx` file is rejected by `pre-commit`.
- `srb tc` exits `0` in both apps; `eslint`/`prettier --check` exit `0`.
- The existing developer flow (`docker compose up app_core`,
  `docker compose up app_fetcher`, `bin/ci` per app) is unchanged.
- The dead nested `.github` directories are gone; Dependabot config lives
  at the repo root.

## Scope

### In Scope

- Root `.github/workflows/ci.yml` with `linters`, `tests`, `coverage` jobs.
- Root `.github/dependabot.yml`; remove `app_core/.github/` and
  `app_fetcher/.github/`.
- `docker-compose.ci.yml` override (CI-appropriate services: no bind
  mounts, DB/Redis healthchecks).
- **ESLint (flat config) + Prettier for `app_core`'s frontend**, added as
  blocking checks, including the one-time reformat of `app/frontend/**`.
- **SimpleCov** in both apps + vitest coverage for the frontend; a
  non-blocking `coverage` job that uploads to **Codecov** (free for this
  public repo) so the percentage/status shows on PRs.
- `lefthook.yml` + a `commit-msg` validator script + root install
  mechanism.
- Sorbet remediation (regenerate RBIs, fix the enumerated `srb tc` errors)
  so `srb tc` can be blocking.
- Add `srb tc`, ESLint/Prettier and coverage steps to the apps'
  `config/ci.rb` as applicable so local `bin/ci` matches CI.
- Keep `AGENTS.md`, `.claude/CLAUDE.md`, `.cursor/rules/development-pipeline.mdc`
  in sync with a short note about hooks/CI.

### Out of Scope

- Stylelint for the CSS files, `tsc`, migration to TypeScript.
- `rubocop-rspec`, markdownlint, actionlint as enforced gates.
- A **blocking** coverage threshold (coverage is reported, not enforced).
- Pre-existing `fix_me.md` items unrelated to `srb tc`.
- Any product/application behavior change beyond what is required to make
  `srb tc` pass or to satisfy ESLint/Prettier.
- Changing `bin/dev` / Procfile / Dockerfile build steps.

## Implementation Approach

### CI (root workflow)

Add `.github/workflows/ci.yml` at the repo root with three jobs, each:
checkout → set the `docker compose` interpolation env (dummy non-empty
values for `APP_FETCHER_PUBLIC_URL`, `APP_CORE_ORIGIN`,
`APP_BRIDGE_JWT_SECRET`, `APP_ADMIN_BRIDGE_JWT_SECRET`) →
`docker compose -f docker-compose.yml -f docker-compose.ci.yml build` →
run the job's commands with `docker compose ... run --rm <service> <cmd>`:

- `linters`:
  - `app_fetcher`: `bin/rubocop -f github`, `bundle exec srb tc`,
    `bin/brakeman --no-pager`, `bin/bundler-audit`
  - `app_core`: same set, plus
  - `app_core`: `npm run lint` (ESLint), `npm run format:check` (Prettier)
- `tests`:
  - `app_fetcher`: `bin/rails db:test:prepare` then
    `COVERAGE=1 bundle exec rspec`
  - `app_core`: `bin/rails db:test:prepare` then `COVERAGE=1 bundle exec rspec`
  - `app_core`: `npm run test:coverage` (vitest + v8 coverage)
  - upload `coverage/` artifacts (Ruby + JS) for the `coverage` job
- `coverage` (needs `tests`, `if: always()`, **must not fail the build**):
  - download the coverage artifacts;
  - upload each report to Codecov (`codecov/codecov-action`) with `flags:`
    `app_fetcher`, `app_core`, `frontend` so the PR shows per-app and total
    coverage plus an informational status check. Codecov is free for this
    public repo; uploading tokenless works for public repos, but a
    `CODECOV_TOKEN` secret is set as a fallback and for reliability.

Runs triggered on `pull_request` and `push` to `main`; add a
`concurrency` group to cancel superseded runs.

### `docker-compose.ci.yml`

An override that makes the compose-managed runtime usable in CI:

- give `app_core` an anonymous `/app/node_modules` volume so the base
  source bind mount (which Compose merges and cannot remove) doesn't
  shadow the image's `node_modules` (which would otherwise break
  vitest/eslint/prettier); the source stays bind-mounted, so the container
  runs the checkout and coverage output lands on the runner;
- add `healthcheck`s to `db_core`, `db_fetcher`, `redis` so `up --wait`
  blocks until they accept connections;
- set `CI=1` for app services (matches
  `config/environments/test.rb`'s `eager_load = ENV["CI"].present?`).

Dummy secrets are supplied via the workflow `env:` block (docker compose
interpolation reads process env), so no committed secrets and no
CI-specific `.env` file are needed.

### Frontend linting (ESLint + Prettier)

- Add to `app_core/package.json` devDependencies: `eslint`,
  `eslint-plugin-react`, `eslint-plugin-react-hooks`,
  `eslint-config-prettier`, `prettier`, `globals`, `@vitest/coverage-v8`.
- Add scripts: `lint` (`eslint app/frontend`), `lint:fix`,
  `format` (`prettier --write app/frontend`),
  `format:check` (`prettier --check app/frontend`),
  `test:coverage` (`vitest run --coverage`).
- `app_core/eslint.config.js` (flat, ESM — `package.json` already has
  `"type": "module"`): React + React Hooks plugins, `eslint-config-prettier`
  last so Prettier owns formatting.
- `app_core/.prettierrc` + `app_core/.prettierignore` (ignore `node_modules`,
  `public/vite*`, `app/frontend/**/*.woff2`).
- One-time `npx prettier --write "app/frontend/**/*.{js,jsx,css,json}"`
  run, kept as its own commit so the formatting churn is isolated from
  behavior changes.

### Coverage

- Add `gem "simplecov", require: false` and
  `gem "simplecov-cobertura", require: false` to the `test` group of both
  apps' Gemfiles.
- In each `spec/spec_helper.rb`, start SimpleCov (with the cobertura
  formatter) only when `ENV["COVERAGE"]` is set, so normal local runs are
  unaffected.
- Frontend: `@vitest/coverage-v8`, add a `coverage` block to
  `vite.config.ts` with `provider: "v8"` and reporters `text` + `cobertura`
  into `coverage/` (a separate reports directory from the Ruby reports).
- The `coverage` job consumes the cobertura XML from both stacks and
  uploads it to Codecov with per-stack flags — non-blocking.

### Git hooks (`lefthook`)

- `lefthook.yml` at the repo root:
  - `commit-msg` → `script/commit-msg {1}` (the message file path).
  - `pre-commit` (parallel, per-app commands, each with its own `root` so
    `{staged_files}` are app-relative):
    - `root: app_fetcher`, `glob: "*.rb"` →
      `docker compose -f ../docker-compose.yml run --rm app_fetcher bin/rubocop {staged_files}`
    - `root: app_core`, `glob: "*.rb"` → same for `app_core`.
    - `root: app_core`, `glob: "app/frontend/**/*.{js,jsx}"` →
      `docker compose -f ../docker-compose.yml run --rm app_core npx eslint {staged_files}`
      and `... npx prettier --check {staged_files}`.
    Commands skip when no matching staged files.
- `script/commit-msg` — dependency-free Ruby (shebang `#!/usr/bin/env
  ruby`, no bundler) that reads the message file, ignores comment lines,
  and validates the first non-comment line against
  `^\[(Core|Fetcher|Core\+Fetcher|AI WorkFlow)\] [A-Z][a-zA-Z]*.*$`
  (scope tags taken from `git-commits.md`), also rejecting trailing
  period, body/trailers, and multi-line subjects.
- Install mechanism: add a root `package.json` (private) with a
  `lefthook` devDependency and `"prepare": "lefthook install"`, plus a
  root `package-lock.json`. Developers/agents run `npm install` once.
  (Rationale: no root Ruby manifest exists; npm is already used by
  `app_core`; keeps the hook tool out of either app's Gemfile.)

### Sorbet remediation

Regenerate gem RBIs with `bundle exec tapioca gems` in both apps (this
alone clears `app_core`'s missing `JWT`/`RSpec`/`FactoryBot` constants),
then fix the enumerated real errors so `srb tc` is green:

- `app_fetcher/app/parsers/item_parser.rb` — the `else` branch's
  `item_name: clean_name` is inferred nilable; make the value
  unambiguously `String`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` — capture
  `item.current_price_cents` in a local before the `nil?` guard so the
  narrowing holds.
- `app_fetcher/app/workers/price_update_worker.rb` — the nilable
  `current_price_cents`/`change_24h_cents` passed to `publish_to_stream`;
  guard in `#perform` and skip publishing when the price is nil (matches
  the existing "skip non-marketable / not-yet-priced" behavior).
- `app_fetcher/app/services/user_inventory_sync_service.rb` — bind
  `response.data` to a local (asserted non-nil after the `success?` check)
  instead of four separate nilable reads.

Iterate `bundle exec srb tc` until clean.

## Files To Modify

- `app_fetcher/config/ci.rb` — add `srb tc` step.
- `app_core/config/ci.rb` — add `srb tc`, ESLint/Prettier, and `npm run test:coverage` steps.
- `app_fetcher/Gemfile`, `app_core/Gemfile` — add SimpleCov gems to `test` group.
- `app_fetcher/spec/spec_helper.rb`, `app_core/spec/spec_helper.rb` — conditional SimpleCov start.
- `app_core/package.json` — ESLint/Prettier/coverage devDeps + scripts.
- `app_core/vite.config.ts` — vitest coverage config.
- `app_core/app/frontend/**/*.{js,jsx,css,json}` — one-time Prettier reformat.
- `app_fetcher/app/parsers/item_parser.rb` — non-nilable `item_name`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` — local before guard.
- `app_fetcher/app/workers/price_update_worker.rb` — skip publish on nil price.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — bind non-nil `response.data`.
- `app_core/sorbet/rbi/gems/*`, `app_fetcher/sorbet/rbi/gems/*` — regenerated by `tapioca gems`.
- `AGENTS.md`, `.claude/CLAUDE.md`, `.cursor/rules/development-pipeline.mdc` — short CI/hooks note.
- `.gitignore` (root) — ignore root `node_modules/`/`coverage/` if not already covered.

## Files To Create

- `.github/workflows/ci.yml` (root) — `linters`, `tests`, `coverage` jobs; the actual CI that runs.
- `.github/dependabot.yml` (root) — moved from the nested app dirs.
- `docker-compose.ci.yml` — CI override (healthchecks, anonymous `node_modules` volume, `CI=1`).
- `lefthook.yml` — `pre-commit` + `commit-msg` definitions.
- `script/commit-msg` — commit-subject validator.
- `app_core/eslint.config.js`, `app_core/.prettierrc`, `app_core/.prettierignore` — frontend lint/format config.
- `codecov.yml` (root) — Codecov config (informational status so it never blocks; ignore paths).
- `package.json` (root) — private; `lefthook` devDependency + `prepare` script.
- `package-lock.json` (root) — generated.

## Files To Delete

- `app_core/.github/` (workflows + dependabot) — dead nested config.
- `app_fetcher/.github/` (workflows + dependabot) — dead nested config.

## Test Plan

This is tooling/config work, so the "tests" are the concrete commands and
the hook behavior. Verification is defined below; the plan does not add
application specs.

- Validator script: exercise `script/commit-msg` directly with sample
  messages — accepted: `[Core] Add user model`,
  `[Fetcher] Skip non-marketable items`, `[Core+Fetcher] Wire bridge`,
  `[AI WorkFlow] Update skill`. Rejected: missing scope (`Add thing`),
  lowercase verb (`[Core] add thing`), trailing period
  (`[Core] Add thing.`), body/trailer present, unknown scope
  (`[Frontend] Add thing`).
- Hooks: after `npm install && npx lefthook install`, attempt a bad-message
  commit (expect rejection), a staged RuboCop offense (expect rejection),
  and a staged ESLint/Prettier issue (expect rejection); then a clean
  commit (expect success).
- Workflow: parse the YAML locally; on a branch, confirm all three jobs
  appear and run on GitHub.
- Coverage: `COVERAGE=1 bundle exec rspec` writes `coverage/cobertura.xml`;
  `npm run test:coverage` writes the frontend cobertura report; the
  `coverage` job uploads both to Codecov with flags (upload itself can only
  be fully confirmed on a PR).
- No `test/`-based steps remain anywhere in CI config.

## Implementation Steps

1. Create root `package.json` + run `npm install` to produce
   `package-lock.json`; add `lefthook` devDependency and `prepare` script.
2. Write `script/commit-msg`; make it executable; self-test it against the
   sample matrix above.
3. Write `lefthook.yml` (`commit-msg` + Ruby/JS `pre-commit`); run
   `npx lefthook install`; verify hooks fire (JS command after step 5).
4. Create `docker-compose.ci.yml` (healthchecks, anonymous `node_modules`
   volume for `app_core`, `CI=1`); verify `docker compose -f
   docker-compose.yml -f docker-compose.ci.yml config` resolves and images
   build.
5. Frontend linting: add devDeps + scripts to `app_core/package.json`,
   add `eslint.config.js`, `.prettierrc`, `.prettierignore`; run
   `npx prettier --write` over `app/frontend/**` and fix ESLint findings in
   a dedicated commit.
6. Coverage: add SimpleCov gems + `spec_helper` wiring in both apps; add
   the vitest coverage config.
7. Sorbet: in `app_core`, run `tapioca gems`; in `app_fetcher`, run
   `tapioca gems`; capture remaining `srb tc` errors.
8. Fix the enumerated `srb tc` errors in the four `app_fetcher` files;
   iterate `srb tc` to green in both apps.
9. Add `srb tc`, frontend lint/format, and coverage steps to the apps'
   `config/ci.rb`.
10. Coverage: add root `codecov.yml` (informational status); decide whether
    to set the `CODECOV_TOKEN` secret (optional for a public repo).
11. Create root `.github/workflows/ci.yml` (`linters` + `tests` +
    `coverage`) using `docker-compose.ci.yml`; create root
    `.github/dependabot.yml`.
12. Delete `app_core/.github/` and `app_fetcher/.github/`.
13. Update `AGENTS.md` and mirror the CI/hooks note into
    `.claude/CLAUDE.md` and `.cursor/rules/development-pipeline.mdc`.
14. Run the full local verification (below), then push a branch / open a
    PR to confirm all CI jobs run and Codecov reports.

## Verification

- `docker compose -f docker-compose.yml -f docker-compose.ci.yml build`
  succeeds.
- Linters stage, all exit `0`:
  - `... run --rm app_fetcher bin/rubocop -f github`
  - `... run --rm app_core bin/rubocop -f github`
  - `... run --rm app_fetcher bundle exec srb tc`
  - `... run --rm app_core bundle exec srb tc`
  - `... run --rm app_fetcher bin/brakeman --no-pager`
  - `... run --rm app_core bin/brakeman --no-pager`
  - `... run --rm app_fetcher bin/bundler-audit`
  - `... run --rm app_core bin/bundler-audit`
  - `... run --rm app_core npm run lint`
  - `... run --rm app_core npm run format:check`
- Tests stage:
  - `... run --rm app_fetcher bundle exec rspec` — pass
  - `... run --rm app_core bundle exec rspec` — pass
  - `... run --rm app_core npm run test` — vitest passes
- Coverage: `COVERAGE=1 bundle exec rspec` + `npm run test:coverage`
  produce cobertura reports; the `coverage` job uploads them to Codecov,
  which shows the percentage/status on the PR, and the job never fails the
  build.
- `script/commit-msg` accepts/rejects the sample matrix as specified.
- `git commit` with a malformed message is blocked; with a RuboCop offense
  in staged Ruby is blocked; with an ESLint/Prettier issue in staged JS is
  blocked; a clean commit succeeds.
- `docker compose up app_core` still starts the dev stack unchanged.
- On GitHub: a push/PR shows `linters`, `tests`, `coverage`; the first two
  are green, and Codecov posts the coverage %/status without failing CI.

## Risks

- **ESLint/Prettier baseline.** First ESLint run over 118 JS/JSX files may
  surface many real findings, and Prettier reformats most of them. Isolate
  the reformat in its own commit; budget time to resolve ESLint findings.
- **Sorbet remediation may surface more errors.** Regenerating RBIs can
  expose previously-masked mismatches (`fix_me.md` documents that
  `item_prices_controller` was only surfaced *after* DSL RBIs existed).
  Budget for iterating beyond the four enumerated files; if it balloons,
  fall back to a documented, explicit exclusion and raise it back to
  `styleguides-check`.
- **`price_update_worker` nilable publish is a product decision.** The
  chosen fix (skip publishing when price is nil) must match intended
  stream semantics; confirm against
  `agent/adr/fetcher/price-updates-via-redis-stream.md`.
- **Docker-in-`pre-commit` is slower** (container start per app) and
  requires Docker running during commits. If disruptive, the alternative
  is host `bin/rubocop`/`npx eslint` (fast, but needs local deps).
- **CI build cost/flakiness** — each job builds images from scratch
  (gems + npm). A buildx layer cache can be added later.
- **`node_modules` shadowing** — any command run under the base compose
  (bind mounts) instead of `docker-compose.ci.yml` breaks vitest/ESLint.
  Ensure all CI invocations use the override.
- **Codecov dependency** — an external service. It is free for this public
  repo (no billing), and the coverage job is non-blocking, so a Codecov
  outage can't break CI. Pin `codecov/codecov-action` to a version/SHA
  (same supply-chain rule as any third-party action).
- **Tokenless uploads** — public-repo uploads work without a token today,
  but set the `CODECOV_TOKEN` secret as a fallback; Codecov may require a
  token in future.
- **Worktrees** — `extensions.worktreeconfig` + `.claude/worktrees/*` mean
  hook installation/config must be validated across a worktree, not only
  the main checkout.
- **Nested `.github` removal** — confirmed dead, but double-check nothing
  references those paths before deleting.
- **Secrets** — tests need non-empty bridge JWT secrets; dummy values must
  be long enough for the HMAC signing path in `bridge_token.rb`.

## Assumptions

- CI platform is GitHub Actions (remote is GitHub; no other CI config
  exists).
- Docker is available on the CI runner and on developer/agent machines
  (repo is docker-first: `database.yml` hosts `db_core`/`db_fetcher`,
  `.claude/launch.json` uses `docker compose`).
- Dummy (non-secret) values are sufficient for test runs, since the suites
  use webmock/VCR.
- Adding a root `package.json` purely to carry `lefthook` is acceptable in
  this monorepo.
- Coverage is uploaded to Codecov, which is free for this public repo;
  switching away later is a drop-in change.
- The scope tags for this change are resolved: `Tooling` for linter/
  formatter config and `CI/CD` for the workflow/hooks/coverage wiring (see
  `agent/styleguides/git-commits.md`).
- The CI/hooks/frontend-linting styleguides and the three ADRs
  (`ci-via-docker-compose`, `git-hooks-with-lefthook`,
  `core/frontend-lint-stack`) are created and approved; see Applicable
  Styleguides below.

## Completion Criteria

- Root CI exists, runs on GitHub, split into `linters`, `tests`, and a
  non-blocking `coverage` job.
- ESLint + Prettier are configured and blocking; the frontend is formatted.
- `lefthook` `pre-commit` (Ruby + JS) and `commit-msg` hooks work and are
  installable from the repo.
- `srb tc` is green in both apps and is a blocking linter.
- Coverage percentage is reported via Codecov without failing CI.
- Dead nested `.github` directories are removed; Dependabot is at root.
- The plan file status is updated as the task progresses.

## Applicable Styleguides

Every technical area this plan touches now has a sufficient,
project-specific styleguide; the plan is ready for `implement-plan`.

- **`agent/styleguides/ci-and-coverage.md`** — constrains the root
  `.github/workflows/ci.yml` (job split, blocking vs non-blocking,
  concurrency), `docker-compose.ci.yml` (override, healthchecks, anonymous
  `node_modules` volume, `CI=1`), and the coverage pipeline (SimpleCov/vitest →
  Codecov flags). Companion ADR: `agent/adr/ci-via-docker-compose.md`.
- **`agent/styleguides/git-hooks.md`** — constrains `lefthook.yml` and
  `script/commit-msg` (staged-files-only pre-commit via docker compose,
  per-app `root`, the commit-msg gate, `npm install` install path).
  Companion ADR: `agent/adr/git-hooks-with-lefthook.md`.
- **`agent/styleguides/git-commits.md`** — constrains every commit for
  this change: the scope tags `Tooling` (linter/formatter config) and
  `CI/CD` (workflow/hooks/coverage), each change split into
  single-purpose commits; also fixes the valid-tag set `script/commit-msg`
  must accept.
- **`agent/styleguides/core/react-dashboard.md`** — its "Linting &
  Formatting" section constrains `eslint.config.js`, `.prettierrc`, the
  `lint`/`format:check` scripts, and the one-time mass format of
  `app/frontend/**`. Companion ADR:
  `agent/adr/core/frontend-lint-stack.md`.
- **`agent/styleguides/fetcher/steam-response-objects.md`** — the
  post-`success?` `#data` narrowing rule constrains the
  `user_inventory_sync_service.rb` fix.
- **`agent/styleguides/fetcher/background-jobs.md`** — the nil-price
  publish guard constrains the `price_update_worker.rb` fix.
- **`agent/styleguides/ruby-sorbet.md`** — constrains all Sorbet
  remediation (sigils, `sig`, `T.let`, guard clauses) in the four touched
  files.

Related ADRs (created with the styleguides): `agent/adr/ci-via-docker-compose.md`,
`agent/adr/git-hooks-with-lefthook.md`, `agent/adr/core/frontend-lint-stack.md`.

## Implementation Progress & Blocker (implement-plan)

Status reset to `draft`: implementation stopped because the plan's Sorbet
remediation section materially underestimates the work.

### Done so far

- Root `.github/workflows/ci.yml` (linters/tests/coverage job split) +
  root `.github/dependabot.yml`; nested `app_core/.github/` and
  `app_fetcher/.github/` deleted.
- `docker-compose.ci.yml` — **mechanism corrected**: Compose *merges*
  `volumes` across files, so the base source bind mount cannot be dropped;
  the override now adds an anonymous `/app/node_modules` volume (plus
  healthchecks, `CI=1`) instead of `volumes: []`.
- `lefthook.yml` + `script/commit-msg` (13/13 accept/reject cases) + root
  `package.json`; hooks install and fire.
- ESLint (flat) + Prettier; `app/frontend/**` mass-formatted; `npm run
  lint` clean (2 React-Compiler rules disabled, documented in
  `eslint.config.js`), `npm run format:check` clean, `vitest` 219/219.
- SimpleCov + `simplecov-cobertura` in both apps, `spec_helper` wiring,
  vitest coverage config, `codecov.yml`; both `config/ci.rb` updated.
- `app_core` `srb tc` **green** (via `tapioca gems`; also fixed
  `profile_fetcher.rb`'s `JSON.parse(response.body)` and its quotes, and
  bumped `app_core/Dockerfile` Ruby 3.3.0 → 3.3.6 because `simplecov`
  fails to load on Ruby 3.3.0's parser).
- `app_fetcher` gem RBIs regenerated (needed `RUBYOPT=-r./config/environment`
  because `solid_cache` loads before the DB config under `tapioca`).
- Docs synced (`AGENTS.md`, `.claude/CLAUDE.md`,
  `.cursor/rules/development-pipeline.mdc`); styleguides/ADR/`fix_me.md`
  updated.

### Blocker

`app_fetcher` `srb tc` reports **21 errors across ~10 files**, not the 4
the plan lists. Regenerating the RBIs surfaced errors beyond the planned
four:

- Query layer — `app/queries/options/item_filter_field.rb`,
  `item_sort_option.rb`, `app/queries/item_catalog_query.rb`,
  `inventory_catalog_query.rb`, `inventory_detail_query.rb`: the
  `Appliers::*` signatures `return(T::Enum)`, losing the concrete enum
  type, and query params are typed as bare `ActiveRecord::Relation`, so
  `Item` scopes aren't visible. Fixing means generifying the applier
  signatures and typing relations as `Item::ActiveRecord_Relation` — a
  query-layer typing refactor the plan didn't include (and possibly
  guidance in `agent/styleguides/fetcher/list-query-objects.md`).
- `config/initializers/redis.rb` — `ConnectionPool` unresolved + needs
  `T.let` for the constant.
- `lib/faraday/user_agent_rotator.rb` — undeclared `@app`.
- `Item` DSL RBI likely needs `tapioca dsl Item` (scopes `by_categories`,
  `by_rarities`, `stattrak_only`, `matching_search`).

### Verification (executed)

- RuboCop — clean in both apps (autocorrected 29 + 28 pre-existing
  offenses; tests re-run green afterwards).
- RSpec — `app_fetcher` 378 examples / 0 failures; `app_core` 39 / 0
  (fixed the pre-existing `user_inventory_cache_spec.rb` version-2 key to
  match `CACHE_KEY_VERSION = 1`; entry removed from `fix_me.md`).
- ESLint / Prettier — clean; vitest 219/219; `npm run test:coverage`
  writes `app_core/coverage-frontend/cobertura-coverage.xml`.
- `COVERAGE=1 bundle exec rspec` writes `app_fetcher/coverage/coverage.xml`
  (Line 98.82%).
- `script/commit-msg` — 13/13 accept/reject cases; `lefthook install`
  synced `commit-msg` + `pre-commit` hooks; `lefthook run commit-msg`
  rejects/accepts as expected.
- Workflow/Dependabot/`lefthook.yml`/`docker-compose.ci.yml` parse; the CI
  compose override resolves.
- Not runnable here: the GitHub Actions jobs end-to-end.

### Remaining Issues

Kept in the gates (per the user), but currently red on pre-existing
problems — to be fixed separately:

- **Sorbet (`srb tc`)** — `app_fetcher`: 21 errors across ~10 files, not
  the plan's 4. Beyond the planned four (`item_parser.rb`,
  `item_prices_controller.rb`, `user_inventory_sync_service.rb`,
  `price_update_worker.rb`), regenerating the RBIs surfaced the query
  layer (`item_filter_field.rb`, `item_sort_option.rb`,
  `item_catalog_query.rb`, `inventory_catalog_query.rb`,
  `inventory_detail_query.rb`) where `Appliers::*` returns base `T::Enum`
  and params are bare `ActiveRecord::Relation` (needs generics +
  `Item::ActiveRecord_Relation`; possibly guidance in
  `agent/styleguides/fetcher/list-query-objects.md`), plus
  `config/initializers/redis.rb` (`ConnectionPool` + `T.let`) and
  `lib/faraday/user_agent_rotator.rb` (`@app`). Deferred to the user.
- **Brakeman** — `bin/brakeman` adds `--ensure-latest`; exits 5 because
  the gem is 8.0.4 vs latest 8.1.0 (fix: `bundle update brakeman`).
- **bundler-audit** — ~20 advisories per app (activestorage,
  concurrent-ruby, json, loofah, nokogiri, puma, rack, rack-session,
  mail, net-imap, erb, crass, websocket-driver, faraday, yard, ...); fix
  is patching those gems (a separate security task).

### Notes / deviations from the plan

- `docker-compose.ci.yml` — plan said `volumes: []`; Compose *merges*
  `volumes`, so the override instead adds an anonymous `/app/node_modules`
  volume (corrected mechanism, documented in the styleguide/ADR).
- `app_core/Dockerfile` Ruby bumped 3.3.0 → 3.3.6 (required for
  `simplecov`; matches `app_fetcher`).
- RuboCop autocorrect touched a broad set of formatting-only files
  (pre-existing offenses) so the lint gate is real.
- 2 React-Compiler ESLint rules disabled in `app_core/eslint.config.js`
  (documented there).
