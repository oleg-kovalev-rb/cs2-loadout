---
status: implemented
app: fetcher+core
goal: Prepare both monorepo apps for a minimal Kamal 2 deployment to one VPS — two services behind one proxy on two subdomains, Postgres/Redis as accessories, Docker Hub registry — buildable and locally smoke-tested before the server is bought.
created: 2026-10-20
---

# Development Plan

## Goal

Make `app_core` and `app_fetcher` deployable as two independent Kamal 2
services on a single Ubuntu VPS, using production Docker images, one
shared `kamal-proxy`, two subdomains (`app.<domain>` → `app_core`,
`api.<domain>` → `app_fetcher`), and Postgres/Redis as Kamal accessories.

The work stops at "artifacts are ready and verified locally": buying the
VPS, DNS records, Docker Hub account creation and the first live
`kamal setup` are human steps performed afterwards.

No application behavior, API shape, or local `docker compose` workflow
changes.

## Expected Behavior

After this plan is implemented (before a server exists):

- `docker build` produces a runnable production image for each app.
- Each image boots with `RAILS_ENV=production`, runs as a non-root user,
  and serves `GET /up` → `200`.
- `app_core` serves its compiled Vite island assets from the image
  (`vite_javascript_tag` resolves through the built manifest; JS chunks
  return `200`).
- `app_fetcher` runs Puma and, in a second role, Sidekiq with
  `config/sidekiq.yml`; `sidekiq-cron` loads `config/schedule.yml` on boot.
- Both apps connect to Postgres using `DB_HOST`/`DB_USER`/`DB_PASSWORD`
  instead of docker-compose hostnames; `app_fetcher` reaches Redis via
  `REDIS_URL` / `REDIS_URL_STREAM`, and `app_core` reaches the demo
  database via `REDIS_URL_DEMO`.
- The signed-out demo flow works end-to-end: `GET /demo/inventory`
  creates a Redis-backed demo session and the browser can call
  `app_fetcher`'s `/api/demo/*` with the demo bridge token.
- `bin/kamal config` renders a valid configuration in both app
  directories, with no reference to `192.168.0.1`, `service: app`, or
  `localhost:5555`.
- `.kamal/secrets` contains only references (`$(...)` / `$VAR`), no raw
  secrets.

After the human provisions the server and DNS:

- `bin/kamal setup` in `app_fetcher`, then in `app_core`, brings both
  apps up behind one proxy with Let's Encrypt certificates.
- `https://app.<domain>` serves `app_core`; `https://api.<domain>` serves
  `app_fetcher` and accepts browser calls from the `app_core` origin.
- Subsequent releases are `bin/kamal deploy` per app, zero downtime.

Behavior that must remain unchanged: local development via
`docker-compose.yml`, the CI pipeline, `bin/ci` in both apps, all
application code and tests.

## Scope

### In Scope

- Production `Dockerfile` for `app_core` and `app_fetcher` (multi-stage,
  non-root, entrypoint, Rails 7.2 production template as the base), while
  preserving the current dev images as `Dockerfile.dev`.
- Minimal `docker-compose.yml` change: point both `build:` directives at
  `Dockerfile.dev` so local dev, git hooks, and CI keep working.
- Vite production build inside the `app_core` image.
- `config/deploy.yml` for both apps: service/image names, Docker Hub
  registry, server placeholder, proxy host/SSL, env, secrets, roles,
  accessories, volumes, builder arch.
- `.kamal/secrets` templates for both apps (references only).
- `bin/kamal` binstubs in both apps.
- `database.yml` production sections: env-driven host/credentials and
  removal of unused `solid_*` databases.
- `config/environments/production.rb`: `assume_ssl` + `force_ssl` in both
  apps.
- `config/vite.json`: a production section if the default build output
  needs pinning.
- Small `.dockerignore` corrections (`/public/vite*` in `app_core`).
- `script/deploy` at repo root: deploys `app_fetcher` then `app_core` in
  one command.
- Local verification procedure (build + throwaway Postgres/Redis smoke
  run).

### Out of Scope

