---
description: Production deployment conventions for the monorepo — two Kamal services on one VPS (steam-core, steam-fetcher), shared kamal-proxy with per-app hostnames, production vs dev Dockerfiles, registry/image naming, the env and secrets contract, accessory naming, migrations, and deploy/rollback/backup procedures.
---

# Deployment (Kamal)

## Purpose

Governs how both applications in this monorepo are built, shipped, and
operated in production. It exists so the two Kamal configurations stay
consistent with each other and with the browser-to-fetcher architecture
they serve.

See `agent/adr/deployment-via-kamal.md` for why this topology was chosen
and which alternatives were rejected.

Not covered here: CI (see `agent/styleguides/ci-and-coverage.md`),
application architecture (see `rails-layering.md` and the per-app
architecture guides), or local development composition.

## When to Use

Applies to any change that touches:

- `Dockerfile` / `Dockerfile.dev` in either app;
- `config/deploy.yml` or `.kamal/secrets` in either app;
- production environment variables, secrets, or database connection
  settings;
- `script/deploy`, `bin/kamal`, or the production database list;
- how releases, migrations, rollbacks, or backups are performed.

## Structure

- Two independent Kamal configurations, one per app directory:
  - `app_core/config/deploy.yml` — service `steam-core`;
  - `app_fetcher/config/deploy.yml` — service `steam-fetcher`.
- One shared `kamal-proxy` on the VPS; each service registers its own
  `proxy.host`.
- Per app, two images in one repository directory:
  - `Dockerfile` — production, Rails 7.2 multi-stage template
    (`WORKDIR /rails`, non-root `rails` user,
    `ENTRYPOINT ["/rails/bin/docker-entrypoint"]`, `EXPOSE 3000`);
  - `Dockerfile.dev` — the development image
    (`WORKDIR /app`, bind-mount friendly), used by
    `docker-compose.yml`, git hooks, and CI.
- `docker-compose.yml` builds `Dockerfile.dev` explicitly via
  `build: { context: ., dockerfile: Dockerfile.dev }`.
- Accessories live in the owning app's configuration:
  - `steam-core` → `db`;
  - `steam-fetcher` → `db`, `redis`.
- `bin/kamal` is committed in both apps; `script/deploy` at the repo root
  deploys the fetcher, then the core.

```text
app.<domain> ──▶ kamal-proxy ──▶ steam-core-web-*        (Puma, :3000)
api.<domain> ──▶ kamal-proxy ──▶ steam-fetcher-web-*     (Puma, :3000)
                                 steam-fetcher-job-*     (Sidekiq)
                    kamal network:
                      steam-core-db, steam-fetcher-db, steam-fetcher-redis
                    steam-core → steam-fetcher-redis/3   (demo sessions)
```

## Interface

### Commands

Run from the app directory (`app_core/` or `app_fetcher/`):

| Action | Command |
|---|---|
| first-time server setup | `bin/kamal setup` |
| release | `bin/kamal deploy` |
| release both apps | `script/deploy` (repo root) |
| rollback | `bin/kamal rollback` |
| logs (web) | `bin/kamal logs -f` |
| logs (Sidekiq) | `bin/kamal logs -r job -f` |
| Rails console | `bin/kamal console` |
| shell in container | `bin/kamal shell` |
| database console | `bin/kamal dbc` |
| inspect resolved config | `bin/kamal config` |
| boot/reboot accessories | `bin/kamal accessory boot <name>` |

### Environment contract (`app_core`)

| Name | Kind | Value / source |
|---|---|---|
| `APP_FETCHER_PUBLIC_URL` | clear | `https://api.<domain>` |
| `DB_HOST` | clear | `steam-core-db` |
| `DB_USER` | clear | `postgres` |
| `REDIS_URL_DEMO` | clear | `redis://steam-fetcher-redis:6379/3` |
| `RAILS_MASTER_KEY` | secret | this app's `config/master.key` |
| `APP_BRIDGE_JWT_SECRET` | secret | shared with `app_fetcher` |
| `APP_ADMIN_BRIDGE_JWT_SECRET` | secret | shared with `app_fetcher` |
| `APP_DEMO_JWT_SECRET` | secret | shared with `app_fetcher` |
| `DB_PASSWORD` | secret | matches `POSTGRES_PASSWORD` |

### Environment contract (`app_fetcher`)

| Name | Kind | Value / source |
|---|---|---|
| `APP_CORE_ORIGIN` | clear | `https://app.<domain>` (boot-critical) |
| `DB_HOST` | clear | `steam-fetcher-db` |
| `DB_USER` | clear | `postgres` |
| `REDIS_URL` | clear | `redis://steam-fetcher-redis:6379/0` |
| `REDIS_URL_STREAM` | clear | `redis://steam-fetcher-redis:6379/2` |
| `SIDEKIQ_CONCURRENCY` | clear | optional; defaults to 5 |
| `RAILS_MASTER_KEY` | secret | this app's `config/master.key` |
| `APP_BRIDGE_JWT_SECRET` | secret | shared with `app_core` |
| `APP_ADMIN_BRIDGE_JWT_SECRET` | secret | shared with `app_core` |
| `APP_DEMO_JWT_SECRET` | secret | shared with `app_core` |
| `DB_PASSWORD` | secret | matches `POSTGRES_PASSWORD` |

### `.kamal/secrets`

Both files contain **references only**, never literal values:

