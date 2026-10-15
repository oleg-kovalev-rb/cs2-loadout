# steam_project

Monorepo, two Rails 7.2 apps sharing a Postgres/Redis stack (see
`docker-compose.yml`):

- `app_fetcher/` — API-only service. Fetches, parses, and stores Steam
  Store/market data (items, prices) via scheduled Sidekiq jobs, exposes it
  internally over an API. Sorbet for type checking.
  - `app/parsers/` — parse raw Steam API responses;
  - `app/builders/` — build domain records from parsed data;
  - `app/workers/` — Sidekiq jobs (list/price updates);
  - `app/schedulers/` — recurring job scheduling (sidekiq-cron);
  - `app/controllers/api/` — internal API consumed by `app_core`.
- `app_core/` — user-facing app. Turbo/Stimulus + a Vite-built React
  dashboard island; consumes `app_fetcher`'s data.
  - `app/actions/` — request-scoped business logic (incl. `steam/`);
  - `app/frontend/dashboard/` — the React island;
  - `app/jobs/` — background jobs local to `app_core`.

Tests: RSpec in both apps (`app_fetcher` also uses request specs under
`spec/requests`; `app_core` mixes RSpec with minitest-based Rails defaults).

## Tool layout (OpenCode)

Shared docs live under `agent/` (ADRs, styleguides, user stories, and plans):

- skills: `.opencode/skills/`
- shared: `agent/adr/`, `agent/styleguides/`, `agent/US/`, `agent/plans/`

## CI & git hooks

- CI lives at the repo root: `.github/workflows/ci.yml` (GitHub reads no
  other location). Jobs: `linters` (RuboCop, Sorbet `srb tc`, Brakeman,
  bundler-audit, ESLint, Prettier), `tests` (RSpec ×2, Vitest), and a
  non-blocking `coverage` job (Codecov). Everything runs through
  `docker compose` via `docker-compose.ci.yml`. See
  `agent/styleguides/ci-and-coverage.md`.
- Git hooks use `lefthook`: run `npm install` once at the repo root (its
  `prepare` script runs `lefthook install`). `pre-commit` lints staged
  Ruby/JS; `commit-msg` enforces the `[Scope] Imperative summary`
  convention. See `agent/styleguides/git-hooks.md`.
- Each app's `bin/ci` is the local equivalent of CI — keep it aligned.

## Development pipeline

For any non-trivial change (new behavior, bug fix touching business logic,
new integration — not one-line fixes or pure formatting), follow this order:

1. `research-codebase` — understand current behavior, relevant files, tests.
2. `create-dev-plan` — turn research into a concrete plan.
3. `styleguides-check` — gate the plan against styleguides; if a guide is
   missing entirely, create it (`create-styleguide` /
   `create-styleguide-from-scratch`); if a guide already exists and applies
   but doesn't cover a case the plan needs, amend it (`update-styleguide`)
   — before moving on.
4. `implement-plan` — implement with TDD, following the checked plan.

Do not jump straight to implementation for non-trivial work. If a stage
surfaces a contradiction with an earlier stage, stop and go back to that
stage rather than improvising.

`create-dev-plan` writes the plan to `agent/plans/<slug>.md`, committed
to the repo, so it survives a new session or context compaction and stays
visible to the rest of the team. `styleguides-check` and `implement-plan`
read and update that same file in place — check its `status` frontmatter
field (`draft` → `blocked`/`styleguide-checked` → `implemented`) to see
where a task currently stands before resuming work on it.

## Styleguides and ADRs: shared vs per-app

Both live under `agent/`, split by scope:

- `agent/styleguides/base.md`, `agent/adr/base.md` — format templates,
  used everywhere.
- `agent/styleguides/*.md` (directly under `styleguides/`, not in a
  per-app folder) — conventions that apply identically to every app: Ruby
  style, git conventions, cross-app Rails/testing conventions. See
  `agent/styleguides/README.md`.
- `agent/styleguides/fetcher/`, `agent/adr/fetcher/` — specific to
  `app_fetcher`'s domain (Steam parsing/building, ingestion jobs,
  schedulers, rate-limiting).
- `agent/styleguides/core/`, `agent/adr/core/` — specific to
  `app_core`'s domain (dashboard/React island, Turbo/Stimulus, actions).

When creating a new styleguide or ADR, decide which folder it belongs in
(see `create-styleguide` / `create-styleguide-from-scratch`). Default to the
relevant per-app folder when unsure — promoting a proven rule to shared
later is easier than walking back a shared rule that turns out to be
app-specific.

Files found to deviate from a convention or styleguide (while creating a
styleguide, researching, or implementing) are logged in
`agent/styleguides/fix_me.md` instead of being fixed inline or folded in
as an alternative convention — see that file for the format.