- Buying/creating the VPS, DNS records, Docker Hub account/token.
- Executing `kamal setup` / `kamal deploy` against a real server.
- GitHub Actions deploy workflow, staging destination, multi-server.
- Backups, monitoring, log aggregation, uptime checks.
- Managed Postgres/Redis.
- Any change to application code, API contracts, routes, or specs.
- Rewriting the compose stacks — only the `build:` directive in the base
  `docker-compose.yml` is touched (the CI override already merges on top
  and needs no change).
- Secret manager integration (1Password/Bitwarden); env vars suffice.

## Implementation Approach

Two Kamal configurations, one per app directory, sharing one
`kamal-proxy` on the VPS (Kamal attaches every app container and every
accessory to the fixed `kamal` Docker network, so no custom networking is
needed). Registry is Docker Hub, matching the official Rails guide.

Images:

- `steam-core` from `app_core/`
- `steam-fetcher` from `app_fetcher/`

Hostnames (placeholders until the domain is confirmed):

- `app.example.com` → `steam-core`, `proxy.ssl: true`
- `api.example.com` → `steam-fetcher`, `proxy.ssl: true`

Both apps use the Rails 7.2 default production Dockerfile (from
`railties` v7.2.3.2) as the base: `WORKDIR /rails`, non-root `rails`
user, `ENTRYPOINT ["/rails/bin/docker-entrypoint"]`, `EXPOSE 3000`,
`CMD ["./bin/rails", "server"]`. The repo's current Dockerfiles are dev
variants: they are renamed to `Dockerfile.dev` and stay the image used by
`docker-compose.yml`, git hooks, and CI, while `Dockerfile` becomes the
Kamal production image. Replacing them outright would break the bind-mount
dev workflow (`WORKDIR /app`, `BUNDLE_WITHOUT=development`) and therefore
CI. `proxy.app_port: 3000` is set explicitly (Kamal defaults to port 80).

