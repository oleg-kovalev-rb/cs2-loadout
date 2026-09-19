# Publish Price Updates to a Redis Stream

## Status

Accepted

## Context

Right now, `app_core`'s dashboard only reflects prices as of the last
full page load — its own view explicitly says "Auto-refresh isn't wired
up yet — reload the page for the latest prices"
(`app_core/app/views/dashboards/show.html.erb`). `app_fetcher` needs a
way to make each price update available for near-real-time delivery to
`app_core` (or any future consumer), without `app_core` polling
`app_fetcher`'s API on a tight interval.

Both apps already share the same Redis deployment (see
`docker-compose.yml`), and `app_fetcher`'s `PriceUpdateWorker` already
runs inside the process that knows about every price change the moment
it happens.

## Decision

`PriceUpdateWorker` publishes every price update as an entry to a Redis
Stream, `prices_stream`, via `STREAM_REDIS_POOL.with { |redis|
redis.xadd(...) }`, with fields `market_hash_name`, `price_cents`,
`change_24h_cents`, `fetched_at` (a string Unix timestamp), capped with
`maxlen: 10_000, approximate: true`.

No consumer exists yet. This is deliberate write-ahead-of-read
infrastructure — the publish side ships independently of when/how a
reader is built, rather than blocking on having a consumer designed
first.

## Alternatives Considered

### Alternative: Redis Pub/Sub

Use `PUBLISH`/`SUBSCRIBE` instead of a stream.

Rejected because:

- Pub/Sub is fire-and-forget — a message published while no consumer is
  subscribed is lost permanently. A Stream retains bounded history, so a
  consumer that starts up later (or reconnects after a drop) can still
  read recent entries via `XREAD` instead of only ever seeing updates
  that happen to occur while it's connected.

### Alternative: ActionCable / WebSockets directly from `app_fetcher`

Push updates straight to `app_core`'s browser clients from `app_fetcher`.

Rejected because:

- would require `app_fetcher` to either know about `app_core`'s
  ActionCable server directly (tight cross-app coupling) or stand up its
  own WebSocket server — significant new surface for a feature whose
  consumer side doesn't exist yet.

### Alternative: `app_core` polls `app_fetcher`'s API on an interval

The simplest option, and likely still how a first "auto-refresh" cut
gets built.

Not rejected outright — polling `/api/v1/price_histories` remains a
reasonable near-term way to consume this data. The Stream is what leaves
room for a genuinely push-based follow-up (an ActionCable or SSE bridge
that tails `prices_stream`) without re-touching the ingestion side again.

## Consequences

### Positive

- Decouples the publish side from the (currently nonexistent) consume
  side — `app_fetcher` doesn't need to know who reads this, or whether
  anyone does yet.
- Bounded memory usage via `maxlen`.
- Multiple independent consumers could read the same stream via separate
  consumer groups later, without changing the publish side.

### Negative

- Today, this is pure write-side cost — a Redis round-trip per price
  update — with no realized benefit, since nothing reads `prices_stream`.
- `approximate: true` trims lazily; the stream's actual length can
  temporarily exceed `maxlen` between trims. This is an approximate
  memory bound, not an exact cap.
- The fields written (`market_hash_name`, `price_cents`,
  `change_24h_cents`, `fetched_at`) are a de facto schema with no
  validation or versioning — nothing enforces that a future consumer's
  expectations match what's actually written.

### Risks

- A future contributor could reasonably read this as dead code ("why are
  we writing to a stream nobody reads?") and remove it. This ADR exists
  so that question has an answer before that happens.
- Conversely, a future consumer could be built against field
  names/types that were never deliberately finalized as a contract.

## Implementation Constraints

- Treat the fields currently written by `PriceUpdateWorker#publish_to_stream`
  as the stream's schema. If they change, update this ADR alongside the
  code.
- A future consumer reads via `XREAD`/consumer groups against the same
  `STREAM_REDIS_POOL` / `REDIS_URL_STREAM` — don't stand up a second,
  differently-configured Redis connection for the same stream.
- Don't remove the `xadd` call as unused/dead code without checking this
  ADR first — it's deliberate write-ahead-of-read infrastructure, not an
  oversight.
- If a future consumer needs guaranteed, exactly-once delivery rather
  than "read recent history," revisit whether consumer groups
  (`XREADGROUP`/`XACK`) are needed — the current `maxlen` +
  `approximate` setup optimizes for bounded memory, not delivery
  guarantees.

## Related

- `app_fetcher/app/workers/price_update_worker.rb`
- `app_fetcher/config/initializers/redis.rb`
- `.claude/styleguides/fetcher/background-jobs.md`
- `app_core/app/views/dashboards/show.html.erb` — the explicit
  "auto-refresh isn't wired up yet" note on the consumer side
