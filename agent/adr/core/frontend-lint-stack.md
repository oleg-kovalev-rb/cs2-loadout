# Frontend Lint & Format Stack: ESLint + Prettier

## Status

Accepted

## Context

`app_core`'s frontend (`app/frontend/**`, 118 `.js`/`.jsx` files across
several React islands) has Vitest for testing but **no** linter,
formatter, type-checker, or Stylelint. Correctness and formatting
conventions (`agent/styleguides/core/react-dashboard.md`) are enforced
only by review, and the code has drifted accordingly (e.g. quoting and
spacing inconsistencies the Ruby side would never tolerate, since
`rubocop-rails-omakase` owns Ruby formatting in both apps).

The frontend has no type layer by design — `react-dashboard.md`
explicitly states there is no TypeScript, and Sorbet covers only the Ruby
backends — so a type-checker is out of scope. What's missing is the
JS/JSX analogue of the Ruby side's lint + format enforcement.

## Decision

Adopt **ESLint** (flat config) for correctness and **Prettier** for
formatting, as the frontend's lint/format stack:

- ESLint config `app_core/eslint.config.js`, with `eslint-plugin-react`
  and `eslint-plugin-react-hooks` for JSX/React correctness, and
  `eslint-config-prettier` applied **last** so ESLint's stylistic rules
  are disabled and formatting is owned solely by Prettier.
- Prettier config `app_core/.prettierrc` (+ `.prettierignore`).
- Both are **blocking**: in CI (`npm run lint`, `npm run format:check`)
  and in the git `pre-commit` hook, over staged files.
- The existing 118 files are formatted once by Prettier, as its own
  commit isolated from behavior changes.

No Stylelint and no type-checker are added.

## Alternatives Considered

### Alternative: No lint/format tooling (status quo)

Rejected because:

- Formatting and JSX/React correctness (`react-hooks` dependency arrays,
  etc.) stay review-only and have already drifted.
- It leaves the frontend as the only part of the repo with no automated
  style gate, while Ruby has had one from the start.

### Alternative: ESLint only, no Prettier

Rejected because:

- Formatting would remain manually enforced; the point of adopting a
  formatter is to end that debate. ESLint's own stylistic rules are being
  deprecated upstream in favor of exactly this split.

### Alternative: Prettier only, no ESLint

Rejected because:

- Prettier only formats; it doesn't catch React correctness issues
  (`react-hooks/exhaustive-deps`, undefined variables, unused imports)
  that the frontend currently has no automated way to detect.

### Alternative: `standard` (StandardJS)

Rejected because:

- It bundles its own opinionated style rather than using Prettier, and
  its JSX/React-hooks coverage is weaker than the ESLint plugins above.
  The Ruby side already models "linter + separate formatter"
  (RuboCop/omakase), so ESLint + Prettier mirrors it.

### Alternative: Biome (one tool for lint + format)

Rejected because:

- It would consolidate lint and format into one fast tool, but adopting
  it means new config semantics, a less mature React-hooks plugin, and
  reviewer unfamiliarity versus the mainstream ESLint + Prettier stack.
  Worth revisiting later if the two-tool setup proves heavy.

## Consequences

### Positive

- Formatting becomes mechanical and consistent; review stops relitigating
  style.
- React-hooks and correctness issues are caught mechanically, in CI and
  locally.
- The frontend now matches the Ruby side's "linter owns correctness, a
  formatter owns style" model.

### Negative

- Two new tool dependencies (plus plugins) in `app_core/package.json`,
  and two config files.
- The one-time mass reformat touches most frontend files, producing a
  noisy (but semantics-free) diff that must be isolated.

### Risks

- The first ESLint run may surface genuine findings (unused vars,
  hook deps, missing keys) that must be fixed, not just formatted away —
  its own effort, separate from the Prettier reformat.
- `react-hooks/exhaustive-deps` can flag real code; the project must
  decide per finding whether to fix or annotate, not blanket-disable.

## Implementation Constraints

- ESLint is configured flat (`app_core/eslint.config.js`); `app_core`'s
  `package.json` already sets `"type": "module"`, so the config is ESM.
- `eslint-config-prettier` must be last in the ESLint config so the two
  tools never conflict over formatting.
- Prettier is the sole formatter; ESLint must not own stylistic rules.
- Scripts live in `app_core/package.json`: `lint` (`eslint app/frontend`),
  `lint:fix`, `format` (`prettier --write app/frontend`), `format:check`
  (`prettier --check app/frontend`).
- Both `lint` and `format:check` are blocking in CI and in `pre-commit`.
- No Stylelint and no `tsc` — CSS and types stay out of scope.

## Related

- `agent/styleguides/core/react-dashboard.md` — the "how" companion
  (Linting & Formatting section)
- `agent/adr/ci-via-docker-compose.md` — where `lint`/`format:check` run
  as blocking CI checks
- `agent/adr/git-hooks-with-lefthook.md` — where they run in
  `pre-commit`
- `agent/plans/add-ci-and-git-hooks.md` — the plan that surfaced this
  decision
