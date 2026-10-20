# Deploy Both Apps with Kamal on One VPS

## Status

Accepted

## Context

The monorepo contains two Rails 7.2 applications that are deployed
together but are independent processes:

- `app_core` — user-facing Turbo/Stimulus app with Vite-built React
  islands. It stores its own data in Postgres and never proxies
  `app_fetcher` traffic: the islands call `app_fetcher` directly from the
  browser with a short-lived bridge JWT (see
  `agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md`).
- `app_fetcher` — API-only service with its own Postgres database, Redis
  (Sidekiq queues + the price stream), and Sidekiq/sidekiq-cron workers.

Consequences already fixed by that architecture:

- `app_fetcher` must be reachable from the browser, so it needs a public
  origin distinct from `app_core`; its CORS allowlist is
  `ENV.fetch("APP_CORE_ORIGIN")` with no default.
- The two apps share three secrets (`APP_BRIDGE_JWT_SECRET`,
  `APP_ADMIN_BRIDGE_JWT_SECRET`, `APP_DEMO_JWT_SECRET`) but have separate
  databases and separate Rails credentials/master keys.
- `app_core` uses Redis database `/3` for signed-out demo sessions
  (`Demo::SessionStore`, `REDIS_URL_DEMO`); `app_fetcher` uses `/0` for
  Sidekiq and `/2` for the price stream. One Redis instance serves both.

Current state: the project has never been deployed. `kamal` 2.11 is in
both Gemfiles, and each app has the stock generated `config/deploy.yml` /
`.kamal/secrets`, but both Dockerfiles are development images (single
stage, `WORKDIR /app`, no `RAILS_ENV=production`, no asset/Vite build,
`CMD rails server`) used by `docker-compose.yml`, git hooks, and CI.

The owner wants the cheapest workable production setup: one rented VPS,
one already-owned domain, no managed database, no deep DevOps investment,
no CI-driven deployment at first.

## Decision

Deploy both apps to **one Ubuntu LTS VPS** with **Kamal 2**, using **two
independent Kamal configurations**, one per app directory:

- `app_core/config/deploy.yml` → `service: steam-core`, image
  `steam-core`, web role only, `db` accessory.
- `app_fetcher/config/deploy.yml` → `service: steam-fetcher`, image
  `steam-fetcher`, `web` + single-host `job` role, `db` and `redis`
  accessories.

Both services sit behind the **single shared `kamal-proxy`** on that
host, each registered under its own hostname:

- `app.<domain>` → `app_core`
- `api.<domain>` → `app_fetcher`

TLS is issued by Let's Encrypt through `kamal-proxy`. Postgres 15 and
Redis 7 run as Kamal **accessories on the same VPS**, on data volumes,
with **no host port publishing** — app containers reach them by their
stable accessory container names over Kamal's fixed `kamal` Docker
network. `app_core` reaches the Redis accessory declared by the fetcher
configuration (`steam-fetcher-redis`) for its demo-session database; this
is the one cross-app runtime dependency besides the public HTTPS API.
Images are stored in **Docker Hub** (free, matching the official
Rails deployment guide). Release execution later moved to GitHub
Actions — see `agent/adr/ci-deploy-via-github-actions.md`; this ADR
still owns the topology.

The production image is `Dockerfile` (Rails 7.2 production template,
multi-stage, non-root, entrypoint, port 3000). The current development
image is preserved as `Dockerfile.dev`, and `docker-compose.yml` builds
that one, so dev, git hooks, and CI keep working unchanged.

## Alternatives Considered

### Alternative: One Kamal configuration for the whole monorepo

Rejected because:

- Kamal deploys one image per `service`; there is no per-role image. Two
  applications cannot be represented by one configuration without merging
  them into one container.
- Merging them into one image (both Puma processes plus Sidekiq under a
  process supervisor) would change the application architecture, couple
  release cycles that are currently independent, and make the API-only
  service inherit the frontend toolchain.

### Alternative: `docker compose` on the VPS plus Caddy/Traefik

Rejected because:

- The existing compose file is a development artifact (bind mounts, dev
  images, no TLS, no health-gated zero-downtime rollout). Turning it into
  a production stack means writing the reverse-proxy/TLS/release logic
  that Kamal already provides.
- No zero-downtime deploys, no built-in rollback, and manual certificate
  management.

### Alternative: Managed Postgres and Redis

Rejected for the first iteration because:

- It adds a second provider, network egress, TLS configuration for
  internal services, and recurring cost, for a two-app hobby-scale
  deployment.
- Accessories keep everything on one bill and one backup surface. The
  decision can be revisited without changing the application code, since
  connections are already env-driven.

### Alternative: A separate infrastructure host for Postgres/Redis

Rejected because:

- Doubles the server cost and adds private networking for no benefit at
  this scale.

### Alternative: One public hostname, proxying fetcher calls through `app_core`

Rejected because:

- It contradicts the accepted no-proxy decision
  (`thin-controllers-actions-direct-fetcher-reads.md`): `app_core` would
  have to re-implement the API surface and authorization it deliberately
  avoids, and the islands' direct bridge-token flow would be replaced.
