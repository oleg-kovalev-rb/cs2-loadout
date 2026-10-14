# Styleguides

`base.md` is the canonical styleguide format — see `create-styleguide` /
`create-styleguide-from-scratch` for how it's used.

Styleguides are split by scope:

- **directly under `styleguides/`** (this level, not in a subfolder) —
  conventions that apply identically to every app in the monorepo. Only
  rules that are true regardless of which app you're in:
  - Ruby style and idioms;
  - git/commit conventions;
  - generic Rails layering, if actually shared between apps;
  - RSpec conventions common to both apps.
- **`styleguides/fetcher/`** — specific to `app_fetcher`'s domain: Steam API
  parsing/builders, ingestion jobs, schedulers, rate-limiting, sidekiq-cron.
- **`styleguides/core/`** — specific to `app_core`'s domain: the React
  dashboard island, Turbo/Stimulus conventions, `app/actions/`.

When in doubt: if the rule would need to be explained differently for the
other app, it's per-app, not shared. Default to per-app when unsure —
promoting a proven rule to shared later is cheap; walking back a shared rule
that turns out to be app-specific is not.

`fix_me.md` — files found to deviate from a convention or styleguide rule,
grouped by the same shared/fetcher/core scopes. Not a task backlog; see
that file for the format and how entries get resolved.
