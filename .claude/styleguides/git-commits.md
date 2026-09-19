# Git Commit Conventions

## Purpose

How commit messages are written across this monorepo, so history stays
scannable by scope (`git log --oneline` should tell you which app a
commit touched without opening it) and so a non-obvious change carries
its own "why."

## Structure

- Subject line: `[Scope] Imperative summary` — no trailing period.
- `Scope` is one of the tags already in use:
  - `Core` — `app_core` only;
  - `Fetcher` — `app_fetcher` only;
  - `Core+Fetcher` — a change that touches both apps together (`Core`
    listed first);
  - `Claude` — changes confined to `.claude/` (skills, styleguides, ADRs,
    plans) — process/tooling, not application code.
  Don't invent a new tag ad hoc; if a genuinely new scope appears (a
  third app or package), add it deliberately rather than
  one-off-improvising a name.
- The summary starts with a capitalized, imperative verb (`Add`, `Move`,
  `Fix`, `Wire` — not `Added`/`Adds`/a lowercase start).

This `[Scope]` convention covers the project's entire commit history to
date except its first dozen commits, from before the convention started
(`Initial commit` through `Rename service directories`) — those predate
it and aren't a pattern to follow for new commits.

## Rules

### MUST

- `[Scope] Imperative summary` as the subject, per Structure above.
- Keep the subject to one line. If the change needs more explanation,
  that's what the body is for (see SHOULD) — don't cram extra detail
  into the subject itself.

### SHOULD

- For a small, self-contained change that's easily understood from the
  diff, a bare subject line is enough — most of this repo's history is
  exactly that (e.g. `[Fetcher] Add change_24h_cents column to items`,
  `[Core] Add user model`).
- For a change with multiple distinct parts, or a motivation that isn't
  obvious from the diff, add a body: one `- ` bullet per distinct part,
  each stating what changed and *why* it was needed — not a restatement
  of the diff. Wrap body lines at roughly 75 characters. See any of the
  six most recent commits (e.g. `914ef7b`, `b65a9b8`) for the pattern.
- When a commit is produced by an AI coding session, end the body with a
  blank line then a `Co-Authored-By: <Model Name> <noreply@anthropic.com>`
  trailer (see the same six commits) — this is how AI-assisted commits
  are marked as such in this repo's history.

### MUST NOT

- Don't pad a one-line-worthy change with a body just to have one, and
  don't summarize a multi-part change in the subject alone when it
  genuinely needs a body to explain the "why."

## Examples From History

Single-line, no body:

```
[Fetcher] Add change_24h_cents column to items
[Core] Add user model
```

Multi-part change with a body:

```
[Fetcher] Add background jobs/schedulers styleguide, ADR for price stream

- Document Sidekiq worker/scheduler conventions: explicit retry: tuned
  to failure-proneness, queue isolation for Steam-API-calling work,
  bulk writes over per-record loops, transactions for multi-record
  consistency, and why jobs stay outside the Steam:: namespace
- Log PriceScheduler's missing explicit retry: as a deviation (judgment
  call vs. the two workers, not a tool-confirmed error)
- Add ADR for publishing price updates to a capped Redis Stream instead
  of Pub/Sub or a direct WebSocket push — documents that this is
  write-ahead-of-read infrastructure shipped with no consumer yet, so
  it isn't mistaken for dead code

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
```
