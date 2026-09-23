# Layered Ingestion Pipeline: Parsers, Builders, Workers, Schedulers

## Status

Accepted

## Context

`app_fetcher` ingests Steam data (item metadata, prices) through several
independent concerns: turning a raw string or API payload into structured
data, turning structured data into persistable record attributes,
actually executing the external call and the write, and deciding on a
schedule what needs refreshing right now. Two ingestion paths exist today
(item list backfill, price updates) and more are expected as more Steam
data gets ingested.

Without an explicit decision, each new ingestion path could freely choose
its own split — a worker that parses inline, a scheduler that also
performs the external call, a controller that builds and saves directly.
That would make it impossible to test parsing logic without a DB, or
tune retry/queue behavior for "cheap local query" separately from
"expensive rate-limited HTTP call," which `background-jobs.md` already
relies on (`PriceScheduler` vs `PriceUpdateWorker`'s distinct retry
counts and queues).

A related question this ADR must also settle: `Api::V1::InventoriesController#show`
calls `Steam::ItemParser` directly and builds unsaved `Item.new` instances
for the JSON response, while the actual persistence happens later via
`ItemsListUpdateWorker`. On its face this looks like the controller
bypassing the worker layer. It doesn't — see Decision.

## Decision

There is no single call stack here — three independent scenarios feed
into the same parser/builder/model layers, each triggered differently
and running in a different process. Naming them separately (instead of
one "Controllers / Schedulers → Workers → ..." diagram) is itself part
of the decision: a controller and a scheduler are not peers, and lumping
them together hides that a scheduler is already an async job, not an
HTTP-triggered entry point.

### Scenario 1 — API request (synchronous, inside the Puma/Rails process)

```text
HTTP request
    ↓
Api::V1::<X>Controller
    ↓  plain synchronous Ruby calls, all inside this one request
Steam::Client   /   Steam::<Noun>Parser   /   Models (read)
    ↓
render json
```

A controller may call `Steam::Client` and, under the carve-out below, a
parser directly — always synchronous, always inside the one request. It
may *also* hand off expensive persistence to a worker (Scenario 3)
before rendering — see the carve-out — but that hand-off is a queue
write the request doesn't wait on, not a call.

### Scenario 2 — scheduled fan-out (cron-triggered, its own job, no I/O)

```text
sidekiq-cron (config/schedule.yml)
    ┊  triggers on a fixed clock — not an HTTP request
    ▼
<Noun>Scheduler#perform     (app/schedulers/ — itself a Sidekiq job)
    ↓  synchronous, local-only: no external I/O
query Models ("what needs refreshing right now?")
    ┊  .perform_async, once per item that needs it
    ▼
Worker#perform  (Scenario 3, below)
```

A scheduler is a Sidekiq job like a worker is, but it's the trigger for
Scenario 3, not a synchronous caller of one — see Scenario 3 for what
happens after the `┊` below it. Its own body never calls `Steam::Client`
or does any other external I/O; it only queries local state and enqueues.

### Scenario 3 — background job execution (async, its own process, wherever enqueued from)

```text
enqueue  ⇢  (from Scenario 1's controller, or Scenario 2's scheduler —
             both just call `.perform_async`, a Sidekiq/Redis queue
             write; the enqueuing caller returns immediately)
    ┊
    ▼
Worker#perform   (app/workers/ — runs later, in a separate Sidekiq
                  worker process; this is where a job's execution starts)
    ↓  synchronous Ruby calls, all inside this one job's execution
Steam::Client → Steam::<Noun>Parser / Steam::<Noun>Builder → Models (write,
    transaction if >1 write must stay consistent)
```

A worker is always where the actual external call and persistence
happen, regardless of whether Scenario 1 or Scenario 2 triggered its
enqueue. ("Worker" here is the literal Sidekiq-job sense — a class with
`include Sidekiq::Worker` and a `perform` — not a generic term for
"background code.")

Within Scenario 3, parsing and building stay their own classes:

- **Parsers** (`app/parsers/steam/`) are pure functions: string/hash in,
  a typed DTO out. No AR, no I/O, no knowledge of what calls them.
- **Builders** (`app/builders/steam/`) turn a parsed/API-response DTO into
  an unsaved AR instance with correctly-shaped attributes (units
  normalized, e.g. prices to cents). They instantiate a model but never
  query or save it — persistence is the worker's job.