- The fetcher is already designed to be called cross-origin, with an
  origin allowlist.

### Alternative: GHCR instead of Docker Hub

Rejected for now because:

- The official Rails deployment guide uses Docker Hub, which makes the
  first deployment the most documented path.
- The image registry is a one-line `registry:` change; moving to GHCR
  later is a migration, not an architectural change.

### Alternative: Kamal's local registry (`localhost:5555`)

Rejected because:

- It requires running and maintaining a registry container plus SSH port
  forwarding on every build, and offers no benefit over a free hosted
  registry for a single developer.

## Consequences

### Positive

- One server, one proxy, one bill; TLS and zero-downtime releases come
  from Kamal without custom infrastructure.
- `app_core` and `app_fetcher` keep separate images, release cycles, and
  databases; a fetcher release cannot break the dashboard deploy.
- The dev/CI stack is untouched: the same Dockerfiles keep serving
  `docker-compose.yml`, and production images are added alongside.
- Local production-image smoke tests are possible before a server exists
  (build the image, run it against throwaway Postgres/Redis).
- The topology matches the accepted browser-to-fetcher architecture, so
  CORS and bridge tokens work exactly as in development.

### Negative

- Two deploy commands (mitigated by `script/deploy`) and two
  configurations to keep consistent.
- Both apps share one proxy and one `kamal` network, so proxy settings
  (`ssl`, `app_port`) must stay in sync.
- Two Postgres instances and a Redis instance consume memory; the VPS
  must be sized for ~4 GB, not the 1 GB the Rails guide assumes.
- Docker Hub's free plan allows one private repository, so the two images
  are public.
- Deploys are driven by CI (see `ci-deploy-via-github-actions.md`); a
  manual local deploy remains possible for debugging.

### Risks

- A missing or mismatched `RAILS_MASTER_KEY` (one per app) prevents boot;
  the key is not in the repository.
- `APP_CORE_ORIGIN` is boot-critical for `app_fetcher` (no default in the
  CORS initializer).
- Scaling the `job` role past one host would duplicate sidekiq-cron
  schedules.
- `app_core` now depends on the fetcher's Redis accessory for demo
  sessions: if Redis is down, demo routes degrade (the controllers rescue
  `Redis::BaseError`) but the app still boots. The accessory must be
  booted before `app_core` is deployed.
- `db:prepare` on first boot must not be pointed at unused Solid
  databases without schema files; production DB lists are trimmed to what
  each app actually uses.
- Vite assets must be compiled inside the image, or the dashboard renders
  without JavaScript.
- Asset bridging covers propshaft assets only; Vite chunks are not
  bridged, so an in-flight old page may briefly 404 a chunk during a
  release.

## Implementation Constraints

- Two Kamal configurations, one per app directory; `service` and `image`
  must be distinct (`steam-core`, `steam-fetcher`). The stock
  `service: app` cannot stay.
- Both configs set `proxy.ssl: true` and `proxy.app_port: 3000`; only
  `proxy.host` differs. Kamal's proxy is shared on the host.
- Accessories are named `db` (and `redis` for the fetcher) so their
  container names are stable (`steam-core-db`, `steam-fetcher-db`,
  `steam-fetcher-redis`); they publish no host ports and use data
  directories/volumes.
- The fetcher runs exactly one `job` role host with
  `cmd: bundle exec sidekiq -C config/sidekiq.yml`.
- Production images are built from `Dockerfile`; `docker-compose.yml`
  builds `Dockerfile.dev`. The two must not be swapped.
- `app_core`'s image runs `bin/vite build` at build time and removes
  `node_modules` before the final stage.
- Production database configuration is driven by `DB_HOST`, `DB_USER`,
  `DB_PASSWORD`; `app_core` keeps only `primary`, `app_fetcher` keeps
  `primary` + `cache`.
- Non-secret configuration lives in `env.clear`; secrets are referenced
  through `env.secret` and resolved from `.kamal/secrets`.
- `.kamal/secrets` contains references (`$(...)`, `$VAR`) only. The
  three JWT secrets are identical across apps; `RAILS_MASTER_KEY` is per
  app.
- `REDIS_URL` points at `/0` and `REDIS_URL_STREAM` at `/2` on the
  fetcher; the initializer's `localhost` default is not valid in
  production. `app_core` sets `REDIS_URL_DEMO` to `/3` on the same
  accessory.
- `SOLID_QUEUE_IN_PUMA` must not be set: neither app uses Solid Queue.
- Deploy order: fetcher first, then core (Redis is an accessory of the
  fetcher configuration; core only depends on the fetcher over HTTPS).
- Migrations run before traffic switches (entrypoint or pre-deploy hook).

## Related

- `agent/styleguides/deployment.md` — the "how" companion to this "why"
- `agent/adr/core/thin-controllers-actions-direct-fetcher-reads.md` —
  why the fetcher needs its own public origin
- `agent/adr/ci-via-docker-compose.md` — why the dev/CI images must keep
  building from the compose stack
- `agent/plans/deploy-via-kamal.md` — the implementation plan
