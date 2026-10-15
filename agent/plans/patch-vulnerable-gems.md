---
status: implemented
app: fetcher+core
goal: Get `bin/bundler-audit` green in both apps by patching the flagged gems to their minimum safe versions on Rails 7.2.x, without pulling unrelated major bumps.
created: 2026-10-15
---

# Development Plan

## Goal

Close the `bundler-audit` follow-up recorded in
`agent/plans/add-ci-and-git-hooks.md` ("Remaining Issues"): the audit
step is blocking in CI and currently red in both apps. Patch the ~18
flagged gems to their minimum safe versions — staying on the Rails 7.2
line and within the existing `Gemfile` constraints — so
`bin/bundler-audit` exits 0 in `app_fetcher` and `app_core`.

## Expected Behavior

- `bin/bundler-audit` (as CI calls it: no args → `check` with
  `config/bundler-audit.yml`) exits **0** in both apps.
- No advisory remains for any of the flagged gems; the existing ignore
  lists stay empty (nothing is silenced).
- Rails stays on `7.2.x` (resolved to `7.2.4`), `puma` stays on `7.x`,
  `json` stays on `2.x` — no Gemfile constraint is loosened or widened to
  make the audit pass.
- Both apps still boot and their full suites stay green: RSpec x2 and
  vitest.
- Behavior that must remain unchanged: no application code changes, no
  `.rubocop.yml`/`srb`/`config/ci.rb` changes, no new ignore entries, no
  Ruby/Node/Postgres/Redis version changes.

## Scope

### In Scope

- `app_fetcher/Gemfile.lock`, `app_core/Gemfile.lock` — patch the flagged
  gems (see the target table in Implementation Approach).
- `app_core` additionally needs `vite_ruby` bumped: the locked `3.10.2`
  pins `rack-proxy` via `~> 0.6` (upper bound `< 1.0`), which is the only
  reason `rack-proxy` (fix: `>= 1.0.3`) cannot be reached. The target is
  `3.10.6`, not the newest `3.11.1` — see the `vite-plugin-ruby` gate
  below.
- Rebuilding both images (gems are installed at build time).
- Docs that record this follow-up: `agent/plans/add-ci-and-git-hooks.md`.

### Out of Scope

- A Rails 8 / Ruby upgrade — `activestorage`/`actionview`/
  `activesupport` are satisfied by `7.2.4`; the `EOLRails` Brakeman
  warning stays intentionally skipped (see the Brakeman entry in the
  same Remaining Issues list).
- A general `bundle update` of unrelated gems (e.g. `image_processing`,
  `minitest`, `kamal`, `bootsnap`). Specifically avoid `puma 8.x` and
  `json 3.x`.
- Ignoring any advisory instead of patching it.
- Fixing the pre-existing `srb tc` errors — the `linters` job stays red
  on those regardless of this change.
- Frontend (`npm`) dependencies. `rack-proxy`/`vite_ruby` are Ruby gems,
  but `vite_ruby` gates itself against the npm `vite-plugin-ruby` range —
  staying on `vite_ruby 3.10.6` is exactly what keeps the npm side out of
  scope (see Implementation Approach).

## Implementation Approach

All flagged gems are transitive except `puma` (both apps) and `faraday`
(`app_fetcher`); none are version-pinned in a `Gemfile` except
`puma ">= 5.0"` (unbounded) and `rails "~> 7.2.0"`. Every advisory has an
available fix, so no ignore entries are needed.

Target versions (minimum fixed → what to resolve to):

| Gem | Now (fetcher / core) | Advisory requires | Target |
| --- | --- | --- | --- |
| rails + actionview/activesupport/activestorage/actionpack/... | 7.2.3.1 / 7.2.3 | `>= 7.2.3.1`, `>= 7.2.3.2` | **7.2.4** |
| concurrent-ruby | 1.3.6 | `>= 1.3.7` | 1.3.8 |
| crass | 1.0.6 | `>= 1.0.7` | 1.0.7 |
| erb | 6.0.2 | `>= 6.0.4` | 6.0.7 |
| faraday (direct, fetcher) | 2.14.1 | `>= 2.14.3` | 2.14.4 |
| json | 2.19.3 | `>= 2.19.9` | **2.20.0 (2.x only)** |
| loofah | 2.25.1 | `>= 2.25.2` | 2.25.2 |
| mail | 2.9.0 | `>= 2.9.1` | 2.9.1 |
| msgpack | 1.8.0 | `>= 1.8.2` | 1.8.5 |
| net-imap | 0.6.3 | `>= 0.6.4.1` | 0.6.8 |
| nokogiri | 1.19.2 | `>= 1.19.4` | 1.19.4 |
| puma (direct, both) | 7.2.0 | `~> 7.2.1` | **7.2.1 (not 8.x)** |
| rack | 3.2.5 | `>= 3.2.6` | 3.2.7 |
| rack-session | 2.1.1 | `>= 2.1.2` | 2.1.2 |
| rails-html-sanitizer | 1.7.0 | `>= 1.7.1` | 1.7.1 |
| websocket-driver | 0.8.0 | `>= 0.8.2` | 0.8.2 |
| yard (dev only, via sorbet) | 0.9.38 | `>= 0.9.44` | 0.9.45 |
| addressable (core, test only) | 2.8.9 | `>= 2.9.0` | 2.9.0 |
| rack-proxy (core, via vite_ruby) | 0.8.3 | `>= 1.0.3` | 1.0.3 or 2.0.1 |
| vite_ruby (core, enabler) | 3.10.2 | — | 3.10.6 |

