---
description: Sidekiq worker/scheduler conventions in app_fetcher — naming, queues/retries, transactions, idempotency, and their spec-level testing rules.
---

# Background Jobs & Schedulers (Sidekiq)

## Purpose

Move Steam ingestion work (fetching prices, backfilling item metadata)
off the request/response cycle and off a fixed clock, via Sidekiq
workers and a `sidekiq-cron`-driven scheduler.

## When to Use

Use a worker for any unit of work that calls the Steam API or does a
bulk write and doesn't need to block a request or another job. Use a
scheduler (see `PriceScheduler`) only for the "what needs updating right
now" query-and-fan-out step that `sidekiq-cron` triggers on a fixed
schedule — the scheduler itself does no external I/O, it only decides
what to enqueue.

## Structure

- Workers live in `app/workers/`, named `<Noun><Verb>Worker`
  (`PriceUpdateWorker`, `UserInventorySyncWorker`).
- The cron-triggered orchestrator lives in `app/schedulers/`, named
  `<Noun>Scheduler` (`PriceScheduler`), and is itself a
  `Sidekiq::Worker` — `sidekiq-cron` enqueues it like any other job, on
  the schedule declared in `config/schedule.yml`.
- Unlike Steam-domain classes elsewhere (`Steam::ItemParser`,
  `Steam::Client`), workers and schedulers are **not** namespaced under
  `Steam::` — they stay top-level (`PriceUpdateWorker`, not
  `Steam::PriceUpdateWorker`), even when everything they do is
  Steam-related.
- `include Sidekiq::Worker` (not the newer `Sidekiq::Job` alias) on
  every worker and scheduler, for consistency with the two that already
  exist.

## Interface

- `perform` is the only public method; its `sig` always `.void`s (a job
  has no return value Sidekiq will use).
- Arguments are Sidekiq-serializable primitives only — an `Integer` id
  (`PriceUpdateWorker`) or a `String` (`UserInventorySyncWorker`'s
  `steam_id`) — never an ActiveRecord object or a custom class instance.

## Responsibilities

`perform` is orchestration glue: look up records, delegate parsing to a
parser (`Steam::ItemParser`) or building to a builder
(`Steam::PriceLogBuilder`), persist, and (for `PriceUpdateWorker`)
publish. It does not itself parse Steam's response shape or implement
domain logic beyond simple guards and diffing — that stays in the
parser/builder/client layer.

## Dependencies

May call `Steam::Client` directly (a fresh instance per `perform`, same
as controllers) and the parser/builder classes. `PriceUpdateWorker` also
depends on `STREAM_REDIS_POOL` (a global `ConnectionPool`, set up in
`config/initializers/redis.rb`) to publish to the `prices_stream` Redis
stream.

## Rules

### MUST

- Declare `sidekiq_options queue: ..., retry: N` explicitly on every
  worker — don't rely on Sidekiq's default retry count (25, over ~3
  weeks) by omission. Pick `N` to reflect how failure-prone the work is:
  a worker that calls the rate-limited, occasionally-flaky Steam API
  gets more retries (`PriceUpdateWorker`: 5) than one that only writes
  to Postgres (`InventoryValueUpdateWorker`: 3).
- Route work that calls `Steam::Client` onto its own queue (`:prices`),
  separate from cheap orchestration work (`:default`) — see
  `config/sidekiq.yml`'s queue list and `PriceUpdateWorker`/
  `UserInventorySyncWorker` vs. `InventoryValueUpdateWorker`/
  `PriceScheduler`. This keeps a Steam-API outage or rate-limit backoff
  from starving unrelated jobs.
- Use a bulk write (`Item.upsert_all(..., unique_by: ...)`) instead of a
  per-record loop of `.new`/`.save!` when a job processes a batch of
  independent records. No current worker does this directly (see
  `app/services/user_inventory_sync_service.rb` for the same `upsert_all`
  pattern, now living in the cross-Scenario service layer instead of a
  worker — see `.claude/adr/fetcher/cross-scenario-service-layer.md`);
  this rule still applies the moment a worker needs it again.
- Wrap multiple writes that must stay consistent with each other in a
  single `ActiveRecord::Base.transaction` (see `PriceUpdateWorker`
  wrapping `price_log.save!` and `item.update!` in `Item.transaction` —
  an item's `current_price_cents` must never be updated without the
  corresponding `price_log` row, or vice versa).
- Guard on a missing/invalid record and return early (`return unless
  item`) rather than letting a `NoMethodError` on `nil` become the
  failure — Sidekiq would retry a `nil` dereference as if it were a
  transient error, which it isn't.

### SHOULD

- Keep a job idempotent enough that Sidekiq retrying it (or `sidekiq-cron`
  re-triggering the scheduler) doesn't corrupt state — `upsert_all` is
  safe to repeat by construction; a repeated `PriceUpdateWorker` run just
  records another price sample, which is the intended behavior, not a
  side effect to guard against.
- On an external-call failure inside a job, log and return rather than
  raising, when the job's job-level `retry:` isn't the right tool for
  that specific failure (see `PriceUpdateWorker`'s `else` branch logging
  and returning normally instead of re-raising `response.error`).
  Prefix the log message with `[ClassName]` (see
  `Rails.logger.warn("[PriceUpdateWorker] Failed for ...")`).

