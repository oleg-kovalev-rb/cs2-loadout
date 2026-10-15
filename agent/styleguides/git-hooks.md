---
description: Git-hook conventions for the monorepo — lefthook setup, the pre-commit checks (staged-file linters plus the whole-project Sorbet/tapioca-dsl step), the commit-msg scope-format gate, install/onboarding, and worktree behavior.
---

# Git Hooks

## Purpose

Catch style violations, stale Sorbet RBIs, type errors, and malformed
commit messages on the developer's machine, before they enter history —
the same checks CI enforces, run locally. One committed config works for
both apps and every worktree.

See `agent/adr/git-hooks-with-lefthook.md` for why lefthook was chosen
over overcommit/husky/`core.hooksPath`.

## When to Use

Applies whenever hooks are added, changed, or installed. Not the place to
decide what a check *is* — a hook only invokes checks defined elsewhere
(the app's `.rubocop.yml`, `eslint.config.js`, Sorbet setup, and
`agent/styleguides/git-commits.md`).

## Structure

- Hook config: root `lefthook.yml`, committed.
- Hook scripts with real logic: root `script/` (`script/commit-msg`,
  `script/sorbet-hook`).
- Install mechanism: root `package.json` devDependency `lefthook`, with
  `"prepare": "lefthook install"`, plus the generated root
  `package-lock.json`.
- Two hooks: `pre-commit` and `commit-msg`.

## Interface

- Staged-file `pre-commit` commands receive `{staged_files}`, filter with
  their own `glob`, and set their own `root` (the app directory) so paths
  are app-relative.
- The Sorbet command is the exception: its `glob` only **gates** whether
  it runs (Ruby was staged); the check itself is whole-project and takes
  no `{staged_files}` — it delegates to `script/sorbet-hook <app>`.
- `commit-msg` receives the path to the commit-message file as its first
  argument (`{1}`).

## Rules

### MUST

- Keep hook config in the committed root `lefthook.yml`; install with
  `lefthook install` (via the root `package.json` `prepare` script) —
  never rely on hand-edited `.git/hooks`.
- Keep the staged-file lint commands (`rubocop`, `eslint`, `prettier`)
  staged-files-only: each selects its files via `glob` and must be a no-op
  when nothing matches.
- Run every `pre-commit` command through docker compose against the
  **working tree** (the source bind mount), so the container sees the
  staged files, not a stale image copy. The staged-file linters use the
  base `docker-compose.yml`; the Sorbet command uses the full override
  (`docker compose -f docker-compose.yml -f docker-compose.ci.yml`) so its
  `up --wait` can use the DB/Redis healthchecks.
- Run the Sorbet check via `script/sorbet-hook`: per app, `bundle exec
  tapioca dsl` (regenerate that app's model DSL RBIs), then fail if it
  produced un-staged changes (`git add <app>/sorbet/rbi/dsl` and commit
  again), then `bundle exec srb tc`. Never run `tapioca gems` here.
- Keep `commit-msg` a dependency-free script (no bundler/gems) so it runs
  on any checkout, and have it validate the subject against
  `agent/styleguides/git-commits.md` — `[Scope] Imperative summary`, a
  tag from that guide's list, a capital imperative verb, no trailing
  period, no body/trailer.
- Treat every `pre-commit` check as a subset of CI: anything it runs is
  also a blocking CI check.

### SHOULD

- Keep the staged-file lint commands cheap and fast; the whole-project
  Sorbet step already makes a Ruby commit slower, so don't add more
  whole-project work.
- Keep the valid scope-tag set in `script/commit-msg` identical to
  `git-commits.md`'s list (update both together).

### MUST NOT

- Don't add a hook check that isn't also a CI check, or that needs the
  full test suite — hooks are a convenience gate, not a second CI.
- Don't run `tapioca gems` in a hook: gem RBIs are regenerated when the
  gems change, not on every commit (and `tapioca gems` regenerates the
  whole gem RBI set).
- Don't let the Sorbet step succeed when `tapioca dsl` changed files that
  aren't staged — that is exactly how DSL-RBI debt accumulates.
- Don't run the JS lint commands (`eslint`, `prettier`) against the CI
  override — its anonymous `/app/node_modules` volume would use the
  image's Node deps instead of the checked-out ones; use the base stack.
- Don't add hook logic inline in `lefthook.yml` beyond a short command —
  put non-trivial logic in a `script/` file.
- Don't depend on hooks for correctness: `git commit --no-verify` is
  always available, and CI is the authority.

## Interaction With Other Layers

```text
git commit
    ↓ pre-commit (lefthook, parallel)
        ├── script/sorbet-hook app_fetcher   (tapioca dsl → gate on staged RBIs → srb tc)
        ├── script/sorbet-hook app_core      (same)
        ├── app_fetcher: docker compose run --rm app_fetcher bin/rubocop {staged_files}
        ├── app_core:    docker compose run --rm app_core    bin/rubocop {staged_files}
        └── app_core:    docker compose run --rm app_core    npx eslint|prettier --check {staged_files}
    ↓ commit-msg (lefthook) → script/commit-msg {1}   (scope/format gate)
    ↓
commit created
```

## Canonical Implementations

- `lefthook.yml` — hook definitions
- `script/commit-msg` — the commit-subject validator
- `script/sorbet-hook` — the per-app `tapioca dsl` + `srb tc` step
- root `package.json` — the `lefthook` devDependency + `prepare` install

## Related ADR

- `agent/adr/git-hooks-with-lefthook.md` — why lefthook, and why hooks
  mirror CI.
- `agent/styleguides/git-commits.md` — the format `commit-msg` enforces.
- `agent/styleguides/ci-and-coverage.md` — the CI checks hooks mirror.
- `agent/styleguides/ruby-sorbet.md` — the `tapioca dsl` regeneration
  workflow the Sorbet step automates.
