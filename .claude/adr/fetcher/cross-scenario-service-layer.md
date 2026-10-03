# A Cross-Scenario `app/services/` Layer, With a Narrow Controller-Persistence Carve-Out

## Status

Proposed

## Context

`app_fetcher`'s layering, as fixed by `layered-ingestion-pipeline.md`,
gives every ingestion concern exactly one home: parsers (pure),
builders (DTO → unsaved AR attributes), workers (the only layer that
persists, Scenario 3), schedulers (query-and-fan-out only, Scenario 2),
and controllers (Scenario 1 — may call `Steam::Client` and, under a
narrow carve-out, a parser directly, but must defer actual persistence
to an async worker). That ADR is explicit that this app has no
`app_core`-style `app/actions/` layer: "there is no `app/actions/`
here... not something this app has or needs." Its own Risks section
goes further, pre-emptively arguing against a future contributor
"fixing" the controller's sync-parse/async-persist split into
synchronous persistence.

The user-inventory-persistence work
(`.claude/plans/user-inventory-persistence.md`) needs a sequence — fetch
a user's inventory from Steam, resolve which `market_hash_name`s
already have an `Item` row vs. which are new, backfill the new ones,
and persist `user_inventories`/`user_inventory_items` — that must run
**identically** from two independent trigger points: `Api::V1::
InventoriesController#show`'s cold-start branch and a new `#refresh`
action (both Scenario 1, synchronous, inside the request/response
cycle), and a new `UserInventorySyncWorker` (Scenario 3, async, inside
a Sidekiq job, on a weekly cadence). This is the first time any
sequence in `app_fetcher` has needed to run, unmodified, from both a
controller and a worker.

It also surfaces a correctness problem the existing carve-out doesn't
have an answer for. `show`'s existing carve-out lets a controller parse
a Steam response and render an in-memory, unsaved `Item.new`, while the
same record's actual persistence is deferred to
`ItemsListUpdateWorker`, batched and async — a client can briefly see a
response referencing an item that isn't durably saved yet, an accepted
tradeoff for that feature. `user_inventory_items.item_id` is a real
foreign key to `items.id`; a join row cannot be written for an `Item`
that doesn't exist in the database yet. If the new `Item`-backfill step
for inventory sync were deferred to an async worker the same way, there
would be a window — of unknown, unbounded length — where the
`user_inventory_items` row for a brand-new item simply cannot be
written at all, not just "written a little late." That's a materially
different, worse problem than the existing accepted tradeoff: not
staleness, but an open-ended period where the new persistence feature's
own core guarantee (a user's full current inventory is durably saved
after their request completes) doesn't hold.

## Decision

Introduce a new layer, `app/services/`, for logic that must run
identically from more than one Scenario — concretely, for logic needed
by both a Scenario-1 controller action and a Scenario-3 worker with no
behavioral difference between the two call sites. Classes here are
flat, top-level (not domain-namespaced under `Steam::`), the same
exception `background-jobs.md` already carves out for workers and
schedulers that call `Steam::Client` without being Steam-domain parsing
themselves (see Implementation Constraints). Calling `Steam::Client` is
a capability this layer *permits*, not a requirement for membership in
it — the qualifying criterion is purely "needed identically by two or
more Scenarios." Its first class is `UserInventorySyncService`
(`app_fetcher/app/services/user_inventory_sync_service.rb`): it calls
`Steam::Client#fetch_user_inventory`, resolves known vs. missing items,
backfills missing `Item` rows, persists `user_inventories`/
`user_inventory_items`, and returns a `Result` (`success`/`error`/
`items`). Its second is `InventoryValueRecordingService`
(`app_fetcher/app/services/inventory_value_recording_service.rb`): no
Steam call at all, just a DB read/sum/upsert, needed identically by
`InventoryValuesController#index`'s cold-start seed and
`InventoryValueUpdateWorker`'s nightly fan-out — confirming the
qualifying criterion really is cross-Scenario reuse, not "touches
Steam." Unlike `UserInventorySyncService.call` (a class method), it's
called as `InventoryValueRecordingService.new(steam_id).call!` — an
instance method is just as valid a shape for a class in this layer; pick
whichever reads better for the specific service, there's no single
mandated call convention.