`app_core` additionally installs Node 20 in the build stage, runs
`npm ci`, `bin/vite build`, then removes `node_modules` — the islands
cannot work without a compiled manifest. `app_fetcher` is API-only, so
its image skips asset precompilation (the Rails template's API branch).

Database configuration:

- `app_core` production: single `primary` database. Its `cache`/`queue`/
  `cable` entries are unused (memory cache store, async adapter, no
  Cable usage) and have no schema/migration dirs, so keeping them risks a
  broken `db:prepare` on first boot.
- `app_fetcher` production: `primary` + `cache` (it genuinely uses
  `:solid_cache_store` and has `db/cache_schema.rb`); drop `queue`/`cable`
  (Sidekiq + Redis).
- Connection settings from `DB_HOST`, `DB_USER`, `DB_PASSWORD` in both.

Accessories:

- `app_core` config: `db` (postgres:15).
- `app_fetcher` config: `db` (postgres:15) and `redis` (redis:7-alpine).
  No host port publishing — both apps reach accessories by container name
  inside the `kamal` network (`steam-core-db`, `steam-fetcher-db`,
  `steam-fetcher-redis`).

Kamal roles:

- `steam-core`: `web` only.
- `steam-fetcher`: `web` + `job` (`cmd: bundle exec sidekiq -C
  config/sidekiq.yml`). A single `job` host — `sidekiq-cron` must not run
  in two processes.

Proxy details shared by both configs (they manage the same proxy
container): `ssl: true`, `app_port: 3000`. Only `host` differs.

Env contract:

- `app_core`: `APP_FETCHER_PUBLIC_URL=https://api.example.com`,
  `DB_HOST=steam-core-db`, `DB_USER=postgres`,
  `REDIS_URL_DEMO=redis://steam-fetcher-redis:6379/3`, secrets
  `RAILS_MASTER_KEY`, `APP_BRIDGE_JWT_SECRET`,
  `APP_ADMIN_BRIDGE_JWT_SECRET`, `APP_DEMO_JWT_SECRET`, `DB_PASSWORD`,
  `POSTGRES_PASSWORD`.
- `app_fetcher`: `APP_CORE_ORIGIN=https://app.example.com`,
  `DB_HOST=steam-fetcher-db`, `DB_USER=postgres`,
  `REDIS_URL=redis://steam-fetcher-redis:6379/0`,
  `REDIS_URL_STREAM=redis://steam-fetcher-redis:6379/2` (optional
  `SIDEKIQ_CONCURRENCY`, default 5), secrets `RAILS_MASTER_KEY`,
  `APP_BRIDGE_JWT_SECRET`, `APP_ADMIN_BRIDGE_JWT_SECRET`,
  `APP_DEMO_JWT_SECRET`, `DB_PASSWORD`, `POSTGRES_PASSWORD`.
  (`APP_CORE_ORIGIN` has no default in `cors.rb`; omitting it prevents
  boot.)
- `RAILS_MASTER_KEY` is per app (each has its own
  `config/credentials.yml.enc`). All three JWT secrets must be identical
  across the two apps. `app_core` depends on the fetcher's `redis`
  accessory for `/3`; the controllers degrade gracefully when Redis is
  down, but the accessory must be booted before the core is deployed.
- Remove `SOLID_QUEUE_IN_PUMA` from both configs (neither app uses
  Solid Queue).

## Files To Modify

- `app_fetcher/Dockerfile` — becomes the Rails 7.2 production template
  (API variant): multi-stage, `RAILS_ENV=production`, non-root,
  entrypoint, port 3000. The current dev file moves to
  `Dockerfile.dev`. Reason: the current image cannot serve production and
  has no entrypoint, while dev/CI still need the old one.
- `app_core/Dockerfile` — same base plus a Node 20 build stage, `npm ci`,
  `bin/vite build`, `rm -rf node_modules`. The current dev file moves to
  `Dockerfile.dev`. Reason: Vite islands must be compiled into the image,
  and the dev image must keep working.
- `docker-compose.yml` — both `build:` entries become
  `{ context: ./, dockerfile: Dockerfile.dev }`. Reason: base compose,
  git hooks, and CI must keep building the dev image after `Dockerfile`
  becomes production-only.
- `app_core/.dockerignore` — add `/public/vite*` (and keep
  `node_modules` ignored). Reason: a stale local Vite build must not leak
  into the image.
- `app_core/config/database.yml` — production becomes a single `primary`
  with env-driven `host`/`username`/`password`. Reason: remove
  docker-compose hostnames and unused Solid databases.
- `app_fetcher/config/database.yml` — production keeps `primary` +
  `cache`, drops `queue`/`cable`, and uses env-driven connection values.
  Reason: same, while preserving the real `solid_cache` database.
- `app_core/config/environments/production.rb` — enable `assume_ssl` and
  `force_ssl` (excluding `/up`). Reason: TLS terminates at
  `kamal-proxy`.
- `app_fetcher/config/environments/production.rb` — same.
- `app_core/config/vite.json` — add a `production` section (output dir,
  no autoBuild) only if the default `bin/vite build` output needs
  pinning during verification.
- `app_core/config/deploy.yml` — rewrite as `steam-core`: image, server
  placeholder, Docker Hub registry, proxy host/SSL/app_port, env,
  secrets, `db` accessory, storage volume, builder arch.
- `app_fetcher/config/deploy.yml` — rewrite as `steam-fetcher`: same,
  plus `job` role, `db` + `redis` accessories.
- `app_core/.kamal/secrets` — references for registry password, master
  key, all three JWT secrets, DB/Postgres password.
- `app_fetcher/.kamal/secrets` — same, without anything core-only.
- `app_core/bin/kamal`, `app_fetcher/bin/kamal` — binstubs so deployment
  commands are `bin/kamal ...` as in the Rails guide.

## Files To Create

- `app_core/Dockerfile.dev`, `app_fetcher/Dockerfile.dev` — the current
  dev Dockerfiles, moved verbatim. Reason: keep the bind-mount dev/CI
  images separate from the production image.
- `script/deploy` — bash wrapper: deploy `app_fetcher`, then `app_core`,
  passing extra args through to `bin/kamal deploy`. Reason: one command
  for the whole monorepo, keeps ordering (fetcher/Redis first) explicit.
- `agent/styleguides/deployment.md` — required by `styleguides-check`
  (missing guide): captures the deploy topology, image/registry rules,
  env and secrets contract, and operational rules once they exist.
- `agent/adr/deployment-via-kamal.md` — the decision record produced
  alongside that styleguide (one VPS, two Kamal services, one proxy,
  accessories, Docker Hub).

No new application files, no migrations.

## Test Plan

Infrastructure-only change: no new RSpec/Vitest specs are expected, but
both existing suites must stay green.

Verification is done in three layers:

1. **Config validation (no server):** `bin/kamal config` in each app
   directory renders the merged config without SSH access; it catches
   unknown keys, bad YAML, and secret lookups.
2. **Image build (no server):** `docker build -t steam-core:local ./app_core`
   and the fetcher equivalent must succeed from a clean cache at least
   once (`--no-cache` on the first run). The dev/CI images must still
   build through `docker compose -f docker-compose.yml -f
   docker-compose.ci.yml build`, since they now point at `Dockerfile.dev`.
3. **Production smoke run (no server):** start throwaway Postgres 15 and
   Redis 7 containers on a dedicated Docker network, then run each image
   with production env pointing at them:
   - `GET /up` → `200` on both;
   - `GET /` on core → `200`, HTML references a Vite-built asset, and
     that asset URL returns `200`;
   - core's demo flow: `GET /demo/inventory` → `200`/redirect and writes
     a key into the throwaway Redis `/3`; a `GET /api/demo/*` call on the
     fetcher accepts a demo token minted with the shared secret;
   - one read-only public fetcher endpoint (e.g. `GET /api/public/items`)
     → `200` (after running `db:prepare` and a seed/fixture insert if the
     endpoint requires rows);
   - fetcher `job` container starts Sidekiq and logs the three cron
     entries from `config/schedule.yml`; no duplicate-cron warning;
   - `db:prepare` runs cleanly against an empty database for both apps.

Throwaway containers/volumes are removed afterwards; no dev database is
touched.

## Implementation Steps

1. Add `bin/kamal` binstubs in both apps (`bundle binstubs kamal`).
2. Move each app's current `Dockerfile` to `Dockerfile.dev` unchanged,
   and point both `build:` entries in `docker-compose.yml` at
   `Dockerfile.dev`.
3. Write the new `app_fetcher/Dockerfile` from the Rails 7.2 production
   template (API variant). Keep `postgresql-client` for `kamal dbc`.
4. Write the new `app_core/Dockerfile` from the same template, adding
   Node 20 + `npm ci` + `bin/vite build` in the build stage, and removing
   `node_modules` before the final stage.
5. Correct `app_core/.dockerignore` (exclude stale `/public/vite*`) and
   confirm `config/master.key` stays excluded in both apps.
6. Rewrite the production sections of both `database.yml` files:
   `primary` (plus `cache` for fetcher), env-driven connection values,
   drop unused Solid DBs.
7. Enable `assume_ssl` / `force_ssl` in both `production.rb`, excluding
   `/up` from the redirect.
8. Rewrite `app_core/config/deploy.yml` (`steam-core`): service, image,
   server placeholder, Docker Hub registry, proxy, env/secrets, `db`
   accessory, storage volume, `builder.arch: amd64`.
9. Rewrite `app_fetcher/config/deploy.yml` (`steam-fetcher`): same, plus
   the `job` role and the `redis` accessory; set `REDIS_URL` and
   `REDIS_URL_STREAM`; no `SOLID_QUEUE_IN_PUMA`.
10. Update both `.kamal/secrets` templates with references only; document
    which values must be identical across apps.
11. Add `script/deploy` (fetcher → core), executable.
12. Run the three verification layers from `Test Plan`; fix build/runtime
    issues (expected candidates: Vite output path, entrypoint args,
    proxy port, DB env wiring).
13. Run `bin/ci` in both apps (through the CI compose stack) to confirm
    nothing regressed.

Steps 1–11 produce the deployable artifacts; steps 12–13 are the gate
before the server is purchased.

## Verification

```bash
# Config renders (no SSH)
(cd app_fetcher && bin/kamal config)
(cd app_core && bin/kamal config)

# Production images build
docker build --no-cache -t steam-core:local ./app_core
docker build --no-cache -t steam-fetcher:local ./app_fetcher

# Dev/CI images still build from Dockerfile.dev
docker compose -f docker-compose.yml -f docker-compose.ci.yml build

# Both suites still pass
(cd app_fetcher && bin/ci)
(cd app_core && bin/ci)
```

Plus the smoke-run matrix described in `Test Plan` (throwaway
Postgres/Redis, `/up`, a core page with its Vite asset, a public fetcher
endpoint, Sidekiq + cron boot).

Manual checks after the server exists (not part of this plan's exit
criteria, recorded for the hand-off):

```bash
(cd app_fetcher && bin/kamal setup)
(cd app_core && bin/kamal setup)
curl -fsS https://api.<domain>/up
curl -fsS https://app.<domain>/up
bin/kamal logs -r job -f   # from app_fetcher/
```

## Risks

- **Master keys are not in this worktree.** `config/master.key` is
  gitignored and absent for both apps; the human must supply each app's
  key, or the container will fail to boot in production.
- **CI and local dev share the Dockerfiles.** If `docker-compose.yml`
  keeps building `./app_core` / `./app_fetcher` after those files become
  production-only, the bind-mounted dev containers run from the wrong
  `WORKDIR`, lose dev gems (`BUNDLE_WITHOUT=development`), and CI fails
  before any test runs. The `Dockerfile.dev` split is mandatory, not
  cosmetic.
- **Vite in Docker.** The default Rails 7.2 template has no Node stage;
  a wrong output path or missing `RAILS_ENV=production` yields a page
  with 404 asset URLs. The smoke run must assert the asset actually
  returns `200`.
- **Port mismatch.** The images expose 3000, while `kamal-proxy` defaults
  to 80; `proxy.app_port: 3000` in both configs is mandatory.
- **`db:prepare` on first boot.** Trimming unused Solid databases reduces
  the risk that the entrypoint tries to create databases without schema
  files. Both apps must still be smoke-tested against an empty database.
- **Two apps, one proxy.** Both deploy configs manage the same proxy
  container; `proxy.ssl` and `app_port` must match. Deploy order matters
  for accessories: `app_fetcher`'s `kamal setup` boots Redis and its DB,
  and `app_core` now depends on that Redis for demo sessions as well as
  on the fetcher's HTTPS API.
- **Cross-app Redis coupling.** `app_core`'s `REDIS_URL_DEMO` points at
  `steam-fetcher-redis`, an accessory owned by the fetcher's config.
  Booting core alone on a fresh host leaves demo sessions without a
  backend (pages degrade, app still boots). The shared JWT secrets and
  Redis hostname must be updated together.
- **Docker Hub free plan** allows one private repository; the two images
  must be public or the account upgraded. Public images contain no
  secrets.
- **`APP_CORE_ORIGIN` has no fallback** in `app_fetcher`'s CORS
  initializer; a missing value is a boot failure, not a CORS warning.
- **Sidekiq cron duplication** if the `job` role is scaled past one
  process.
- **Asset bridging.** `asset_path` covers `/rails/public/assets`
  (propshaft); Vite chunks live under `/rails/public/vite` and are not
  bridged. Acceptable for a single small server; revisit if rolling
  deploys show chunk 404s.
- **`.kamal/secrets` is committed.** It is a template today and must stay
  raw-secret-free; values come from env or a password manager.
- **Cost/size.** Two Rails processes + Sidekiq + two Postgres + Redis do
  not fit comfortably in 1 GB; the target VPS is ~4 GB (Hetzner CX22/23
  class, ~€4–5/month incl. IPv4).

## Assumptions

- Registry: Docker Hub, images `steam-core` / `steam-fetcher` under a
  personal account, both public.
- One VPS, Ubuntu 24.04 LTS, ~4 GB RAM, Docker installed by
  `kamal setup`; SSH as root with a key.
- The domain is already owned; two subdomains will point at the VPS,
  DNS-only (no CDN proxy) so Let's Encrypt can issue certificates.
  Exact names are still open (`app.` / `api.` placeholders).
- Local machine has Docker + buildx; builds target `amd64`.
- No CI-driven deployment in this plan; deploys are run manually.
- `app_core` uses the fetcher's Redis accessory only for demo sessions
  (`/3`); no other Redis usage exists in core.
- `app_fetcher` does not read `STEAM_WEB_API_KEY`; if that changes, the
  secret must be added to the fetcher config too.

## Applicable Styleguides

- `agent/styleguides/deployment.md` — the primary guide: constrains the
  topology (two services, one proxy, accessories), the production vs dev
  `Dockerfile` split, registry/image naming, the full env and secrets
  contract (including the three shared JWT secrets and
  `REDIS_URL_DEMO`), accessory naming, migration/rollback/backup
  procedure, and deploy order.
- `agent/styleguides/ci-and-coverage.md` — constrains Verification: the
  dev/CI images must keep building from `docker-compose.yml` +
  `Dockerfile.dev`, checks must keep running through the CI compose
  override, and each app's `bin/ci` stays the local equivalent.
- `agent/styleguides/core/architecture-layers.md` — constrains the
  topology: React islands (including the demo inventory) call
  `app_fetcher` directly from the browser, so `api.<domain>` must be a
  public, CORS-allowed origin and `APP_FETCHER_PUBLIC_URL` must match it.

## Completion Criteria

- Both apps build production images locally and pass the smoke matrix.
- The dev/CI images still build from `Dockerfile.dev` through the compose
  stack, and `bin/ci` passes in both apps.
- `bin/kamal config` is valid in both app directories.
- No docker-compose hostnames, `service: app`, or `localhost:5555`
  remain in deploy/database production config.
- Both `.kamal/secrets` files contain references only; the shared JWT
  secrets are documented as identical.
- `bin/ci` passes in both apps.
- The only remaining deploy steps are human-owned: buy the VPS, create
  DNS records and the Docker Hub token, fill the IP/domain placeholders,
  then run `bin/kamal setup` twice.

# Implementation Summary

## Implemented

- Replaced both dev Dockerfiles with Rails 7.2 production images
  (`Dockerfile`: multi-stage, `WORKDIR /rails`, non-root `rails` user,
  `bin/docker-entrypoint`, port 3000). The old files moved verbatim to
  `Dockerfile.dev`, and `docker-compose.yml` now builds them explicitly;
  dev, git hooks, and CI keep using the same images as before.
- `app_core`'s image installs Node 20 in the build stage, runs
  `npm ci` + `bin/vite build`, precompiles Propshaft assets with
  `SECRET_KEY_BASE_DUMMY=1`, and removes `node_modules` before the final
  stage. `public/vite` and `public/assets` are present in the image.
- Rewrote both `config/deploy.yml` files: `steam-core` (web + `db`),
  `steam-fetcher` (web + single `job` Sidekiq role + `db` + `redis`),
  Docker Hub registry, `proxy.ssl: true`, `proxy.app_port: 3000`,
  `builder.arch: amd64`, `deploy_timeout: 60`, env split into
  `clear`/`secret`, three shared JWT secrets, `REDIS_URL_DEMO` for core,
  `REDIS_URL`/`REDIS_URL_STREAM` for the fetcher. `SOLID_QUEUE_IN_PUMA`
  and the `/rails` path errors from the stock template are gone.
- `.kamal/secrets` for both apps now contain only references
  (`$VAR`, `$(cat config/master.key)`), including
  `APP_DEMO_JWT_SECRET` added by demo mode.
- `database.yml` (both apps): production driven by `DB_HOST`,
  `DB_USER`, `DB_PASSWORD`; core keeps only `primary`, fetcher keeps
  `primary` + `cache`. Removed the unused `queue`/`cable` databases.
- `production.rb` (both apps): enabled `assume_ssl`, `force_ssl`, and
  the `/up` exemption from the HTTPS redirect.
- Added `bin/kamal` binstubs, `script/deploy` (fetcher → core), and
  excluded stale `/public/vite*` from `app_core`'s build context.

## Tests

No new RSpec/Vitest specs: the change is deployment configuration, and no
application behavior moved. Existing suites were run unchanged.

Commands executed:

```bash
docker build --no-cache -t steam-core:local ./app_core
docker build --no-cache -t steam-fetcher:local ./app_fetcher
docker compose --env-file script/hook.env -f docker-compose.yml -f docker-compose.ci.yml build
docker compose ... up -d db_core db_fetcher
docker compose ... run --rm --no-deps -e COVERAGE=1 app_fetcher bin/ci
docker compose ... run --rm --no-deps -e COVERAGE=1 app_core bin/ci
(cd app_fetcher && bin/kamal config)
(cd app_core && bin/kamal config)
```

## Verification

- `app_fetcher/bin/ci`: passed — RSpec 563 examples, 0 failures;
  RuboCop, Sorbet, Brakeman, bundler-audit and seeds green.
- `app_core/bin/ci`: passed — RuboCop, Sorbet, ESLint, Prettier,
  Brakeman, bundler-audit, RSpec, Vitest and seeds green.
- Dev/CI images build through the compose stack from `Dockerfile.dev`.
- `bin/kamal config` renders valid configurations in both apps
  (Kamal 2.11.0, bundle binstub).
- Production smoke run against throwaway Postgres 15 + Redis 7:
  - both containers booted from empty databases; core created
    `app_core_production`, fetcher created `app_fetcher_production` and
    `app_fetcher_production_cache`;
  - `/up` → 200 on both; `GET /` → 200 and the referenced Vite chunk →
    200; `GET /api/public/items` → 200;
  - demo flow: `Demo::Start.call` wrote a key to Redis db 3, the minted
    demo token was accepted by `/api/demo/inventories` (200), and the
    CORS preflight returned `access-control-allow-origin:
    http://localhost:3100`;
  - the `job` container loaded all three sidekiq-cron schedules;
  - no errors in any container log.

## Deviations

- **Pre-existing production boot bugs had to be fixed.** Both
  `production.rb` files called `ActiveSupport::TaggedLogging.logger`,
  which does not exist in ActiveSupport 7.2.3.2 — production could not
  boot at all. Replaced with the Rails 7.2 template's
  `ActiveSupport::Logger` + `TaggedLogging.new` construction.
- **`solid_cache` had duplicate database configuration.** The fetcher
  had both `config.solid_cache.connects_to` (application.rb) and
  `database: cache` (cache.yml), which Solid Cache 1.0.10 rejects in
  every environment. Kept `connects_to` and removed the duplicate yml
  key; test/production cache access now consistently uses the `cache`
  database.
- **`DB_HOST`/`DB_PASSWORD` are fetched conditionally in `database.yml`.**
  ERB evaluates every section of the file, so a bare `ENV.fetch` in the
  production block broke dev, test, and CI. The values are now fetched
  only when `Rails.env.production?`, keeping fail-fast in production and
  the existing compose defaults elsewhere.
- **`assets:precompile` gets dummy DB values** (`DB_HOST=localhost
  DB_PASSWORD=precompile`) because the build evaluates `database.yml`
  but never connects.
- **`config/vite.json` needed no production section** — the default
  `bin/vite build` output and manifest resolution worked as-is.
- **`deploy_timeout: 60`** was added to both configs so a cold first
  boot (image pull + `db:prepare`) does not race the 30s default.

Known limitations:

- Production smoke used `SECRET_KEY_BASE` because `config/master.key` is
  not present in this worktree; the real deploy must supply each app's
  `RAILS_MASTER_KEY`.
- Asset bridging covers Propshaft (`/rails/public/assets`); Vite chunks
  under `/rails/public/vite` are not bridged during a release.
- `bin/kamal` runs on the host and needs a Ruby matching the Gemfile
  (`rbenv` has 3.3.5 here; the default 2.7.8 will not run the bundle).

## Remaining Issues

Human-owned steps before the first live deploy:

1. Buy the VPS (Ubuntu 24.04, ~4 GB) and add two DNS A records.
2. Create the Docker Hub repositories and access token.
3. Fill `<server-ip>`, `<domain>`, `<dockerhub-user>` in both
   `config/deploy.yml` files (and `<domain>` in the env values).
4. Ensure each app's `config/master.key` is available, then export
   `KAMAL_REGISTRY_PASSWORD`, `DB_PASSWORD`, and the three JWT secrets.
5. Run `bin/kamal setup` in `app_fetcher`, then in `app_core`.

Follow-up work, out of this plan's scope: CI-driven deployment,
monitoring/uptime checks, automated backups, and Vite chunk bridging.
