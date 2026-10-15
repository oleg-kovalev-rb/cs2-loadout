# Git Hooks with Lefthook (Staged Lint + Commit-Message Gate)

## Status

Accepted

## Context

The repo has no git hooks installed — `.git/hooks/` contains only the
`.sample` files. Quality is enforced only by whatever CI runs (which,
until `agent/adr/ci-via-docker-compose.md`, ran nothing), so a style
violation or a malformed commit reaches history before anyone sees it.

`agent/styleguides/git-commits.md` defines a `[Scope] Imperative
summary` commit-message convention, but nothing enforces it — it relies
on the author remembering. The repo also actively uses linked worktrees
(`extensions.worktreeconfig=true`, `.claude/worktrees/*`), and any hook
mechanism has to keep working there.

The project has no root Ruby manifest and no root Node manifest; the two
apps each have their own. Any hook tool has to be installed without
assuming a root Gemfile.

## Decision

Adopt **lefthook** as the git-hook manager, configured in a committed
root `lefthook.yml`.

Two hooks:

- **`pre-commit`** — a fast, staged-files-only subset of the CI
  `linters` job: `rubocop` on staged Ruby for each app, and `eslint` +
  `prettier --check` on staged `app_core` frontend files. Commands are
  scoped per app (each with its own `root`) and run through docker
  compose, matching how CI runs them.
- **`commit-msg`** — a dependency-free Ruby script
  (`script/commit-msg`) that rejects any subject not matching
  `git-commits.md`'s `[Scope] Imperative summary` (valid scope, capital
  imperative verb, no trailing period/body/trailer).

lefthook is installed as a devDependency of a new root `package.json`
whose `prepare` script runs `lefthook install`, so a single `npm install`
wires the hooks on any checkout.

## Alternatives Considered

### Alternative: `overcommit` (Ruby gem)

Use the established Ruby hook-framework gem instead of a separate binary.

Rejected because:

- It needs a Gemfile to live in; the repo has no root Gemfile, and
  adding a third Gemfile purely for hooks couples hook setup to the Ruby
  toolchain, which a frontend-only contribution shouldn't need.
- Its staged-file handling is less ergonomic for a two-app, per-directory
  scoping than lefthook's `root`/`glob`.

### Alternative: `husky` (Node)

The most common JS-ecosystem hook manager.

Rejected because:

- It's Node-centric and expects a single root package; the repo's only
  Node manifest is `app_core/package.json`, and root tooling shouldn't be
  owned by one app's manifest.
- It doesn't run per-directory commands as cleanly as lefthook's `root`.

### Alternative: `core.hooksPath` + hand-written shell scripts

Point Git at a committed hooks directory and write `pre-commit`/
`commit-msg` shell scripts.

Rejected because:

- There's no dependency, but also no staged-file selection, no parallel
  execution, and no `skip`/`exclude` handling — each script would
  re-implement what lefthook provides.
- Bootstrapping is manual (`git config core.hooksPath ...`), easy to
  forget on a fresh clone or a new worktree, and there's no `prepare`
  equivalent to automate it.

### Alternative: No hooks (status quo)

Rejected because:

- The commit convention and lint rules stay unenforced until CI runs, and
  a broken commit is already in history by then.

## Consequences

### Positive

- Style and commit-format violations are caught before the commit exists,
  not after a CI round-trip.
- One committed `lefthook.yml` works for both apps and every worktree;
  `npm install` is the only setup step.
- The hook layer is deliberately a subset of CI, so the two can't
  disagree about what "clean" means.

### Negative

- The `pre-commit` hook runs through docker compose, so a contributor
  must have Docker running while committing — a local hook is slower than
  a host-installed `rubocop`/`eslint`.
- A root `package.json`/`package-lock.json` now exists solely for the
  hook tool, on top of the two apps' manifests.

### Risks

- Bypass is possible (`git commit --no-verify`) and expected; the hook is
  a convenience gate, CI remains the authority.
- If a check is added to CI but not to `lefthook.yml` (or vice versa),
  local and CI behavior drift; keep them aligned deliberately.
- Worktree behavior must be verified: `lefthook install` writes into the
  shared hooks directory, and `extensions.worktreeconfig` means config
  can differ per worktree.

## Implementation Constraints

- Hook config lives in the committed root `lefthook.yml`; installation is
  `lefthook install`, wired through the root `package.json`'s `prepare`
  script.
- `pre-commit` commands are staged-files-only and per-app (each command
  declares its own `root`/`glob`), and invoke checks through docker
  compose with the `docker-compose.ci.yml`-style invocation.
- `commit-msg` is a dependency-free script (no bundler, no gems) so it
  runs on any checkout; `lefthook.yml` passes it the commit-message file.
- The valid scope-tag set in `script/commit-msg` must match
  `agent/styleguides/git-commits.md` exactly.
- Hooks never replace CI: every `pre-commit` check is also a blocking CI
  check (`agent/styleguides/ci-and-coverage.md`).

## Related

- `agent/styleguides/git-hooks.md` — the "how" companion to this "why"
- `agent/styleguides/git-commits.md` — the commit-message convention the
  `commit-msg` hook enforces
- `agent/adr/ci-via-docker-compose.md` — the CI half of the same
  automated-checks story
- `agent/plans/add-ci-and-git-hooks.md` — the plan that surfaced this
  decision
