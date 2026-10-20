# app_core

The user-facing Rails app for [CS2 Loadout](../README.md): Steam OpenID
sign-in, the portfolio dashboard, inventory pages, the public item catalog,
and the admin panel.

- Rails 7.2 with Sorbet, Turbo/Stimulus, and React islands built with Vite.
- Reads data from `app_fetcher` over HTTP. The browser calls the fetcher
  directly with a short-lived bridge token; there is no proxy layer.
- Tests and checks: `bin/ci` (RSpec, Vitest, RuboCop, Sorbet, Brakeman,
  bundler-audit, ESLint, Prettier).

Local setup and the architecture overview live in the
[root README](../README.md). Conventions: `agent/styleguides/core/` and
`agent/styleguides/rails-layering.md`.