This is deliberately **not** a re-introduction of `app_core`'s
`app/actions/` layer. `app_core`'s actions exist as a general
per-request orchestration convenience for its controllers — any
non-trivial controller logic gets one. `app_services/` in `app_fetcher`
is narrower and exists for one specific reason: the literal same
sequence is required, unmodified, from more than one Scenario. A class
here is not the default landing spot for "this feels like business
logic" — see Alternatives Considered and Implementation Constraints for
what does and doesn't qualify.

A class in this layer may do two things parsers and builders may not:
call `Steam::Client` directly, and persist models. And a controller
action may call it **synchronously, inline, before rendering** — the
sanctioned case in `app_fetcher` where Scenario-1 code triggers real
persistence itself, rather than deferring to an async worker. This
carve-out is scoped specifically to the two named call sites below. It
does not generalize to any other controller action without its own
explicit decision through this same process:

- `UserInventorySyncService` from `InventoriesController#show`'s
  cold-start branch and `#refresh`.
- `InventoryValueRecordingService` from `InventoryValuesController#index`'s
  cold-start seed (first-ever request for a `steam_id`, no log rows yet).

Everything else in `layered-ingestion-pipeline.md` is unchanged: the
general "only a worker persists" rule, `ItemsListUpdateWorker`'s own
unrelated batch-backfill role, and the three-Scenario map all still
hold for every other ingestion path in this app.

## Alternatives Considered

### Alternative: a pure resolver, with persistence duplicated per caller

Split the sequence into a pure "resolve known vs. missing items, parse
the missing ones" step (no `Steam::Client` call, no persistence) shared
between callers, with the controller and the worker each separately
calling `Steam::Client` and persisting on their own.

Considered and initially preferred for being the narrowest possible
change. Rejected because both callers need the *entire* sequence
identically, not just the resolve step — splitting it only deferred
facing that duplication, it didn't remove it. The project's own
`app/caching/` layer exists on exactly this reasoning (shared,
non-trivial logic needed by more than one caller gets its own class,
per `price-cache-invalidation.md`); the same reasoning applies here to
the full sequence, not just a slice of it.

### Alternative: duplicate the whole sequence inline in both callers

Accept the duplication rather than introduce a new layer, on the
general principle that a few similar lines are better than a premature
abstraction.

