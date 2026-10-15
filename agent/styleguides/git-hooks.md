---
description: Git-hook conventions for the monorepo — lefthook setup, the staged-files-only pre-commit lint subset, the commit-msg scope-format gate, install/onboarding, and worktree behavior.
---

# Git Hooks

## Purpose

Catch style violations and malformed commit messages on the developer's
machine, before they enter history — a fast, local subset of what CI
enforces in full. One committed config works for both apps and every
worktree.

See `agent/adr/git-hooks-with-lefthook.md` for why lefthook was chosen
over overcommit/husky/`core.hooksPath`.

## When to Use

Applies whenever hooks are added, changed, or installed. Not the place to
decide what a check *is* — a hook only invokes checks defined elsewhere
(the app's `.rubocop.yml`, `eslint.config.js`, and
`agent/styleguides/git-commits.md`).

## Structure

- Hook config: root `lefthook.yml`, committed.
- Hook scripts with real logic: root `script/` (currently
  `script/commit-msg`).
- Install mechanism: root `package.json` devDependency `lefthook`, with
  `"prepare": "lefthook install"`, plus the generated root
  `package-lock.json`.
- Two hooks: `pre-commit` and `commit-msg`.

## Interface

- `pre-commit` receives `{staged_files}`; each command filters with its
  own `glob` and sets its own `root` (the app directory) so the paths are
  app-relative.
- `commit-msg` receives the path to the commit-message file as its first
  argument (`{1}`).

## Rules

### MUST

- Keep hook config in the committed root `lefthook.yml`; install with
  `lefthook install` (via the root `package.json` `prepare` script) —
  never rely on hand-edited `.git/hooks`.
- Keep `pre-commit` staged-files-only: each command selects its files via
  `glob` (Ruby for each app; `app/frontend/**/*.{js,jsx}` for `app_core`)
  and must be a no-op when nothing matches.
- Run `pre-commit` checks through docker compose against the **working
  tree** (the base `docker-compose.yml`, which bind-mounts the source), so
  the container lints the staged files, not the image's copy; scope each
  command per app with `root`.
- Keep `commit-msg` a dependency-free script (no bundler/gems) so it runs
  on any checkout, and have it validate the subject against
  `agent/styleguides/git-commits.md` — `[Scope] Imperative summary`, a
  tag from that guide's list, a capital imperative verb, no trailing
  period, no body/trailer.
- Treat every `pre-commit` check as a subset of CI: anything it runs is
  also a blocking CI check.

### SHOULD

- Keep `pre-commit` fast — only the cheap, staged-file checks belong
  there; full suites stay in CI.
- Keep the valid scope-tag set in `script/commit-msg` identical to
  `git-commits.md`'s list (update both together).

### MUST NOT

- Don't add a hook check that isn't also a CI check, or that needs the
  full test suite — hooks are a convenience gate, not a second CI.
- Don't add a hook check that depends on the CI override's anonymous
  `node_modules` volume or the image's baked-in code — hooks must lint the
  working tree via the base stack.
- Don't add hook logic inline in `lefthook.yml` beyond a short command —
  put non-trivial logic in a `script/` file.
- Don't depend on hooks for correctness: `git commit --no-verify` is
  always available, and CI is the authority.

## Interaction With Other Layers

```text
git commit
    ↓ pre-commit (lefthook)
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
- root `package.json` — the `lefthook` devDependency + `prepare` install

## Related ADR

- `agent/adr/git-hooks-with-lefthook.md` — why lefthook, and why hooks
  are a staged subset of CI.
- `agent/styleguides/git-commits.md` — the format `commit-msg` enforces.
- `agent/styleguides/ci-and-coverage.md` — the CI checks hooks mirror.
