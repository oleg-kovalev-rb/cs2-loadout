# app_fetcher

The API-only Rails service for [CS2 Loadout](../README.md). It ingests Steam
Store and Market data, stores items, prices, and inventories, and exposes JSON
APIs for the player dashboard, public catalog, demo sessions, and admin panel.

- Rails 7.2 API with Sorbet, Sidekiq and sidekiq-cron for scheduled work.
- Pipeline: parsers → builders → services → workers. Prices update hourly,
  portfolio value snapshots nightly, and inventories sync roughly weekly.
- Tests and checks: `bin/ci` (RSpec, RuboCop, Sorbet, Brakeman,
  bundler-audit).

Local setup and the architecture overview live in the
[root README](../README.md). Conventions: `agent/styleguides/fetcher/` and
`agent/styleguides/rails-layering.md`.