Mechanics that matter (verified during research):

- Use `bundle update --conservative <gems>` so unrelated locked gems
  don't move. A plain `bundle update` would resolve `puma` to `8.0.2`
  (`>= 5.0` has no upper bound) and could pull `json 3.x`, which
  `rubocop` forbids (`json (~> 2.3)`).
- Run the update inside the container: `Gemfile.lock` is bind-mounted, so
  the result lands in the repo, but the gems themselves are baked into
  the image by `bundle install` in each `Dockerfile` — the image must be
  rebuilt before the new versions are used locally or in CI-verified
  steps.
- `rack-proxy`: update `vite_ruby` in the same command (it now declares
  `rack-proxy (>= 0.6.1)`, no upper bound), otherwise the resolver keeps
  `0.8.3` and the advisory stands. `rack/proxy` appears nowhere in our
  own code — only vite_ruby's dev-server proxy uses it — so this is the
  one change whose blast radius is not covered by tests.
- `vite_ruby` also gates itself against the npm `vite-plugin-ruby` range:
  `ViteRuby::DEFAULT_PLUGIN_VERSION` is enforced on boot by
  `ViteRuby::Config`. `3.11.1` demands `^5.2.5`, while
  `app_core/package.json` declares `^5.2.2` — so that version fails boot
  with `ArgumentError` unless the npm package moves too, which is out of
  scope. `3.10.6` already declares `rack-proxy (>= 0.6.1)` and still
  accepts `^5.2.2`, satisfying both sides.
- `puma` and `json` are the two gems where "resolve latest" must be
  explicitly avoided; the `Gemfile` is not edited to do this, the update
  is just scoped.

## Files To Modify

- `app_fetcher/Gemfile.lock` — patch the table's gems (no `vite_ruby` /
  `rack-proxy` / `addressable` here; `addressable` is only reached via
  `webmock` and is already fixed in this app's resolution). Reason: turn
  the audit step green.
- `app_core/Gemfile.lock` — same set, plus `addressable`, `vite_ruby`,
  `rack-proxy`. Reason: same, plus the `rack-proxy` enabler.
- `agent/plans/add-ci-and-git-hooks.md` — rewrite the `bundler-audit`
  bullet in "Remaining Issues" from "fix is patching those gems (a
  separate security task)" to the outcome (patched; note that the
  `linters` job still fails on the pre-existing `srb tc` errors).
  Reason: that list is where this follow-up is tracked.

## Files To Create

None. No new source, test, config, or styleguide file is needed: the audit
gate already exists in CI and in each `config/ci.rb`, and the fix is a
lockfile patch that needs no new convention.

## Test Plan

No new unit or request specs are warranted — this task changes dependency
versions, not behavior, and the existing suites are the regression net
for the gems we actually exercise (`app_fetcher`'s Steam client and
`lib/faraday/user_agent_rotator.rb` use `faraday` directly and are
covered by VCR/WebMock-backed specs).

The behavior that must be verified is the gate itself:

- `bin/bundler-audit` exits 0 in both apps (this is the task's actual
  acceptance test; CI already runs exactly this command).
- The resolved versions match the intent: `rails 7.2.4`, `puma 7.2.1`,
  `json 2.20.0` — asserted by reading the lockfiles, since the resolver
  could otherwise quietly pick `8.x`/`3.x`.
- Regression: existing suites stay green (RSpec x2, vitest).
- Smoke check for the one untested dependency: load vite_ruby's proxy
  class under the new `rack-proxy`, e.g. a `bundle exec ruby -e` inside
  `app_core` that requires `vite_ruby`'s proxy. This is the closest thing
  to coverage the dev-proxy path has and should be done manually, since
  the proxy only runs in development.

