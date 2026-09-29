# Composite Component Tests Drive a Real Reducer, Not Mocked Callbacks

## Status

Accepted

## Context

All of the dashboard's shared UI state (filters, sort, pagination,
selection, open dropdown) lives in one `useReducer(dashboardReducer,
initialState)` owned by `Dashboard.jsx`. Individual components like
`ItemsTile` don't own state themselves — they receive state slices and
dispatch-bound callback props (`onSortChange`, `onWeaponToggle`, ...) and
render from them.

Testing a composite component like `ItemsTile` — one that wires together
filtering (`filters.js`), sorting, and pagination — raises a choice: mock
the callback props and assert "the right callback was called with the
right argument when the user clicks X," or mount a small harness that
owns a real `dashboardReducer`/`initialState`, wire the component to it,
and assert on what actually renders after real user interaction. This is
the same question `.claude/adr/fetcher/rspec-testing-strategy.md` already
settled for the Ruby backend (real Redis for `PriceUpdateWorker`'s stream
write, not a mock) — asked here for the frontend's own state layer.

## Decision

`ItemsTile.test.jsx` mounts a harness component that owns a real
`useReducer(dashboardReducer, initialState)` — the same reducer
`Dashboard.jsx` uses in production, not a stub or a mocked dispatch —
renders `ItemsTile` wired to it, and drives it through
`@testing-library/user-event`, asserting on rendered output (which rows
appear, in what order, after which interactions). This is the pattern for
any new composite component whose correctness depends on how it responds
to real state transitions.

## Alternatives Considered

### Alternative: Mock the reducer/callback props, assert on call arguments

Render `ItemsTile` with plain mock functions for
`onSortChange`/`onWeaponToggle`/etc., and assert that clicking a sort
option calls `onSortChange('price_asc')`, without a real reducer in the
loop.

Rejected because:

- This proves the component *calls* the expected callback, not that the
  *reducer* actually produces the correct resulting state, or that the
  component correctly *re-renders* given that new state. The thing worth
  verifying — that `dashboardReducer` + `filters.js`'s
  `applyFilters`/`applySort` + `ItemsTile`'s rendering agree with each
  other end to end — is exactly what a mocked-callback test cannot
  observe, since it stops at "was this function called."

### Alternative: Snapshot testing

Render the component and assert against a stored snapshot of its output.

Rejected: a snapshot doesn't express *why* a given output is correct, so
it doesn't communicate intended behavior to a reader, and it's brittle
against incidental markup/class changes unrelated to the behavior under
test — an update-the-snapshot habit forms instead of understanding the
diff.

## Consequences

### Positive

- A passing `ItemsTile.test.jsx` is direct evidence that the reducer,
  the filter/sort derivation functions, and the rendered output agree
  with each other — not just that each piece works in isolation or that
  the component calls the props it's given.
- The same harness shape (real reducer + `user-event` interaction) is
  immediately reusable for the next composite component without a new
  design decision.

### Negative

- Slightly more test setup than mocking props directly — a harness
  component per composite under test, rather than a bare render call
  with stub functions.

### Risks

- As more composite components and reducer action types are added, a
  shared harness component could grow large or slow; not yet a problem
  at this app's current size, but worth revisiting if the reducer or the
  number of composite components grows substantially.

## Implementation Constraints

- A new composite component that consumes reducer-driven state and
  dispatches actions gets its own harness-based test — mount a real
  `useReducer(dashboardReducer, initialState)`, wire the component to it,
  drive it via `@testing-library/user-event` — following
  `ItemsTile.test.jsx`'s pattern, not a shallow render with
  mocked dispatch/callback props.
- A component with no reducer interaction (a pure presentational leaf)
  doesn't need this pattern — see
  `.claude/styleguides/core/react-dashboard.md`'s "what gets a dedicated
  test file" section for that boundary; not every component needs a
  harness-based test, only ones whose correctness depends on real state
  transitions.

## Related

- `.claude/styleguides/core/react-dashboard.md` — Testing section
- `.claude/adr/fetcher/rspec-testing-strategy.md` — the backend-side
  parallel decision (real Redis over a mock for the same reason: proving
  the integration, not just that a call happened)
- `app_core/app/frontend/dashboard/__tests__/ItemsTile.test.jsx`
- `app_core/app/frontend/dashboard/reducer.js`
