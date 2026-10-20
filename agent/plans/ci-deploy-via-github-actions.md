---
status: implemented
app: fetcher+core
goal: Deploy both apps from GitHub Actions after CI passes — first bootstrapping via a manual workflow run, then automatically on every push to main — with all production secrets held in GitHub Actions Secrets and no manual deploy commands.
created: 2026-10-20
---

# Development Plan

## Goal

Move production deployment of `app_core` and `app_fetcher` from a local
`bin/kamal deploy` into a GitHub Actions workflow:

- a push to `main` that passes CI deploys both apps automatically;
- a fresh server is bootstrapped by a manual `workflow_dispatch` run with
  `command: setup`;
- every secret lives in **GitHub Actions Secrets** (encrypted, available
  only to workflows on the repository), not in the repo or a file.

The already-implemented Kamal topology (two services, one proxy,
accessories, Docker Hub) stays unchanged.

## Expected Behavior

- `CI` succeeds on `main` → `Deploy` workflow starts, builds both images
  on the runner, pushes them to Docker Hub, and releases `app_fetcher`
  then `app_core` with zero downtime.
- `CI` fails → no deployment. Automatic deploys are gated by the
  repository variable `DEPLOY_ENABLED=true`, so the first merge after
  this change does not try to deploy an unbootstrapped server.
- `workflow_dispatch` with `command: setup` on a fresh server installs
  Docker, boots the proxy and accessories, and deploys both apps;
  `command: deploy` performs a normal release.
- Two deploys never overlap (`concurrency` without cancel).
- Missing/incorrect secrets fail the workflow before any server change
  (SSH/registry/Kamal config resolution), never half-deploy silently.
- A developer can still deploy manually from their machine with
  `script/deploy`, using the same env-var/secrets contract.
- No secret value appears in the repository, the images, or workflow logs.

Behavior that must remain unchanged: the CI workflow and its checks, the
local compose stack, application code, and both apps' test suites.

## Scope

### In Scope

- `.github/workflows/deploy.yml`: trigger on CI success + manual dispatch,
  Ruby/Kamal setup, SSH setup, per-app secret mapping, ordered deploy.
- `.kamal/secrets` in both apps: read `RAILS_MASTER_KEY` from the
  environment instead of `config/master.key`, so CI and local runs share
  one contract.
- `config/deploy.yml` in both apps: replace the placeholders with the
  real server IP, domain, and Docker Hub user; add
  `SIDEKIQ_CONCURRENCY: 3` for the 2 GB droplet; raise `deploy_timeout`.
- `agent/styleguides/deployment.md`: add the CI-deployment rules.
- `agent/adr/ci-deploy-via-github-actions.md`: the decision record.
- `agent/adr/deployment-via-kamal.md`: note that release execution moved
  to CI.

### Out of Scope

- Changing the deployment topology, images, or accessories.
- A staging environment or per-app deployment triggers.
- 1Password/Bitwarden integration (GitHub Secrets is the chosen store).
- Automated backups, monitoring, uptime checks.
- Server provisioning beyond the one-time swap/deploy key already done.

## Implementation Approach

**Workflow shape**

`.github/workflows/deploy.yml`, job `deploy`:

- `workflow_run` on `CI` completed for `main`, gated on
  `conclusion == 'success'`; plus `workflow_dispatch` with an input
  `command` (`deploy` | `setup`, default `deploy`).
- Check out the exact SHA that CI tested
  (`github.event.workflow_run.head_sha || github.sha`).
- `ruby/setup-ruby` with Ruby 3.3, then `gem install kamal -v 2.11.0`
  (Kamal runs on the runner; no app bundle needed, so no per-app
  `bundle install`).
- Write `SSH_PRIVATE_KEY` to `~/.ssh/id_ed25519` (chmod 600) and
  `ssh-keyscan -H <server-ip>` into `known_hosts`.
- Two deploy steps, `app_fetcher` then `app_core`, each exporting the
  shared secrets plus that app's `RAILS_MASTER_KEY` and running
  `kamal ${{ inputs.command || 'deploy' }}` from the app directory.
- `environment: production`, `permissions: contents: read`,
  `concurrency: group: production-deploy`, `cancel-in-progress: false`.
- The job runs on `workflow_run` only when `vars.DEPLOY_ENABLED == 'true'`;
  `workflow_dispatch` always runs, so bootstrap is not blocked.

**Secrets (GitHub Actions Secrets)**