## Implementation Steps

1. Record the baseline: run
   `bin/bundler-audit check --update` in both apps and keep the output
   (exit 1, 59 advisories in `app_fetcher` at the time of research).
2. Patch `app_fetcher`: in a container, run `bundle update --conservative`
   with the table's gems (optionally `--patch` if bundler's resolver needs
   the hint; the target list is authoritative either way).
3. Inspect `app_fetcher/Gemfile.lock` for the diff: confirm `rails 7.2.4`,
   `puma 7.2.1`, `json 2.20.0`, and that no unrelated gem moved.
4. Patch `app_core`: same, plus `addressable vite_ruby rack-proxy`.
5. Inspect `app_core/Gemfile.lock`: the above, plus `rack-proxy >= 1.0.3`
   and `vite_ruby 3.11.1`; confirm `rack-proxy` is no longer `0.8.x`.
6. Re-run `bin/bundler-audit` in both apps; expect exit 0 with no
   `ignore` entry added.
7. Rebuild both images (`docker compose build app_fetcher app_core`) so
   the installed gems match the committed lockfiles.
8. Smoke-check the vite_ruby proxy load in `app_core` (see Test Plan).
9. Run the full suites: `rspec` in both apps, `npm run test:coverage` in
   `app_core`.
10. Re-run the other linters that could react to the gem bumps —
    `bin/brakeman` (must stay exit 0; `EOLRails` remains skipped),
    `bin/rubocop`, `bundle exec srb tc` (record any delta, do not fix
    pre-existing errors).
11. Update the `bundler-audit` bullet in
    `agent/plans/add-ci-and-git-hooks.md` ("Remaining Issues").
12. Commit.

## Verification

Run through the CI override, matching
`.github/workflows/ci.yml`/`config/ci.rb` invocations:

```bash
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.ci.yml"

$COMPOSE run --rm --no-deps app_fetcher bin/bundler-audit   # exit 0
$COMPOSE run --rm --no-deps app_core    bin/bundler-audit   # exit 0

$COMPOSE run --rm --no-deps app_fetcher bundle exec rspec
$COMPOSE run --rm --no-deps app_core    bundle exec rspec
$COMPOSE run --rm --no-deps app_core    npm run test:coverage

$COMPOSE run --rm --no-deps app_fetcher bin/brakeman --no-pager  # exit 0
$COMPOSE run --rm --no-deps app_core    bin/brakeman --no-pager  # exit 0
```

Plus: lockfile version inspection for `rails`/`puma`/`json`, and the
`app_core` vite_ruby proxy smoke load.

Not verifiable here: the full GitHub Actions run, and the vite dev-server
proxy against a real frontend dev session (`bin/vite dev`).

## Risks

- **`rack-proxy` major jump (`0.8.3 → 1.x/2.x`)** is the only change
  without test coverage, because it is used exclusively by vite_ruby's
  development proxy. Mitigations: `rack/proxy` is unused in our code;
  bump `vite_ruby` in the same step (its relaxed constraint is the reason
  the jump is possible); smoke-check the proxy class load; call out the
  dev-server path as the manual check.
- **Resolver drift past the minimum**: `bundle update` takes the newest
  allowed version, which is why `puma`/`json` must be watched explicitly
  in the lockfile diff. Picking `puma 8.x` or `json 3.x` would be a
  silent scope violation even if the audit went green.
- **`faraday` is used by `app_fetcher`'s Steam client**, so its patch
  bump is behaviorally relevant; the VCR/WebMock-backed specs are the
  check. A green suite is the bar, not an assumption.
- **Rails `7.2.3 → 7.2.4`** can shift static-analysis output
  (`rubocop`/`srb tc`/`brakeman`). Re-run those steps and record any
  delta; do not absorb unrelated fixes into this change.
- **The advisory database is a moving target** (1263 advisories at commit
  `a6847b0`, 2026-10-10) — a future `--update` can flag new gems. That is
  a new task, not a reason to add ignores now.
- **The `linters` job stays red after this change** because of the
  pre-existing `srb tc` errors. This task only turns the two
  `bundler-audit` steps green; saying so avoids a false "CI is green"
  claim.

## Assumptions

- Patch-level moves stay backward compatible, as each advisory's own
  "update to" range implies.
- Patching dev-only/test-only gems (`yard` via `sorbet`, `addressable`
  via `capybara`/`webmock`) is preferable to ignoring their advisories —
  the user chose the minimal-patch approach over an ignore-list one.
