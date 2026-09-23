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
  (`PriceUpdateWorker`, `ItemsListUpdateWorker`).
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
  (`PriceUpdateWorker`) or an `Array[String]` of names
  (`ItemsListUpdateWorker`) — never an ActiveRecord object or a custom
  class instance.

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
  to Postgres (`ItemsListUpdateWorker`: 3).
- Route work that calls `Steam::Client` onto its own queue (`:prices`),
  separate from cheap orchestration work (`:default`) — see
  `config/sidekiq.yml`'s queue list and `PriceUpdateWorker` vs.
  `ItemsListUpdateWorker`/`PriceScheduler`. This keeps a Steam-API outage
  or rate-limit backoff from starving unrelated jobs.
- Use a bulk write (`Item.upsert_all(..., unique_by: ...)`) instead of a
  per-record loop of `.new`/`.save!` when a job processes a batch of
  independent records (see `ItemsListUpdateWorker`).
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

Api::V1::InventoriesController#save_missing_items
    ↓ ItemsListUpdateWorker.perform_async(names_batch)  — batched via each_slice(500)
ItemsListUpdateWorker#perform
    ↓ Steam::ItemParser → Item.upsert_all
```

## Testing

General RSpec mechanics — spec levels, fixtures vs. `FactoryBot`,
`WebMock` vs. VCR, the Sorbet-sigil exemption, example granularity — are
governed by `.claude/styleguides/rspec-conventions.md` and
`.claude/adr/fetcher/rspec-testing-strategy.md`; this section only adds
what's specific to testing workers/schedulers. A worker or scheduler
spec is a **unit spec** (see that styleguide's layer table) — it lives
under `spec/workers/`/`spec/schedulers/`, no `type:` metadata.

### MUST

- Run every worker/scheduler spec under `Sidekiq::Testing.fake!`
  (configured once, globally, in `rails_helper.rb`, not per-spec).
  `.perform_async` enqueues into an in-memory array instead of hitting a
  real Sidekiq-backed Redis connection — assert against `<Worker>.jobs`
  (its size, `["args"]`), not a side effect of the enqueued job actually
  running. `PriceScheduler`'s spec is the concrete case: assert
  `PriceUpdateWorker.jobs.size` and the enqueued `item.id`s, never that
  `PriceUpdateWorker#perform` itself ran.
- Test `STREAM_REDIS_POOL` against a real Redis connection, never
  mocked. `PriceUpdateWorker#publish_to_stream` writes directly to
  Redis, not through Sidekiq's queue — that write *is* the job's own
  documented responsibility (see
  `.claude/adr/fetcher/price-updates-via-redis-stream.md`), so its spec
  asserts against what was actually written (`XRANGE "prices_stream",
  "-", "+"`), never a stubbed `redis.xadd` call. This is why
  `app_fetcher`'s CI runs a real Redis service.
- Trim `prices_stream` before/after any example that publishes to it
  (e.g. `XTRIM prices_stream MAXLEN 0`, via a
  `spec/support/redis_stream_helper.rb` support module) so one example's
  entries can't leak into another's assertions, or collide with
  whatever a locally-running app instance already wrote to the same
  stream in dev.
- Stub the Steam API the same way any other unit spec does: `WebMock`
  against `Steam::Client`'s underlying HTTP call, never a canned
  `Steam::Response` handed back in place of the real client — so the
  worker's own branching on `response.success?` is exercised for real,
  not assumed away.

### SHOULD

- Pack a success case's assertions into one `:aggregate_failures`
  example rather than several single-expectation `it`s. A
  `PriceUpdateWorker` success case typically has three things to check
  at once — the `PriceLog` row, the `Item`'s updated
  `current_price_cents`/`change_24h_cents`, and the stream entry — that
  belongs in one example, not three that each re-run the same
  stub-and-perform setup to check a single field (see
  `rspec-conventions.md`'s Example Granularity).

## Canonical Implementations

- `app_fetcher/app/workers/price_update_worker.rb`
- `app_fetcher/app/workers/items_list_update_worker.rb`
- `app_fetcher/app/schedulers/price_scheduler.rb`
- `app_fetcher/config/schedule.yml`, `app_fetcher/config/sidekiq.yml`,
  `app_fetcher/config/initializers/sidekiq.rb`
- Testing: none yet — no worker/scheduler spec exists in the repo. See
  `.claude/plans/price-update-pipeline-test-coverage.md` for the plan
  that introduces the first ones.

## Related ADR

- `.claude/adr/fetcher/price-updates-via-redis-stream.md` — why
  `PriceUpdateWorker` publishes to a capped Redis Stream instead of
  Pub/Sub or a direct WebSocket push, and why that's shipped ahead of any
  consumer.
- `.claude/adr/fetcher/rspec-testing-strategy.md` — why a background
  job's spec doesn't fit cleanly into "unit" or "integration," and why
  `STREAM_REDIS_POOL` specifically gets a real Redis connection while
  Sidekiq's own queue gets `Sidekiq::Testing.fake!` instead.
