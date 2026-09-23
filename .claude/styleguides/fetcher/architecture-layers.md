---
description: app_fetcher's concrete ingestion-pipeline layer map — parsers/builders/workers/schedulers/controllers and which scenario each belongs to.
---

# Architecture Layers (`app_fetcher`)

See `.claude/styleguides/rails-layering.md` first for the cross-app
invariant this follows. This file is the concrete layer map specific to
`app_fetcher`'s ingestion pipeline.

## Purpose

Give each ingestion concern (parsing, building, persisting, scheduling,
exposing over the internal API) its own layer, so a new Steam data type
being ingested has an unambiguous place for each piece instead of a
fresh design decision. See
`.claude/adr/fetcher/layered-ingestion-pipeline.md` for why this split
was chosen over merging any of these layers.

## When to Use

Applies to any code that ingests, transforms, persists, or schedules the
refresh of Steam data. Not relevant to code that only reads already-
persisted data for a response (`PriceHistoriesController`, which is a
plain AR query with no parsing/building involved).

## Structure

Three independent scenarios feed the same parser/builder/model layers.
They're kept separate here because they're triggered differently and
run in different processes — a controller and a scheduler are not
peers, even though both eventually enqueue a worker. See the ADR's
Decision section for the full reasoning; this is the file-location
version of the same three scenarios.

**Scenario 1 — API request**, synchronous, inside the Rails/Puma
process:

```text
Api::V1::<X>Controller (app/controllers/api/v1/)
    ↓  synchronous, inside this one request
Steam::Client (lib/steam/)  /  Steam::<Noun>Parser (app/parsers/steam/)  /  Models (read)
```

**Scenario 2 — scheduled fan-out**, cron-triggered, its own job, no I/O:

```text
sidekiq-cron (config/schedule.yml)
    ┊  fixed clock, not an HTTP request
<Noun>Scheduler (app/schedulers/) — itself a Sidekiq job
    ↓  synchronous, local-only
query Models
    ┊  .perform_async, once per item — enqueue, not a call
Worker  (Scenario 3)
```

**Scenario 3 — background job execution**, async, its own process,
regardless of whether Scenario 1 or 2 triggered the enqueue:

```text
enqueue (from Scenario 1 or Scenario 2)
    ┊  Sidekiq/Redis queue write — caller returns immediately
<Noun><Verb>Worker (app/workers/) — job's execution starts here
    ↓  synchronous Ruby calls, all within this one job's execution
Steam::Client (lib/steam/)
    ↓
Steam::<Noun>Parser (app/parsers/steam/)  /  Steam::<Noun>Builder (app/builders/steam/)
    ↓
Models (app/models/, write)
```

- **Parsers** (`app/parsers/steam/`): pure, stateless, `.parse` class
  method, string/hash in → typed DTO out. No AR references, no I/O.
  Called from Scenario 3 (inside a worker) and, under the carve-out
  below, directly from Scenario 1 (inside a controller).
- **Builders** (`app/builders/steam/`): `.build` class method, DTO/API
  response in → unsaved AR instance out. May reference a model class to
  instantiate it, never to query or save it. Called only from
  Scenario 3.
- **Workers** (`app/workers/`): Scenario 3's entry point — the only
  layer that both invokes a parser/builder and persists the result. A
  Sidekiq job in the literal sense (`include Sidekiq::Worker`, a
  `perform` method) — not a generic term for background code. See
  `.claude/styleguides/fetcher/background-jobs.md` for worker-specific
  conventions (queues, retries, transactions).
- **Schedulers** (`app/schedulers/`): Scenario 2's entry point — query
  local model state only, synchronously, then fan out to Scenario 3's
  workers via `.perform_async`. Never call `Steam::Client` — a
  scheduler's own run does no I/O; only the jobs it enqueues do, and
  only later.
- **Controllers** (`app/controllers/api/v1/`): Scenario 1's entry
  point — see `.claude/styleguides/fetcher/internal-api-controllers.md`.

## Responsibilities

Parsing logic (regex/string extraction, unit normalization) belongs in a
parser, never duplicated inline in a worker or controller. Building
AR-shaped attributes belongs in a builder, never inline in a worker.
Deciding *when* something needs refreshing belongs in a scheduler, never
folded into a worker's `perform`.

## Dependencies

One-directional, per `rails-layering.md`. Concretely for this app:

- Parsers depend on nothing else in the app.
- Builders depend only on the model class(es) they instantiate.
- Workers (Scenario 3) may call parsers, builders, models, and
  `Steam::Client` — all synchronous, all within one job's execution.
- Schedulers (Scenario 2) depend only on models (synchronous query) and
  workers (async enqueue via `.perform_async`) — never `Steam::Client`.
- Controllers (Scenario 1) may depend on models and `Steam::Client`
  (both synchronous) and workers (async enqueue via `.perform_async`,
  never a call) — and, under the carve-out below, a parser directly
  (synchronous).

## Rules

### MUST

- New ingestion data types get their own parser/builder pair under
  `Steam::`, following the split above — don't merge parse+build+persist
  into one class (see ADR, "Alternative: single importer class").
- Only a worker persists parsed/built data, inside a transaction when
  more than one write must stay consistent (see `background-jobs.md`).

### SHOULD

- Reuse an existing parser from a controller (see carve-out) rather than
  re-deriving the same extraction logic inline, if the same shape is
  already parsed elsewhere.

### MUST NOT

- Don't call `Steam::Client` from a parser, builder, or scheduler —
  those layers do no external I/O.
- Don't have a builder query or save the model it instantiates —
  persistence is the calling worker's job.

## Interaction With Other Layers

`→` below is a plain synchronous call. `⇢` is a Sidekiq `.perform_async`
enqueue — the caller returns immediately; everything after it runs later,
in a separate worker execution.

```text
sidekiq-cron ⇢ PriceScheduler#perform ⇢ PriceUpdateWorker#perform
    → Steam::Client → Steam::PriceLogBuilder → transaction (save)

Api::V1::InventoriesController#show
    → Steam::Client (inventory fetch)
    → Steam::ItemParser (inline, for the response — carve-out, see ADR)
    ⇢ ItemsListUpdateWorker#perform (batched, actual persistence — runs
        later, in a separate worker execution, not before the response
        above is rendered)
        → Steam::ItemParser → Item.upsert_all
```

The `InventoriesController` path calling `Steam::ItemParser` directly
and returning unsaved `Item.new` instances is deliberate, not a layer
violation — see
`.claude/adr/fetcher/layered-ingestion-pipeline.md`'s Decision section.
Parsing there is cheap, pure, and safe to run inline; the actual
persistence for the same records still only happens via
`ItemsListUpdateWorker`.

## Canonical Implementations

- `app_fetcher/app/parsers/steam/item_parser.rb`
- `app_fetcher/app/builders/steam/price_log_builder.rb`
- `app_fetcher/app/workers/price_update_worker.rb`,
  `app_fetcher/app/workers/items_list_update_worker.rb`
- `app_fetcher/app/schedulers/price_scheduler.rb`
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb`

## Related ADR

`.claude/adr/fetcher/layered-ingestion-pipeline.md`