- `vite_ruby 3.11.1` remains compatible with the app's existing
  `vite.config.ts`/`config/vite.json` (no API change is advertised in the
  bump; the vitest suite and the proxy smoke check are the guard).

## Applicable Styleguides

- `agent/styleguides/dependency-patching.md` — the whole patch procedure:
  update scope (`--conservative`), version selection, the
  transitive-upper-bound case, the image rebuild, and the verification
  set. Constrains **Implementation Approach**, **Implementation Steps**
  2–10, and **Risks**.
- `agent/styleguides/ci-and-coverage.md` — the gates this work has to
  satisfy and how they are invoked: `bundler-audit` is a blocking linter
  in both apps, run through the `docker-compose.ci.yml` override;
  Brakeman must stay exit 0 (no `--ensure-latest`; `EOLRails` disabled
  per app in `config/brakeman.yml`). Constrains **Verification**.
- `agent/styleguides/git-commits.md` — the commit: a change to an app's
  own `Gemfile` stays tagged with that app, so this lands as
  `Core+Fetcher` (or two per-app commits, one lockfile each). Constrains
  **Implementation Steps** 12 and **Completion Criteria**.
- `agent/styleguides/rspec-conventions.md` — binds nothing here: it
  assigns a spec level per class, and no class changes. Cited so the
  **Test Plan**'s "no new specs" reads as an explicit consequence rather
  than an omission.

## Resolved Open Questions

- **`rack-proxy` target version** — settled by `dependency-patching.md`
  (SHOULD: take the resolver's choice; don't pin a transitive gem into the
  `Gemfile` just to force a version). So the update goes in without a pin;
  the requirement to meet is `>= 1.0.3`, and Step 5 verifies the lockfile
  no longer holds `0.8.x`.
- **Commit scope** — settled by `git-commits.md`: a change to an app's own
  `Gemfile` stays tagged with that app, so `Core+Fetcher` (one commit) or
  two per-app commits (`Fetcher`, `Core`), one lockfile each. Prefer the
  latter if the two lockfile diffs stand on their own.
