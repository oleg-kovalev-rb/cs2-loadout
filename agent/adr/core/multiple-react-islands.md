# Multiple Independent React Islands, With Direct Cross-Island Reuse Only for Pure/Stateless Code

## Status

Accepted

## Context

`app_core`'s React island (`app/frontend/dashboard/`) has so far been the
one top-level frontend feature: a signed-in user's Portfolio view, with one
root component (`Dashboard.jsx`), one `useReducer`, and one data-loading
hook (`useDashboardData`) built around a specific shape — fetch the user's
(small) inventory once, then filter/sort/paginate it entirely client-side
in memory (`utils/filters.js`, a fixed `PAGE_SIZE`, a 0-based in-memory
page index).

The "Tracked Items" feature needs a second top-level page: a public,
unauthenticated catalog of all tracked items
(`agent/plans/tracked-items-frontend.md`), served by `app_fetcher`'s
`Api::Public::ItemsController#index` — a large, server-paginated resource
where every filter, sort, search, or page change must become a new network
request with new query params, not an in-memory re-slice. This is not a
variation on the existing reducer's shape; it is a structurally different
data-loading contract (server-driven pagination/filtering vs. fetch-once-
and-derive-client-side).

Two decisions had to be made before implementation could proceed:

1. Does a second top-level feature with an incompatible data-loading shape
   become a second mode inside the existing `Dashboard.jsx`/`reducer.js`,
   or a wholly separate island?
2. Once a second island exists, which of the first island's
   components/utilities (e.g. `Sparkline.jsx`, `format.js`'s
   `fmtPrice`/`conditionAbbr`) does the second island get to use directly,
   and which does it need its own version of?

`agent/styleguides/core/react-dashboard.md` had no answer to either
question — it was written when there was only ever going to be one island,
and its own heading scoped it literally to `app/frontend/dashboard/`.

## Decision