Rejected: this is substantially more than a few similar lines (an
external call, a resolve step, a conditional backfill, and a
transactional persist), and correctness here depends on the FK-ordering
behavior holding *identically* in both places. Letting that drift
between two hand-maintained copies (e.g. one call site's backfill logic
quietly diverging from the other's over time) risks exactly the kind of
subtle inconsistency a shared class exists to prevent.

### Alternative: keep deferring persistence to an async worker (today's existing carve-out, unmodified)

Keep the controller's cold-start/refresh paths building an in-memory
response the same way `show` does today for the `Item` catalog, with
all persistence — including the new `user_inventories`/
`user_inventory_items` rows — deferred to `ItemsListUpdateWorker` or an
equivalent async job.

Rejected for the reason in Context: `user_inventory_items.item_id`'s FK
constraint means the join row cannot be written until the `Item` row
exists, so deferring that write leaves an unbounded gap during which
the new feature's central guarantee doesn't hold, not just a brief
staleness window.

### Alternative: a general-purpose `app/actions/` layer for `app_fetcher`

Adopt `app_core`'s `app/actions/` convention wholesale for `app_fetcher`,
for this and any future non-trivial controller logic.

Rejected as too broad. `layered-ingestion-pipeline.md` already
evaluated and rejected a general orchestration layer for this app; this
decision doesn't reopen that question, it carves out one narrow,
named exception for a proven, repeated need. A second genuine
cross-scenario case in the future would extend this same
`app/services/` layer, not justify a broader `app/actions/`-style
layer on its own.

## Consequences

### Positive

- Removes the FK-ordering gap entirely: after
  `UserInventorySyncService.call` returns successfully, a user's full
  current inventory is guaranteed durably saved, from any of its three
  call sites.
- One place owns the fetch→resolve→backfill→persist sequence, instead
  of two independently-maintained copies that could drift.
- Gave `app_fetcher` a scoped, precedented place for a second genuine
  cross-scenario case without re-deciding the shape from zero —
  materialized as `InventoryValueRecordingService` shortly after this
  decision.

### Negative

- A sixth top-level `app/` layer to learn, on top of
  parsers/builders/workers/schedulers/caching.
- `layered-ingestion-pipeline.md`'s "no `app/actions/` here" framing is
  now only approximately true — a reader of that ADR alone, without
  this one, could misread the new layer as contradicting it outright
  rather than as a narrow, named exception.
- Added request latency on `InventoriesController#show`'s cold-start
  branch and `#refresh`: real DB writes (an `Item.upsert_all`, plus
  `user_inventories`/`user_inventory_items` persistence) now happen
  inside the request/response cycle, not just a Steam HTTP round-trip.
  Accepted deliberately in exchange for removing the FK-ordering gap.

### Risks

- A future contributor could reach for `app/services/` out of
  convenience ("this looks like business logic") rather than because a
  sequence is genuinely needed, unmodified, from two or more Scenarios.
  `architecture-layers.md`'s corresponding "When to Use" text is the
  guard against that — a single-Scenario need still belongs inline or
  in an existing layer.
- The controller-persistence carve-out could be misread as a general
  loosening of "controllers don't persist." It is not — it applies only
  to the named call sites listed above. Any other controller wanting to
  persist synchronously needs its own explicit decision through this
  same process, not an appeal to this ADR by analogy.

## Implementation Constraints

- Classes live flat under `app/services/`, top-level, named
  `<Noun>Service` — `UserInventorySyncService` at
  `app/services/user_inventory_sync_service.rb` — not namespaced under
  `Steam::` even though it calls `Steam::Client`, mirroring how
  `background-jobs.md` already keeps workers/schedulers top-level for
  the same reason (they're categorically workers/schedulers/services
  that happen to touch Steam, not Steam-domain parsing/building/client
  code itself).
- A class in this layer may call `Steam::Client` directly and persist
  models — the two things parsers and builders may not do.
- May be called synchronously, inline, from a controller action before
  rendering (Scenario 1) — restricted to the named call sites above,
  not a general permission for any controller.
- May also be called from a worker (Scenario 3) with the identical call
  shape — no special casing needed there, since workers could already
  persist.
- Reserve this layer for a sequence genuinely needed, unmodified, by two
  or more Scenarios — not a default home for any non-trivial logic a
  controller or worker happens to need.
- `UserInventory.sync!` (the model-level bulk-replace step
  `UserInventorySyncService` calls) stays a plain model method per
  `rails-layering.md` — this ADR does not change where that specific
  step lives, only what calls into the service that calls it. Contrast
  with `InventoryValueRecordingService`, which *did* move an equivalent
  pure-DB read/sum/upsert step (formerly `InventoryValueLog.record_for!`)
  out of the model and into this layer — the distinguishing factor
  between the two is not "does it touch external I/O," it's "is it
  called directly by more than one Scenario." `UserInventory.sync!` has
  exactly one caller (`UserInventorySyncService` itself); the recording
  step had two (`InventoryValuesController` and
  `InventoryValueUpdateWorker`) before this layer existed.

## Related

- `.claude/adr/fetcher/layered-ingestion-pipeline.md` — the ADR this
  one narrowly amends; its general Scenario map and "only a worker
  persists" rule are otherwise unchanged.
- `.claude/adr/fetcher/price-cache-invalidation.md` — the closest
  precedent for introducing a new top-level layer before its first use,
  though that layer is read-only where this one persists and performs
  external I/O.
- `.claude/styleguides/fetcher/architecture-layers.md` — updated
  alongside this ADR with the concrete `app/services/` Structure entry.
- `.claude/styleguides/rails-layering.md` — the cross-app invariant this
  decision stays inside (Controller → orchestration → Models, one
  direction).
- `.claude/plans/user-inventory-persistence.md` — the plan this
  decision unblocks.
