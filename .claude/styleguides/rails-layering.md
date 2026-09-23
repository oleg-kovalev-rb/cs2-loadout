---
description: Cross-app invariant — the one Controller → orchestration → Models shape and dependency direction both app_fetcher and app_core follow.
---

# Rails Layering (Cross-App)

## Purpose

Describe the one architectural rule both `app_fetcher` and `app_core`
follow identically, so it's written down once instead of repeated,
differently worded, in each app's own architecture styleguide. Each
app's concrete layer names and diagram live in its own
`architecture-layers.md` — this file only covers what's actually shared.

## When to Use

Read this first when touching either app's controller, worker/action, or
model layer. Read the app-specific styleguide
(`.claude/styleguides/fetcher/architecture-layers.md` or
`.claude/styleguides/core/architecture-layers.md`) for what the
orchestration layer is actually called in that app and how it's
structured.

## Structure

Both apps converge on the same three-tier shape, differing only in what
the middle tier is called and split into:

```text
Controller  (thin: routing, auth, param handling)
    ↓
<app-specific orchestration layer>   — workers/schedulers/parsers/builders in app_fetcher,
                                        actions in app_core
    ↓
Models  (persistence + validations only)
```

External I/O (HTTP calls to Steam, JWT signing) is never inline in a
controller or the orchestration layer body beyond a single call — it's
isolated in a dedicated client class (`Steam::Client` in `app_fetcher`,
`lib/steam/` in `app_core`).

The `↓` above only asserts dependency *direction*, not that every step
is a synchronous method call — in `app_fetcher`, Controller/Scheduler →
Worker is a Sidekiq `.perform_async` enqueue, not a call (see
`.claude/styleguides/fetcher/architecture-layers.md` for which edges are
synchronous and which are an async hand-off).

## Responsibilities

- **Controllers**: routing, authentication, param extraction, response
  rendering. Delegate anything beyond a trivial single-model lookup.
- **Orchestration layer** (app-specific name/split): coordinates
  external calls, parsing/building, and persistence. This is where
  business logic lives.
- **Models**: schema, associations, validations. No orchestration, no
  external I/O.
- **Client/lib layer**: the only code allowed to perform outbound HTTP
  or crypto operations against an external system.

## Dependencies

Dependency direction is one-way, top to bottom in the diagram above.
Lower layers never call back up:

- Models never reference controllers or the orchestration layer.
- The client/lib layer never references models or controllers.
- The orchestration layer may call the client/lib layer and models, not
  the reverse.

## Rules

### MUST

- Keep controllers thin: delegate to the orchestration layer for
  anything beyond a single trivial model lookup or a direct render.
- Isolate all outbound HTTP/crypto behind a dedicated client class, not
  inline in a controller, worker, action, or model.
- Respect one-directional dependency flow (see Dependencies). A lower
  layer must never import or call a higher one.

### MUST NOT

- Don't put business logic (multi-step orchestration, external calls,
  conditional persistence) directly in a model callback or a controller
  action body.
- Don't have the client/lib layer touch ActiveRecord.

## Interaction With Other Layers

See each app's own `architecture-layers.md` for the concrete
call-graph — this file states the invariant both graphs satisfy, not the
graphs themselves.

## Related

- `.claude/styleguides/fetcher/architecture-layers.md`
- `.claude/styleguides/core/architecture-layers.md`
- `.claude/adr/fetcher/layered-ingestion-pipeline.md`
- `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md`