Introduce `app_core/app/frontend/tracked_items/` as a new, independent
React island — its own root component, `reducer.js`, data-loading hook,
`components/`, `utils/`, `__tests__/`, Vite entrypoint, and stylesheet —
rather than adding a second mode to `dashboard/`'s existing reducer. Each
island owns its own `useReducer` and its own data-loading hook(s); state is
never shared between islands directly (no cross-island Context, no one
island reading another's reducer state).

Cross-island code reuse is decided by one test: is the piece pure/stateless
and already generic, or is it coupled to its owning island's own
reducer/state contract?

- **Pure/stateless, generic code is imported directly** from its owning
  island into any other island that needs it — not duplicated. This
  applies today to `dashboard/components/Sparkline.jsx` (already the
  canonical small-repeated-trend-line component per
  `agent/adr/core/sparkline-vs-recharts.md`) and `dashboard/utils/
  format.js`'s `fmtPrice`/`conditionAbbr`.
- **Code coupled to one island's reducer/state shape gets a fresh,
  island-local implementation**, even when it looks structurally or
  visually similar to an existing component elsewhere — `ItemsToolbar`,
  `FilterDropdown`, `SortDropdown`, and `Pagination` are this case for
  `tracked_items/`, since each is wired to `dashboard/reducer.js`'s
  specific action types and client-side-pagination assumptions.

Shared chrome outside any one island (the topbar, nav tabs between pages,
sign-in/out markup) stays server-rendered ERB, and its CSS
(`dashboard.css`'s custom-property tokens plus that shared chrome) is
loaded by every island's page; each island's own page-specific CSS lives in
that island's own stylesheet.

`agent/styleguides/core/react-dashboard.md` is amended (not superseded)
to state this as the general shape — its existing `dashboard/`-specific
content remains the canonical worked example throughout.

## Alternatives Considered

### Alternative: one island, a second "page" mode in the existing reducer

Keep a single `Dashboard.jsx`/`reducer.js`/entrypoint; add a `page: 'portfolio' | 'tracked-items'` field and grow the reducer/hook set to cover both.

Rejected because the two features' data-loading contracts are
fundamentally incompatible, not just visually different: one fetches a
small resource once and derives everything client-side; the other must
re-fetch from the server on every filter/sort/page change against a large,
paginated resource. Cramming both into one reducer would mean either two
disjoint sets of action types coexisting in one file (connected only by
which tile currently renders — no actual shared logic) or distorting the
existing client-side-pagination contract to also serve server-driven
pagination through configuration, which would have made the *existing,
working* Portfolio page riskier to change for a feature that doesn't need
to touch it at all.

### Alternative: generalize the existing toolbar/filter/pagination components to serve both shapes

Make `FilterDropdown`/`SortDropdown`/`Pagination` configurable enough
(render props, strategy objects) to serve both an in-memory and a
server-driven list.

Rejected: the actual complexity these components would need to absorb
(variable page-size vs. fixed, 1-based vs. 0-based paging, debounced
server search vs. synchronous client filtering, different action-type
vocabularies) is exactly the kind of premature, speculative abstraction
the project avoids elsewhere (see the deferred base-service/`Result` class
for `app_fetcher`'s services, and `Api::Public::`'s deliberately duplicated
~10-line base controller in
`agent/adr/fetcher/public-api-namespace.md`) — guessing at a shared shape
from exactly two examples, one of which doesn't even exist yet.

### Alternative: duplicate everything per island, including pure utilities

Give `tracked_items/` its own copy of `Sparkline.jsx` and `format.js`'s
formatters instead of importing across directories, on the reasoning that
each island should be fully self-contained.

Rejected: these specific pieces have no island-specific state or
assumptions baked in — they're plain functions/components over plain
data. Duplicating them buys no isolation benefit (there's no shared state
to accidentally couple to) and creates a real one: two copies to keep in
sync, with no automatic way to notice drift. This is the opposite
situation from the controller-duplication case above, which is why the
two decisions land differently.

## Consequences

### Positive

- The Portfolio island's existing behavior, reducer, and tests are
  untouched by this change — a second feature with its own data-loading
  shape doesn't force a risky generalization of working code.
- A contributor can read one island's directory in isolation and
  understand its full state machine, without cross-referencing a sibling
  island's unrelated action types.
- Genuinely shared, stateless code (visualizations, formatters) still has
  exactly one implementation, avoiding silent drift between two copies.

### Negative

- Some structurally similar-looking components (a filter dropdown, a
  pagination control) now exist twice, once per island, instead of once —
  an accepted, bounded amount of duplication rather than a shared
  abstraction guessed at too early.
- A future contributor has to apply the "pure/stateless vs. reducer-
  coupled" test themselves for each new piece of cross-island-reusable
  code, rather than following one blanket rule ("always share" or "never
  share").

### Risks

- As more islands appear, the set of components judged "pure enough to
  share" could grow haphazardly without a clear owner directory — if
  reuse becomes common, a future `components/shared/`-style directory
  (not invented here, since there isn't yet a third example motivating its
  exact shape) may become the better answer. Revisit once a third island
  or a third reuse case appears, following the same
  wait-for-a-real-third-example posture as
  `agent/adr/fetcher/public-api-namespace.md`.

## Implementation Constraints

- A new top-level feature with its own route and a data-loading shape
  that doesn't fit an existing island's reducer/hook contract is a new
  directory under `app_core/app/frontend/`, with its own root component,
  `reducer.js`, `hooks/`, `components/`, `utils/`, `__tests__/`, Vite
  entrypoint, and stylesheet — never a second mode inside an existing
  island's reducer.
- No island reads another island's reducer state, hook state, or a shared
  Context. The only form of cross-island coupling is a plain import of a
  pure, stateless component or function.
- Before duplicating a component/utility into a new island, check whether
  it's actually coupled to the source island's reducer/state shape. If
  not, import it directly instead.
- Shared chrome (topbar, nav tabs, sign-in/out) stays server-rendered ERB
  outside any island, with its CSS in the existing shared stylesheet; each
  island's own page-specific CSS goes in that island's own stylesheet.

## Related

- `agent/styleguides/core/react-dashboard.md` — the concrete
  structure/component/reuse/testing conventions this decision backs,
  amended to state this as the general shape rather than a
  `dashboard/`-only one.
- `agent/adr/core/sparkline-vs-recharts.md` — the existing precedent for
  `Sparkline.jsx` being a shared, reusable component, now cited as the
  canonical example of the "pure/stateless → reuse directly" rule.
- `agent/adr/fetcher/public-api-namespace.md` — the closest precedent in
  the `app_fetcher` side of the codebase for "accept small duplication
  rather than guess at a shared abstraction from too few examples," which
  this decision's reasoning mirrors for the opposite case (components) in
  `app_core`.
- `agent/plans/tracked-items-frontend.md` — the plan this decision
  unblocks.