- **The `rack-proxy`/`vite_ruby` coupling** — settled: no longer undocumented;
  `dependency-patching.md` records the transitive-upper-bound case ("bump A
  to be allowed to bump B").

## Completion Criteria

- `bin/bundler-audit` exits 0 in both apps with no new ignore entries.
- Lockfiles show `rails 7.2.4`, `puma 7.2.1`, `json 2.20.0`, and
  `rack-proxy >= 1.0.3` in `app_core`.
- RSpec (both apps) and vitest are green; both Brakeman runs stay exit 0.
- Images rebuilt so the installed gems match the lockfiles.
- `agent/plans/add-ci-and-git-hooks.md` records the outcome.
- The change is committed with a scope tag per
  `agent/styleguides/git-commits.md` (see Resolved Open Questions).

# Implementation Summary

## Implemented

- `app_fetcher/Gemfile.lock`, `app_core/Gemfile.lock` — every flagged gem
  patched to (at most) its minimum safe version, scoped with
  `bundle update --conservative [--patch]`:
  - Rails stack → `7.2.3.2` (satisfies the `>= 7.2.3.1`/`>= 7.2.3.2`
    advisories);
  - `concurrent-ruby 1.3.8`, `crass 1.0.7`, `erb 6.0.7`, `json 2.19.9`,
    `loofah 2.25.2`, `mail 2.9.1`, `msgpack 1.8.5`, `net-imap 0.6.8`,
    `nokogiri 1.19.4`, `puma 7.2.1`, `rack 3.2.7`, `rack-session 2.1.2`,
    `rails-html-sanitizer 1.7.1`, `websocket-driver 0.8.2` (both apps);
  - `faraday 2.14.4`, `yard 0.9.45` (`app_fetcher`);
  - `addressable 2.9.0`, `rack-proxy 2.0.1`, `vite_ruby 3.10.6`
    (`app_core`, the last two being the transitive-upper-bound pair).
  No `ignore` entry was added to either `config/bundler-audit.yml`.
- `agent/styleguides/dependency-patching.md` — new shared styleguide, the
  gap `styleguides-check` blocked on; approved by the user.
- Both images rebuilt so the baked gems match the committed lockfiles.
- Docs: this plan (targets corrected, Open Questions resolved), and the
  `bundler-audit` bullet in `agent/plans/add-ci-and-git-hooks.md`'s
  Remaining Issues.

## Tests

No new or changed specs. The plan's Test Plan argued none were warranted —
no behavior changed, and `rspec-conventions.md` assigns spec levels per
class, of which none changed. The acceptance test is the audit gate, which
flipped RED → GREEN.

Commands executed:

```bash
COMPOSE="docker compose -f docker-compose.yml -f docker-compose.ci.yml"
$COMPOSE run --rm --no-deps <app> bin/rails db:test:prepare
$COMPOSE run --rm --no-deps -e COVERAGE=1 <app> bundle exec rspec
$COMPOSE run --rm --no-deps app_core npm run test:coverage
$COMPOSE run --rm --no-deps <app> bin/bundler-audit
$COMPOSE run --rm --no-deps <app> bin/brakeman --no-pager
$COMPOSE run --rm --no-deps <app> bin/rubocop -f github
$COMPOSE run --rm --no-deps <app> bundle exec srb tc
```

## Verification

- `bin/bundler-audit` — exit 0, `No vulnerabilities found`, **both** apps
  (RED baseline was exit 1: 59 advisories in `app_fetcher`).
- RSpec — `app_fetcher` 378 examples / 0 failures; `app_core` 39 / 0.
- vitest (`npm run test:coverage`) — 39/39 test files pass.
- `brakeman` — exit 0, 0 security warnings, both apps (`EOLRails` remains
  disabled per app in `config/brakeman.yml`).
- `rubocop` — exit 0, 0 offenses, both apps.
- `srb tc` — `app_fetcher` 21 errors, identical to the pre-existing
  baseline recorded in `add-ci-and-git-hooks.md`; `app_core` 0 errors.
- `app_core` boots (`BOOT_OK`), `ViteRuby::CompatibilityCheck` passes with
  the untouched npm `vite-plugin-ruby ^5.2.2`, and the smoke load of
  `ViteRuby::DevServerProxy` succeeds under `rack-proxy 2.0.1`.

## Deviations

- **`vite_ruby` target is `3.10.6`, not the planned `3.11.1`.** `3.11.1`
  raises `ViteRuby::DEFAULT_PLUGIN_VERSION` to `^5.2.5` while
  `app_core/package.json` declares `vite-plugin-ruby ^5.2.2`;
  `ViteRuby::Config` enforces that range on boot, so `app_core` failed to
  load (`ArgumentError`, 8 errors outside examples in RSpec). Moving the
  npm package is out of the plan's scope, so the newest version whose
  requirement is already satisfied was taken. `3.10.6` already declares
  `rack-proxy (>= 0.6.1)` — which is what lifts the upper bound — and
  still accepts `^5.2.2`.
- **Rails resolved to `7.2.3.2`, not `7.2.4`.** The resolver picked
  `7.2.3.2` (the exact advisory minimum) both with and without `--patch`;
  per `dependency-patching.md` (take the resolver's choice, don't pin),
  that is the target met.
- **`json` resolved to `2.19.9`, not `2.20.0`** — `--patch` scoping keeps
  it on the 2.19 line, and `2.19.9` is exactly the advisory minimum.
- **`bundle update rails` also moved part of Rails' own subtree** within
  its constraints (`marcel 1.2.1`, `globalid 1.4.0`, `i18n 1.15.2`,
  `zeitwerk 2.8.3`, `rake 13.4.2`, `rdoc 8.1.0`, and several default
  gems). Unavoidable when the framework moves; all suites stay green.
- **Two entries left the lockfiles entirely:** `rdoc 8.1.0` (reached via
  `irb`) replaced its `psych (>= 4.0.0)` dependency with `prism` + `rbs`,
  so `psych` and its own dependency `stringio` are no longer in the
  resolved graph. Both are Ruby default gems, now served by the
  interpreter (`psych 5.1.2`). Checked deliberately: the advisory database
  contains no `psych` advisories, so the audit is not masking anything —
  but these two are no longer pinned or audited by this repo.
- **`--conservative` alone could not move the Rails stack**: its
  components are separate locked gems pinned by `= <rails version>`, so
  each component had to be named explicitly.
- **One process mistake, self-corrected:** the first audit run after the
  patch used an un-rebuilt image and failed to even load — exactly the
  failure mode `dependency-patching.md` now warns about. Rebuilding
  first is what the recorded MUST rules exist for.

## Remaining Issues

- The `linters` job is still red overall — on the pre-existing `srb tc`
  errors (21, `app_fetcher`), which this task deliberately left alone.
- `dependency-patching.md` does not yet cover the case this task hit: a
  Ruby gem whose newest version demands a newer version of an
  *out-of-scope* ecosystem package (npm). The rule applied here — take
  the newest gem version whose requirements are already satisfied
  elsewhere rather than widening scope — belongs there via
  `update-styleguide`.