- `KAMAL_REGISTRY_PASSWORD` from the environment (Docker Hub token);
- `RAILS_MASTER_KEY` from this app's `config/master.key`;
- the three JWT secrets from the environment;
- database/Postgres passwords from the environment.

## Rules

### MUST

- Keep `service` and `image` distinct per app: `steam-core` and
  `steam-fetcher`. Never reintroduce `service: app`.
- Set `proxy.ssl: true`, `proxy.app_port: 3000`, and a per-app
  `proxy.host` in both configurations. Both configs manage one shared
  proxy, so these settings must stay identical except for `host`.
- Build production images from `Dockerfile`; keep `Dockerfile.dev` as the
  image referenced by `docker-compose.yml`. Never point compose at the
  production Dockerfile.
- Compile Vite assets inside `app_core`'s image (`npm ci`,
  `bin/vite build`) and delete `node_modules` before the final stage.
- Declare non-secret configuration under `env.clear` and every secret
  under `env.secret`, resolved through `.kamal/secrets`.
- Keep all three JWT secrets byte-identical across the two apps, and keep
  `RAILS_MASTER_KEY` app-specific.
- Give `app_core` `REDIS_URL_DEMO` pointing at the fetcher's Redis
  accessory (`/3`); it must not assume a local Redis. Boot that accessory
  (`bin/kamal accessory boot redis` from `app_fetcher/`) before deploying
  `app_core` to a fresh server.
- Drive production database connections from `DB_HOST` / `DB_USER` /
  `DB_PASSWORD`. Keep `app_core`'s production databases to `primary`, and
  `app_fetcher`'s to `primary` + `cache`.
- Run exactly one `job` role host for `app_fetcher`, with
  `cmd: bundle exec sidekiq -C config/sidekiq.yml`.
- Put data in accessory volumes/directories (`postgres` data dir, Redis
  `/data`) and back them up on a schedule.
- Deploy `app_fetcher` before `app_core` when a change affects the
  shared contract (JWT secrets, API shape, env).
- Run migrations before traffic switches to the new container
  (`bin/docker-entrypoint` for the web role, or a `pre-deploy` hook).

### SHOULD

- Verify a production image locally (`docker build`, then run it against
  throwaway Postgres/Redis) before the first deploy on a new server.
- Run `bin/kamal config` after editing a deploy configuration; it catches
  unknown keys and missing secrets without SSH.
- Keep `script/deploy` as the single entry point for releasing both apps.
- Keep `.kamal/secrets` in version control as a template; source values
  from the environment or a password manager.

### MUST NOT

- Publish Postgres or Redis ports on the host; apps reach accessories by
  container name over the `kamal` network.
- Set `SOLID_QUEUE_IN_PUMA`; neither app uses Solid Queue.
- Rely on `REDIS_URL_STREAM`'s `localhost` default in production.
- Put raw secrets in `config/deploy.yml`, `.kamal/secrets`, a Dockerfile,
  or the image.
- Reuse one app's master key for the other.
- Run more than one Sidekiq process for the `job` role (duplicate
  sidekiq-cron schedules).
- Use `localhost:5555` / a local registry unless the whole team adopts
  the port-forwarding workflow; the project registry is Docker Hub.

## Operations

### Deploy machine

Kamal runs on the developer machine, not inside the app image: it needs a
Ruby matching the Gemfile (the `ARG RUBY_VERSION` in `Dockerfile`) with
`bundle install` completed in each app. `bin/kamal` is the entry point;
`script/deploy` runs both apps in the required order.

### First deployment (once per server)

1. Ubuntu 24.04 VPS, SSH key, firewall allowing 22/80/443.
2. DNS A records for `app.<domain>` and `api.<domain>` → VPS IP
   (DNS-only, no CDN proxy, so Let's Encrypt can validate).
3. Docker Hub account + access token; `KAMAL_REGISTRY_PASSWORD` exported.
4. Fill the server IP in both `config/deploy.yml`, replace `<domain>`.
5. From `app_fetcher/`: `bin/kamal setup` (installs Docker, boots proxy,
   `db` + `redis`, deploys).
6. From `app_core/`: `bin/kamal setup` (reuses the proxy, boots its `db`).
7. Check `https://api.<domain>/up` and `https://app.<domain>/up`, then
   `bin/kamal logs -f` in each app.

### Release

`script/deploy` from the repo root, or `bin/kamal deploy` in one app.
Migrations run from the web container's entrypoint; a failing migration
aborts the release before traffic switches.

### Rollback

`bin/kamal rollback` in the affected app. Accessory images are not rolled
back with the app; a database migration that is not backwards-compatible
must be released in two steps.

### Backups

Nightly `pg_dump` of each database from its accessory container, gzipped
to the host, retained for at least a week. Redis is replaceable state
(queues can be re-enqueued); Postgres is not.

## Canonical Implementations

- `app_core/config/deploy.yml`, `app_fetcher/config/deploy.yml`
- `app_core/Dockerfile`, `app_fetcher/Dockerfile`
- `app_core/Dockerfile.dev`, `app_fetcher/Dockerfile.dev`
- `app_core/.kamal/secrets`, `app_fetcher/.kamal/secrets`
- `script/deploy`
- `docker-compose.yml` (the `build:` entries only)

## Related ADR

- `agent/adr/deployment-via-kamal.md` — why one VPS, two services, one
  proxy, accessories, and Docker Hub
- `agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md` — the
  browser-to-fetcher decision that requires a public `api.` origin
- `agent/adr/ci-via-docker-compose.md` — why the compose/dev image must
  keep working
