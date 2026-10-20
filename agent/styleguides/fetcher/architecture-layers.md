---
description: app_fetcher's concrete ingestion-pipeline layer map — parsers/builders/workers/schedulers/controllers and which scenario each belongs to.
---

# Architecture Layers (`app_fetcher`)

See `agent/styleguides/rails-layering.md` first for the cross-app
invariant this follows. This file is the concrete layer map specific to
`app_fetcher`'s ingestion pipeline.

## Purpose

Give each ingestion concern (parsing, building, persisting, scheduling,
exposing over the internal API) its own layer, so a new Steam data type
being ingested has an unambiguous place for each piece instead of a
fresh design decision. See
`agent/adr/fetcher/layered-ingestion-pipeline.md` for why this split
was chosen over merging any of these layers.

## When to Use

Applies to any code that ingests, transforms, persists, or schedules the
refresh of Steam data. Not relevant to code that only reads already-
persisted data for a response (`ItemPricesController#history`,
`InventoryValuesController`, which are plain AR queries with no
parsing/building involved).

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
Steam::Client (lib/steam/)  /  <Noun>Parser (app/parsers/)  /  Models (read)
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
<Noun>Parser (app/parsers/)  /  <Noun>Builder (app/builders/)
    ↓
Models (app/models/, write)
```

- **Parsers** (`app/parsers/`, flat/top-level — `<Noun>Parser`, with no
  `Steam::` prefix): pure, stateless, `.parse` class method, string/hash
  in → typed DTO out. No AR references, no I/O. Called from Scenario 3
  (inside a worker) and, under the carve-out below, directly from
  Scenario 1 (inside a controller).
- **Builders** (`app/builders/`, flat/top-level — `<Noun>Builder`, with
  no `Steam::` prefix): `.build` class method, DTO/API response in →
  unsaved AR instance out. May reference a model class to instantiate
  it, never to query or save it. Called only from Scenario 3.
- **Workers** (`app/workers/`): Scenario 3's entry point — the only
  layer that both invokes a parser/builder and persists the result. A
  Sidekiq job in the literal sense (`include Sidekiq::Worker`, a
  `perform` method) — not a generic term for background code. See
  `agent/styleguides/fetcher/background-jobs.md` for worker-specific
  conventions (queues, retries, transactions).
- **Schedulers** (`app/schedulers/`): Scenario 2's entry point — query
  local model state only, synchronously, then fan out to Scenario 3's
  workers via `.perform_async`. Never call `Steam::Client` — a
  scheduler's own run does no I/O; only the jobs it enqueues do, and
  only later.
- **Controllers** (`app/controllers/api/v1/`, plus the sibling
  `api/public/`, `api/admin/`, and `api/demo/` namespaces): Scenario 1's
  entry point. V1 conventions live in
  `agent/styleguides/fetcher/internal-api-controllers.md`, Public in
  `public-api-controllers.md`, Admin in `admin-api-controllers.md`, and
  Demo in `demo-api.md`.
- **Services** (`app/services/`, flat, top-level, named
  `<Noun>Service` — e.g. `UserInventorySyncService` — not namespaced
  under `Steam::` even when calling `Steam::Client`, like every other
  `app_fetcher` application-layer class):
  for a cohesive business operation that warrants its own class because
  keeping it in its caller would leave that caller with more than one
  responsibility. The number of callers is not the criterion: a sequence
  needed from more than one Scenario qualifies, and so does a
  single-Scenario sequence extracted to keep a worker's `perform` as
  thin orchestration glue (e.g. `PriceUpdateService`). Not a catch-all
  for any multi-step logic: reach for a service when the extracted
  sequence has clear, independently-testable boundaries and no existing
  layer owns it (parser, builder, query object, caching, model). See
  `agent/adr/fetcher/cross-scenario-service-layer.md` for the
  layer's origin and how it differs from `app_core`'s `app/actions/`.
  Unlike parsers/builders, a class here may call `Steam::Client`
  directly and persist models; unlike every other Scenario-1 rule, it
  may be called synchronously, inline, from a controller action before
  rendering — but only for the specific call sites that ADR names, not
  as a general permission. Every service inherits `ApplicationService`
  (`app/services/application_service.rb`), which supplies the private
  `success`/`failure`/`skipped` result helpers and holds no business
  logic. Its full rules — including the uniform `ApplicationService::Result[Payload]`
  return contract every `.call` uses — live in
  `agent/styleguides/fetcher/services.md`.
- **Query objects** (`app/queries/`, flat, one `<Resource>ListQuery`
  per resource, plus `app/queries/appliers/` → `Appliers::` and
  `app/queries/options/` → `Options::` for resource-agnostic
  filter/sort/pagination mechanics) and **Serializers**
  (`app/serializers/`, flat, pure response-shaping functions): Scenario
  1 for `Api::Public::` (and, in principle, `Api::V1::`) list endpoints
  whose filter/sort/pagination/serialization mechanics are shared across
  more than one controller — a different reuse axis from Services above
  (cross-controller within one Scenario, not cross-Scenario). A shared
  read-only concern query (e.g. `InventoryValueQuery`) also lives here
  when its result is consumed by more than one query object, an
  `Api::V1::` read action, or a cross-Scenario service; it returns
  structs, not response hashes, and is not an endpoint query. See
  `agent/styleguides/fetcher/list-query-objects.md` and
  `agent/adr/fetcher/list-query-objects-layer.md` for the full
  structure, interface, and rules — not restated here.
- **Demo read model** (`app/queries/demo/`, `Demo::Dataset` and
  `Demo::ItemPool`): a read-only demo-specific collaborator used by
  `Api::Demo::` controllers. It samples real `Item` rows from the YAML
  pool, reuses real price/trend caches, and assembles the existing
  list/detail serializers’ structs. It is deliberately not an
  `ApplicationService` (no writes/`Result` contract) and not a
  `app/queries/` endpoint query (no persisted demo resource). The only
  demo writer is the `demo:seed_items` rake task, which creates ordinary
  `Item` rows through `ItemParser` and enqueues `PriceUpdateWorker`. See
  `agent/styleguides/fetcher/demo-api.md`.

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
  (synchronous). An `Api::V1::` read action may also call a read-only
  query object for its payload; the only remaining synchronous service
  exception is `InventoriesController#show`'s cold-start sync.