| Secret | Value |
|---|---|
| `SSH_PRIVATE_KEY` | private key of the dedicated deploy key |
| `KAMAL_REGISTRY_PASSWORD` | Docker Hub access token (Read & Write) |
| `DB_PASSWORD` | Postgres superuser + app DB password |
| `RAILS_MASTER_KEY_FETCHER` | `app_fetcher/config/master.key` |
| `RAILS_MASTER_KEY_CORE` | `app_core/config/master.key` |
| `APP_BRIDGE_JWT_SECRET` | shared, both apps |
| `APP_ADMIN_BRIDGE_JWT_SECRET` | shared, both apps |
| `APP_DEMO_JWT_SECRET` | shared, both apps |

`config/deploy.yml` holds only non-secret values (server IP, domain,
Docker Hub username, accessory hosts). A repository **variable**
`DEPLOY_ENABLED=true` gates automatic deploys; manual dispatch ignores it.

**Memory**

The droplet is 1 vCPU / 2 GB (2 GB swap added). Keep Puma single-mode and
set `SIDEKIQ_CONCURRENCY: 3`; no image building happens on the server
(the runner builds and pushes).

## Files To Modify

- `app_core/.kamal/secrets`, `app_fetcher/.kamal/secrets` —
  `RAILS_MASTER_KEY=$RAILS_MASTER_KEY` instead of `cat config/master.key`.
  Reason: CI has no checkout-level key file.
- `app_core/config/deploy.yml` — real `<dockerhub-user>`, `<server-ip>`,
  `app.<domain>`; `deploy_timeout: 120`.
- `app_fetcher/config/deploy.yml` — same, plus
  `api.<domain>`, `APP_CORE_ORIGIN`, `SIDEKIQ_CONCURRENCY: 3`.
- `agent/styleguides/deployment.md` — new "CI deployment" section.
- `agent/adr/deployment-via-kamal.md` — point the execution note at the
  new ADR.

## Files To Create

- `.github/workflows/deploy.yml` — the deployment pipeline.
- `agent/adr/ci-deploy-via-github-actions.md` — why CI-driven deploys,
  GitHub Secrets, a dedicated SSH key, and `workflow_run` after CI.

## Test Plan

No application tests change. Verification:

1. YAML is valid and the workflow passes `actionlint`.
2. `kamal config` renders in both apps with the real values and
   env-provided secrets.
3. `git grep` confirms no secret material was committed.
4. The workflow itself is exercised by the first `workflow_dispatch`
   (`setup`) run on GitHub after the branch is pushed — this is the real
   integration test and replaces a local manual deploy.
5. After the run: `https://app.cs2-loadout.pro/up` and
   `https://api.cs2-loadout.pro/up` return 200 over TLS; demo flow and
   Sidekiq cron are checked; a second push to `main` proves the
   `workflow_run` path.

## Implementation Steps

1. Update both `.kamal/secrets` to env-based `RAILS_MASTER_KEY`.
2. Fill real IP/domain/username in both `config/deploy.yml`; add
   `SIDEKIQ_CONCURRENCY: 3` and `deploy_timeout: 120`.
3. Add `.github/workflows/deploy.yml`.
4. Add the CI-deploy ADR and amend the deployment ADR's execution note.
5. Add the "CI deployment" rules to the deployment styleguide.
6. Validate YAML/actionlint and `kamal config`; check the diff for
   secrets.
7. Commit locally; the human adds the eight secrets, pushes, runs the
   first `setup` dispatch, then sets `DEPLOY_ENABLED=true`.

## Verification

```bash
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest
(cd app_fetcher && bin/kamal config)   # with secrets exported
(cd app_core && bin/kamal config)
git grep -nE 'BEGIN OPENSSH|ghp_|dckr_|APP_BRIDGE_JWT_SECRET=[0-9a-f]{32}' || true
```

Then, on GitHub: Actions → Deploy → Run workflow → `setup`.

## Risks

- **2 GB RAM.** Two Rails processes + Sidekiq + two Postgres + Redis is
  close to the limit; swap and concurrency 3 mitigate it, but the first
  hours should be watched (`kamal logs`, `free -m`).
- **Let's Encrypt rate limits** if the first deploy is retried many times
  with the same hostnames. Fix config errors before re-running.
- **`workflow_run` only fires for workflows on the default branch** —
  the deploy workflow must be merged to `main` before automatic deploys
  start working.
- **SSH host-key trust on first use** (`ssh-keyscan`); acceptable for a
  single known server, can be replaced by a `SSH_KNOWN_HOSTS` secret.
- **Docker Hub repositories** are expected to be created on first push;
  if the token lacks permission the workflow fails before touching the
  server.
- **Secrets in a public repo**: GitHub Actions secrets are not exposed to
  forks, but any collaborator with write access can read them.

## Assumptions