### MUST NOT

- Don't put Steam response parsing or HTTP-status branching inside a
  worker — that belongs to `Steam::Client`/its DTOs (see
  `.claude/styleguides/fetcher/steam-response-objects.md`).
- Don't have the scheduler do the actual Steam call itself — it only
  queries local state and fans out via `.perform_async` (see
  `PriceScheduler`). If a scheduler starts doing real I/O beyond a
  query, that work belongs in a worker it enqueues, not in the scheduler.

## Data / Transactions

A job that writes more than one record where partial completion would
leave inconsistent state (e.g. a price log without the item's price
being updated to match) must wrap those writes in a transaction. A job
that writes one thing, or many independent things via a single bulk
statement, doesn't need one.

## Error Handling

- Missing/invalid input record → guard clause, return early, no log (see
  `PriceUpdateWorker`'s `return unless item`).
- External call failed (`Steam::Client` response not `success?`) → log a
  `[ClassName] ...` warning with `response.error` and return normally;
  Sidekiq's `retry:` count is what handles giving the call another shot
  later, not an in-line rescue/retry loop.

## Interaction With Other Layers

```text
sidekiq-cron (config/schedule.yml)
    ↓ enqueues on schedule
PriceScheduler#perform
    ↓ queries local Item state, no external I/O
    ↓ PriceUpdateWorker.perform_async(item.id)  — one job per item
PriceUpdateWorker#perform
    ↓ Steam::Client → Steam::PriceLogBuilder → transaction (save + update)
    ↓ publish to STREAM_REDIS_POOL ("prices_stream")

sidekiq-cron
    ↓ enqueues on schedule (daily; its own staleness filter bounds actual Steam calls to ~weekly per steam_id)
UserInventorySyncScheduler#perform
    ↓ queries local UserInventory state, no external I/O
    ↓ UserInventorySyncWorker.perform_async(steam_id)
UserInventorySyncWorker#perform
    ↓ UserInventorySyncService.call(steam_id)  — see
      `.claude/adr/fetcher/cross-scenario-service-layer.md`: the actual
      Steam call, backfill, and persistence live in this cross-Scenario
      service, not inline in the worker
```

## Testing

General RSpec mechanics — spec levels, fixtures vs. `FactoryBot`,
`WebMock` vs. VCR, `Sidekiq::Testing.fake!`, real-Redis-connection
testing for a job's own direct writes, the Sorbet-sigil exemption,
example granularity/structure — are governed by
`.claude/styleguides/rspec-conventions.md` and
`.claude/adr/fetcher/rspec-testing-strategy.md`. This section only adds
what's genuinely specific to workers/schedulers beyond those rules. A
worker or scheduler spec is a **unit spec** (see that styleguide's layer
table) — it lives under `spec/workers/`/`spec/schedulers/`, no `type:`
metadata.

### MUST

- Trim `prices_stream` before/after any example that publishes to it
  (e.g. `XTRIM prices_stream MAXLEN 0`, via a
  `spec/support/redis_stream_helper.rb` support module) so one example's
  entries can't leak into another's assertions, or collide with
  whatever a locally-running app instance already wrote to the same
  stream in dev.

## Canonical Implementations

- `app_fetcher/app/workers/price_update_worker.rb`
- `app_fetcher/app/workers/user_inventory_sync_worker.rb`,
  `app_fetcher/app/workers/inventory_value_update_worker.rb`
- `app_fetcher/app/schedulers/price_scheduler.rb`,
  `app_fetcher/app/schedulers/user_inventory_sync_scheduler.rb`
- `app_fetcher/config/schedule.yml`, `app_fetcher/config/sidekiq.yml`,
  `app_fetcher/config/initializers/sidekiq.rb`
- `app_fetcher/spec/workers/price_update_worker_spec.rb` — concrete case
  for `rspec-conventions.md`'s real-Redis-connection rule (asserts
  against `XRANGE "prices_stream", "-", "+"`) and its
  `aggregate_failures` guidance (checks the `PriceLog` row, the `Item`'s
  updated price fields, and the stream entry together)
- `app_fetcher/spec/workers/user_inventory_sync_worker_spec.rb`,
  `app_fetcher/spec/workers/inventory_value_update_worker_spec.rb`
- `app_fetcher/spec/schedulers/price_scheduler_spec.rb` — concrete case
  for `rspec-conventions.md`'s `Sidekiq::Testing.fake!` rule (asserts
  `PriceUpdateWorker.jobs.size` and the enqueued `item.id`s, never that
  `PriceUpdateWorker#perform` itself ran)

## Related ADR

- `.claude/adr/fetcher/price-updates-via-redis-stream.md` — why
  `PriceUpdateWorker` publishes to a capped Redis Stream instead of
  Pub/Sub or a direct WebSocket push, and why that's shipped ahead of any
  consumer.
- `.claude/adr/fetcher/rspec-testing-strategy.md` — why a background
  job's spec doesn't fit cleanly into "unit" or "integration," and why
  `STREAM_REDIS_POOL` specifically gets a real Redis connection while
  Sidekiq's own queue gets `Sidekiq::Testing.fake!` instead.