- Services may depend on `Steam::Client`, the Caching layer
  (`ItemPriceCache`/`PriceHistoryCache`), parsers, models, and read-only
  query objects in `app/queries/` for their read step — the same
  dependency set a worker already has, plus the query layer. Calling a
  query does not transfer write ownership. May also be called
  synchronously from a controller (Scenario 1) for the specific named
  persistence call sites in `cross-scenario-service-layer.md`, or for a
  cohesive side-effect operation the controller would otherwise own —
  e.g. `PriceWarmupService`'s warmup cap/dedup/enqueue. A side-effect
  service writes no records; only the named persistence sites carry the
  controller-persistence permission.
- Query objects (`<Resource>ListQuery`, `<Resource>DetailQuery`, and
  shared concern queries such as `InventoryValueQuery`) may depend on
  `Appliers::*`, `Options::*`, model scopes, other read-only concern
  queries in the same layer, and bulk/single-key read-through caching
  classes (e.g. `ItemTrendCache`) — never on a response-payload TTL
  cache (e.g. `ItemListCache`), a serializer, a service, a
  controller, or anything HTTP-related, which stay the caller's job.
  `Appliers::*` depend on nothing resource-specific. Serializers depend
  only on the data already fetched by a query object. See
  `list-query-objects.md` for the full dependency rules.
- Demo controllers (`Api::Demo::`) depend on the demo base controller’s
  token check and `Demo::Dataset`; they never write and never touch
  `steam_id`/`UserInventory`. `Demo::Dataset` may depend on `Item`
  reads, the existing price/trend caches, `Demo::ItemPool`, the existing
  query structs, `Options::*`, and `Appliers::*` — never on
  controllers or services. `Demo::ItemPool` only reads
  `config/demo_items.yml`. The `demo:seed_items` task may depend on
  `Demo::ItemPool`, `ItemParser`, `Item`, and `PriceUpdateWorker`.

## Rules

### MUST

- New ingestion data types get their own parser/builder pair under the
  flat `app/parsers/`/`app/builders/` roots (top-level `<Noun>Parser`/
  `<Noun>Builder`, not namespaced under `Steam::`), following the split
  above — don't merge parse+build+persist into one class (see ADR,
  "Alternative: single importer class").
- Only a worker persists parsed/built data, inside a transaction when
  more than one write must stay consistent (see `background-jobs.md`) —
  except the narrow, named exception in
  `agent/adr/fetcher/cross-scenario-service-layer.md`, and the
  `demo:seed_items` task’s ordinary `Item` upsert.
- Keep `Api::Demo::`/`Demo::Dataset` read-only: no `UserInventory`,
  `UserInventoryItem`, or `InventoryValueLog` writes, and no fake
  `steam_id`. See `demo-api.md`.

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
    → Steam::Client → PriceUpdateService.call
        → PriceLogBuilder → transaction (save)

Api::V1::InventoriesController#show
    → UserInventorySyncService.call(steam_id)  (the one collaborator —
        see `agent/adr/fetcher/cross-scenario-service-layer.md`)
        → Steam::Client (inventory fetch)
        → ItemParser (for any missing names) → Item.upsert_all
        → UserInventory.sync!

Api::V1::ItemPricesController#dynamics
    → PriceWarmupService.call(items)  (nil-price filter, cap 20,
        Rails.cache dedup, enqueue — no persistence)
        ⇢ PriceUpdateWorker.perform_async(item.id)

