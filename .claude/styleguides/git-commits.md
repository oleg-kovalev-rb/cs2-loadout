# Git Commit Conventions

## Purpose

How commit messages are written across this monorepo, so history stays
scannable by scope (`git log --oneline` should tell you which app a
commit touched without opening it) and so a non-obvious change carries
its own "why."

## Structure

- Subject line only: `[Scope] Imperative summary` — no trailing period,
  no body, no trailer.
- `Scope` is one of the tags already in use:
  - `Core` — `app_core` only;
  - `Fetcher` — `app_fetcher` only;
  - `Core+Fetcher` — a change that touches both apps together (`Core`
    listed first);
  - `AI WorkFlow` — changes confined to `.claude/` (skills, styleguides,
    ADRs, plans) — the AI-driven dev pipeline's own process/tooling, not
    application code.
  Don't invent a new tag ad hoc; if a genuinely new scope appears (a
  third app or package), add it deliberately rather than
  one-off-improvising a name.
- The summary starts with a capitalized, imperative verb (`Add`, `Move`,
  `Fix`, `Wire` — not `Added`/`Adds`/a lowercase start).

This `[Scope]` convention covers the project's entire commit history to
date except its first dozen commits, from before the convention started
(`Initial commit` through `Rename service directories`) — those predate
it and aren't a pattern to follow for new commits. Commits before the
subject-line-only rule took effect may still carry a body/trailer —
that's history, not something to rewrite.

## Rules

### MUST

- `[Scope] Imperative summary` as the subject, per Structure above —
  nothing else in the commit message.
- Keep the subject to one line.

### MUST NOT

- Don't add a commit body. If a change has multiple distinct parts, the
  diff and the individual file/commit split are what explain it — split
  into more single-purpose commits rather than writing a bullet list to
  narrate one big one.
- Don't add a `Co-Authored-By:` or any other trailer.

## Examples From History

```
[Fetcher] Add change_24h_cents column to items
[Core] Add user model
[AI WorkFlow] Add RSpec testing-conventions styleguide and ADR
```