- The human adds the eight repository secrets and pushes `main`.
- Docker Hub user `olegkovalevswe`, repositories `steam-core` and
  `steam-fetcher` (public or private, token must allow push).
- Domain `cs2-loadout.pro` with DNS-only records for `app` and `api`
  (verified: both resolve to the VPS).
- The server is fresh; the dedicated deploy key is already authorized.
- GitHub Actions is enabled for the repository and `main` is the default
  branch.

## Applicable Styleguides

- `agent/styleguides/deployment.md` — the primary guide: CI deployment
  rules (trigger on green CI, `setup` only for bootstrap, GitHub Secrets
  contract, deploy order, non-cancelling concurrency, pinned Kamal).
- `agent/styleguides/ci-and-coverage.md` — constrains where workflow
  files live (repo root only) and keeps the existing verification
  workflow untouched and separate.
- `agent/styleguides/git-commits.md` — the commit that ships this change
  (`[Core+Fetcher]` scope, subject-only).

## Completion Criteria

- The workflow is valid, committed, and contains no secret values.
- Both apps' `.kamal/secrets` work with env-provided master keys.
- `kamal config` is valid with the real server/domain values.
- The deployment styleguide and ADR describe the CI path.
- The only remaining human steps are adding GitHub secrets, pushing, and
  running the first `setup` dispatch.

# Implementation Summary

## Implemented

- `.github/workflows/deploy.yml`: deploys both apps from GitHub Actions.
  Triggers on `CI` success for `main` (gated by the `DEPLOY_ENABLED`
  repository variable) and on `workflow_dispatch` with
  `command: deploy|setup`. Checks out the tested SHA, installs Ruby 3.3
  and Kamal 2.11.0, writes the dedicated SSH key, and runs
  `kamal <command>` in `app_fetcher` then `app_core`.
- `.kamal/secrets` (both apps): `RAILS_MASTER_KEY=$RAILS_MASTER_KEY`
  from the environment, so CI and local deploys share one contract.
- `config/deploy.yml` (both apps): real values filled in — server
  `134.209.196.226`, hosts `app.cs2-loadout.pro` / `api.cs2-loadout.pro`,
  Docker Hub user `olegkovalevswe`; `deploy_timeout` raised to 120 for
  the 1 vCPU droplet and `SIDEKIQ_CONCURRENCY: 3` added for its 2 GB of
  RAM.
- `agent/adr/ci-deploy-via-github-actions.md`: decision record.
- `agent/styleguides/deployment.md`: CI-deployment section, secret-name
  table, `DEPLOY_ENABLED` gate, bootstrap/release/rollback procedure.
- `agent/adr/deployment-via-kamal.md`: execution note now points at the
  CI ADR.

Server provisioning done separately (not part of the repo change):
2 GB swap file enabled and a dedicated deploy key
(`~/.ssh/gha_cs2_loadout.pub`) authorized for `root`.

## Tests

No application specs changed. Validation performed:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy.yml'))"
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest
(cd app_fetcher && bin/kamal config)   # real values + env secrets
(cd app_core && bin/kamal config)
```

## Verification

- Workflow YAML parses and passes `actionlint` with no findings.
- `bin/kamal config` renders successfully in both apps with the real
  server/domain/registry values and env-provided secrets.
- `git grep` found no committed secret material.
- The end-to-end check is the first `workflow_dispatch` (`setup`) run on
  GitHub after the human adds secrets and pushes; it cannot be executed
  locally.

## Deviations

- Added the `DEPLOY_ENABLED` repository-variable gate, which was not in
  the original plan. Without it, the first merge (before the server is
  bootstrapped) would trigger an automatic `kamal deploy` and fail; with
  it, automatic deploys stay off until the `setup` dispatch succeeds.
- `RAILS_MASTER_KEY` switched from `$(cat config/master.key)` to an
  environment variable in `.kamal/secrets`; CI has no checkout-level key
  file, and this keeps one contract for CI and local runs.

## Remaining Issues

Human-owned steps before the first live deploy:

1. Add the eight repository secrets (values live in
   `~/.config/kamal/steam-deploy.env`, `~/.ssh/gha_cs2_loadout`, and each
   app's `config/master.key`; the Docker Hub token is the user's).
2. Push/merge this branch to `main`.
3. Actions → **Deploy** → *Run workflow* → `command: setup`.
4. After it succeeds, set the repository variable
   `DEPLOY_ENABLED=true` to enable automatic deploys.

Known follow-ups: watch memory on the 2 GB droplet, replace
`ssh-keyscan` with an `SSH_KNOWN_HOSTS` secret, and add monitoring and
backups.