Api::Demo::InventoriesController#show/#summary/#detail
    → Demo::Dataset.new(seed: demo_seed)
        → Demo::ItemPool.market_hash_names
        → Item reads (real catalog/prices)
        → ItemTrendCache / PriceHistoryCache (real market data)
        → InventoryListQuery::InventorySummary /
          InventoryDetailQuery::InventoryDetails structs
    → existing InventoryListSerializer / InventoryDetailSerializer
    (read-only; no UserInventory/InventoryValueLog writes)

demo:seed_items
    → Demo::ItemPool.entries → ItemParser.parse → Item upsert
        ⇢ PriceUpdateWorker.perform_async(item.id)
```

`InventoriesController#show`'s cold-start branch persists
synchronously, inline, before rendering — this is a narrow, named
exception to "only a worker persists" (above), not a layer violation.
See `agent/adr/fetcher/cross-scenario-service-layer.md` for why, and
for the original sync-parse/async-persist carve-out this superseded for
this specific path (`agent/adr/fetcher/layered-ingestion-pipeline.md`'s
Decision section still documents that original carve-out as a pattern
available for a future, similar case — it just no longer describes what
`show` itself currently does).

## Canonical Implementations

- `app_fetcher/app/parsers/item_parser.rb`
- `app_fetcher/app/builders/price_log_builder.rb`
- `app_fetcher/app/workers/price_update_worker.rb`,
  `app_fetcher/app/workers/user_inventory_sync_worker.rb`
- `app_fetcher/app/schedulers/price_scheduler.rb`
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb`
- `app_fetcher/app/services/application_service.rb` —
  `ApplicationService`, the services layer's only shared base class.
  It holds the layer's shared machinery in one file: nested
  `ApplicationService::Result` (the covariant value object) plus the
  private generic `success` and the payload-less `failure`/`skipped`
  result constructors every service inherits. Construction-only — no
  business logic lives here.
- `app_fetcher/app/services/user_inventory_sync_service.rb` —
  `UserInventorySyncService`, called from
  `InventoriesController#show`'s cold-start branch (Scenario 1) and
  `UserInventorySyncWorker` (Scenario 3).
- `app_fetcher/app/services/inventory_value_recording_service.rb` —
  `InventoryValueRecordingService`, called from
  `InventoryValueUpdateWorker` (Scenario 3) only; the read endpoint no
  longer seeds, so the nightly worker is the sole writer. A
  precondition-gated write —
  it returns `ApplicationService::Result::Skipped` (writing nothing) when
  the inventory is not yet fully priced, else `Success(data: <the log>)`. See
  `agent/styleguides/fetcher/services.md` and
  `agent/adr/fetcher/service-result-contract.md`.
- `app_fetcher/app/services/price_update_service.rb` —
  `PriceUpdateService`, called from `PriceUpdateWorker` (Scenario 3);
  a single-Scenario service extracted for SRP — keeps `perform` as thin
  orchestration glue by moving the 24h-change calculation and DB
  transaction out of the worker. `.call` returns
  `ApplicationService::Result[Item]` (`Success(data: <the updated Item>)`); it
  has no `Failure` branch (its writes are bang methods that raise), and the
  caller reads the result off `result.data` rather than the mutated
  argument (see `agent/styleguides/fetcher/services.md`).
- `app_fetcher/app/services/price_warmup_service.rb` —
  `PriceWarmupService`, called from
  `Api::V1::ItemPricesController#dynamics` (Scenario 1). A
  single-Scenario side-effect service: filters nil-price items, caps at
  20, deduplicates the enqueue with a 90-second `Rails.cache` write,
  and enqueues `PriceUpdateWorker`; returns
  `ApplicationService::Result[T::Array[Integer]]`
  (`Success(data: <enqueued ids>)`) and persists nothing.
- Demo: `app_fetcher/app/controllers/api/demo/base_controller.rb`,
  `app_fetcher/app/controllers/api/demo/inventories_controller.rb`,
  `app_fetcher/app/queries/demo/dataset.rb`,
  `app_fetcher/app/queries/demo/item_pool.rb`,
  `app_fetcher/config/demo_items.yml`, `app_fetcher/lib/tasks/demo.rake` —
  see `agent/styleguides/fetcher/demo-api.md`.
- Query objects / Appliers / Options / Serializers: none implemented
  yet — `app_fetcher/app/queries/item_catalog_query.rb` and siblings
  (`agent/plans/item-catalog-query-refactor.md`) will be this layer's
  first members. See `agent/styleguides/fetcher/list-query-objects.md`
  for the intended shape in the meantime.

## Related ADR

- `agent/adr/fetcher/layered-ingestion-pipeline.md`
- `agent/adr/fetcher/cross-scenario-service-layer.md` — the
  `app/services/` layer added above, and the narrow controller-
  persistence carve-out it comes with.
- `agent/adr/fetcher/list-query-objects-layer.md` — the Query
  objects/Appliers/Options/Serializers layers added above, and why they
  are not an extension of `app/services/`.