- **`Steam::Client`** (`lib/steam/`) is the one layer allowed to make
  outbound HTTP calls to Steam — called synchronously from Scenario 3's
  worker, or from Scenario 1's controller directly. This is
  `app_fetcher`'s equivalent of a "service" layer for talking to an
  external system — there is no `app/actions/` here; that's an
  `app_core`-specific name (see
  `.claude/adr/core/thin-controllers-actions-direct-fetcher-reads.md`)
  for its own request-orchestration layer, not something this app has or
  needs. `Steam::Client` itself is documented separately in
  `.claude/adr/fetcher/steam-client-response-objects-and-rate-limiting.md`
  — this ADR only fixes *who's allowed to call it* (Scenario 1's
  controllers, Scenario 3's workers; never parsers, builders, or
  Scenario 2's schedulers).

**Explicit carve-out (Scenario 1 borrowing from Scenario 3's parser):** a
controller may call a parser directly and return an in-memory, unsaved
model built from it, provided the actual persistence for those same
records is deferred to a Scenario-3 worker. This is not the controller
doing the worker's job — parsing is cheap, pure, local computation with
no reason to be pushed off the request path; persistence is the
expensive part, and that stays batched and async
(`InventoriesController#show` → `ItemsListUpdateWorker`, batched via
`each_slice(500)`). The rule this preserves is about the *expensive*
work only running through a worker, not about parsers being off-limits
to controllers.

## Alternatives Considered

### Alternative: single "importer" class per data type (parse + build + persist)

Rejected because parsing (pure, no DB needed to test) and building (needs
to know the target AR attribute shape) have different testing needs;
merging them forces every parser-logic test through AR/DB setup, and
removes the ability to reuse a parser from a context that never
persists (the controller carve-out above).

### Alternative: workers parse inline, no separate `parsers`/`builders`

Rejected because the same parsing logic already needs to run from two
places (a worker's batch path and a controller's inline path). Inlining
it into the worker would either duplicate the regex/extraction logic or
force the controller to enqueue a worker just to parse a string it needs
synchronously for its own response.

### Alternative: merge `Scheduler` into `Worker` (scheduler enqueues the actual Steam call itself)

Rejected because it couples "what needs refreshing, on a fixed clock"
with "how a single item actually gets refreshed, against a rate-limited
external API." Keeping them separate is what lets `PriceScheduler` have
no `Steam::Client` dependency at all and lets `PriceUpdateWorker` carry
its own retry/queue tuning independent of the cron trigger.

## Consequences

### Positive

- Parser logic is unit-testable with no DB and no Steam API.
- Builder logic is unit-testable with no Steam API, only AR.
- Workers stay small — orchestration glue, not parsing/building logic.
- A new ingestion type has an obvious place for each concern instead of
  a fresh design decision per feature.

### Negative

- A single ingestion path spans more files (parser + builder + worker,
  sometimes + scheduler) than a single "do everything" class would.
- The sync-parse/async-persist carve-out means a client can receive a
  response containing an item that isn't durably saved yet — already an
  accepted product tradeoff, not a bug, but a real one.

### Risks

- A future contributor could read `InventoriesController#show` calling
  `Steam::ItemParser` directly as drift/inconsistency and "fix" it by
  making the controller enqueue-and-wait or persist synchronously,
  which would put expensive writes back on the request path. This ADR
  is what should stop that "fix."

## Implementation Constraints

- A new ingestion data type gets its own parser (pure) and builder
  (AR-shaping) pair under `Steam::`, not a merged class.
- Parsers must not reference AR models or perform I/O.
- Builders may instantiate a model but must not query or save it.
- Only workers persist and only workers perform the paired
  transaction when more than one write must stay consistent (see
  `background-jobs.md`'s Data/Transactions section).
- Schedulers must not call `Steam::Client` or any other external-I/O
  collaborator directly.
- A controller may call a parser (not a builder) directly and construct
  an unsaved model for its response only when persistence for the same
  data is deferred to an async worker — this is the only sanctioned
  layer skip.

## Related

- `.claude/styleguides/fetcher/architecture-layers.md`
- `.claude/styleguides/fetcher/background-jobs.md`
- `.claude/styleguides/fetcher/internal-api-controllers.md`
- `.claude/styleguides/rails-layering.md`
- `.claude/adr/fetcher/steam-client-response-objects-and-rate-limiting.md`
  — why `Steam::Client` itself is shaped the way it is; this ADR only
  covers who's allowed to call it
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb`
- `app_fetcher/app/workers/items_list_update_worker.rb`
- `app_fetcher/app/parsers/steam/item_parser.rb`
- `app_fetcher/app/builders/steam/price_log_builder.rb`
- `app_fetcher/lib/steam/client.rb`
