# Deploy from GitHub Actions after CI

## Status

Accepted

## Context

The Kamal topology is in place (`agent/adr/deployment-via-kamal.md`):
two services on one VPS behind `kamal-proxy`, Postgres/Redis accessories,
images in Docker Hub. Releases were performed by a developer running
`bin/kamal deploy` (or `script/deploy`) from a laptop.

That has three problems for a solo project:

- the deploy depends on the developer's machine having the right Ruby
  toolchain, the Docker daemon, the SSH key, and every production secret
  exported in the shell;
- there is no automatic link between a green CI run and what is running
  in production — a merge can sit undeployed, or a manual deploy can ship
  a commit that never passed CI;
- the first deployment of a fresh server has to be executed by hand.

The Rails guide suggested fetching secrets from 1Password
(`kamal secrets fetch --adapter 1password`). There is no 1Password
account in this project, and a secret store would still have to hand the
values to CI for SSH and the registry.

## Decision

Deployment runs in **GitHub Actions**, in `.github/workflows/deploy.yml`:

- triggered by `workflow_run` when the `CI` workflow completes
  successfully on `main`, and by `workflow_dispatch` with a
  `command` input (`deploy` or `setup`) for manual runs and first
  bootstrapping;
- one job, `environment: production`, `concurrency: production-deploy`
  with `cancel-in-progress: false`;
- checks out the SHA the CI run tested, installs Ruby 3.3 + the pinned
  Kamal gem (no app bundle on the runner), configures a **dedicated
  SSH deploy key**, and runs `kamal setup`/`kamal deploy` in
  `app_fetcher` first and `app_core` second;
- all production secrets live in **GitHub Actions Secrets**
  (`SSH_PRIVATE_KEY`, `KAMAL_REGISTRY_PASSWORD`, `DB_PASSWORD`, one
  `RAILS_MASTER_KEY` per app, the three shared JWT secrets);
- `.kamal/secrets` reads `RAILS_MASTER_KEY` from the environment, so the
  workflow and a local `script/deploy` use the same contract;
- the server IP, domain, and Docker Hub username stay in
  `config/deploy.yml` — they are not secret.

The first deployment of a fresh server is the `workflow_dispatch` run
with `command: setup`; every later push to `main` deploys automatically
after CI.

## Alternatives Considered

### Alternative: keep manual local deploys with secrets in 1Password

Rejected because:

- It does not remove the dependency on the developer's machine for
  releases and does not tie production to a green CI run.
- It adds a paid account and a second secret store; GitHub Actions still
  needs its own secrets for SSH and the registry, so the values would be
  duplicated.

### Alternative: add a `deploy` job to the existing `ci.yml`

A job with `needs: [linters, tests]`, gated to `push` on `main`.

Rejected because:

- It mixes verification with production mutation in one workflow, and
  gives every CI step the deploy environment/secrets by default.
- It cannot cleanly expose a manual `setup` command without re-running
  all linters and both suites for a bootstrap.
- A separate workflow keeps deploy permissions (`contents: read`,
  `environment: production`) and its own concurrency policy scoped to
  production.

### Alternative: deploy on every push with `workflow_run`-less triggers

Rejected because:

- It would deploy commits that failed lint/type/test checks.
- `workflow_run` gives exactly the "CI passed on main" semantics.

### Alternative: build images on the server

Rejected because:

- The VPS is 1 vCPU / 2 GB; building two Rails images plus npm there
  would starve the running apps and duplicate work the runner already
  does.
- The runner has buildx and pushes to Docker Hub in the same workflow.

### Alternative: `SSH_KNOWN_HOSTS` secret instead of `ssh-keyscan`

Deferred, not rejected: the workflow currently does a first-use
`ssh-keyscan` of the one known IP. Storing the host key as a secret is
stricter and can be added later without changing the rest of the design.

If it is added, the secret must hold plain, unhashed known_hosts lines
(`ssh-keyscan <ip>`, without `-H`). SSHKit 1.25.1 returns only the first
matching hashed entry, while `ssh-keyscan -H` writes one hashed line per
key type, so a hashed file leaves only one algorithm trusted; when sshd
negotiates ed25519, Kamal aborts with `Net::SSH::HostKeyMismatch`. Plain
lines for the same host are accumulated and verify normally.

## Consequences

### Positive

- A merge to `main` that passes CI reaches production without manual
  commands.
- Production secrets live in one encrypted store scoped to the repo;
  nothing secret is committed or baked into images.
- The deploy is reproducible: same Ruby, same Kamal version, same steps.
- The first deployment is a recorded, repeatable `setup` run.
- Local manual deploys remain possible for debugging with the same
  secrets contract.

### Negative

- Debugging a failed deploy happens through workflow logs instead of a
  local terminal.
- The workflow must be on `main` before automatic deploys work, so the
  very first pipeline run requires the human to merge and dispatch.
- GitHub Actions Secrets require write access to manage; a compromised
  collaborator account can read them.

### Risks

- 2 GB RAM on the server: two Puma processes, Sidekiq, two Postgres and
  Redis leave little headroom. Swap (2 GB) and
  `SIDEKIQ_CONCURRENCY: 3` are in place; memory must be watched.
- Let's Encrypt rate limits if a broken config is retried repeatedly.
- `workflow_run` can queue an older SHA behind a newer one; the
  no-cancel concurrency group keeps runs sequential but not necessarily
  in commit order.
- Docker Hub rate limits/credentials: a bad token fails before the
  server is touched.

## Implementation Constraints

- The deploy workflow lives only at `.github/workflows/deploy.yml` and
  triggers on the `CI` workflow name.
- Secrets are referenced only via `${{ secrets.* }}`; no literal values
  in the repo, Dockerfiles, `deploy.yml`, or `.kamal/secrets`.
- `RAILS_MASTER_KEY` is resolved from the environment in
  `.kamal/secrets`; CI maps `RAILS_MASTER_KEY_FETCHER` /
  `RAILS_MASTER_KEY_CORE` onto it per step.
- Deploy order is always `app_fetcher` → `app_core`.
- The Kamal gem is pinned to the version in both `Gemfile.lock`s
  (currently 2.11.0).
- The workflow must not cancel an in-flight deploy.
- Manual `script/deploy` stays available and uses the same env-var
  contract.

## Related

- `agent/styleguides/deployment.md` — the "how" companion
- `agent/adr/deployment-via-kamal.md` — the topology this executes
- `agent/adr/ci-via-docker-compose.md` — the CI whose success gates the
  deploy
- `.github/workflows/deploy.yml`, `agent/plans/ci-deploy-via-github-actions.md`
