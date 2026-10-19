# A Cross-Scenario `app/services/` Layer, With a Narrow Controller-Persistence Carve-Out

## Status

Accepted

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
(`agent/plans/user-inventory-persistence.md`) needs a sequence — fetch
a user's inventory from Steam, resolve which `market_hash_name`s
already have an `Item` row vs. which are new, backfill the new ones,
and persist `user_inventories`/`user_inventory_items` — that must run
**identically** from two independent trigger points: `Api::V1::
InventoriesController#show`'s cold-start branch and an initial `#refresh`
action (both Scenario 1, synchronous, inside the request/response
cycle; the refresh action was later removed as unused), and a new
`UserInventorySyncWorker` (Scenario 3, async, inside a Sidekiq job, on
a weekly cadence). This is the first time any
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

> **Amended 2026-10-19:** the "two or more Scenarios" membership
> criterion stated in this section is superseded — a cohesive
> single-Scenario operation may also be a service. Everything else here
> (the layer's existence, its naming, the `.call`/`ServiceResult`
> contract, and the controller-persistence carve-out) still stands. See
> the Amendment section at the end of this ADR.

Introduce a new layer, `app/services/`, for logic that must run
identically from more than one Scenario — concretely, for logic needed
by both a Scenario-1 controller action and a Scenario-3 worker with no
behavioral difference between the two call sites. Classes here are
flat, top-level (not domain-namespaced under `Steam::`), like every
other `app_fetcher` application-layer class — parsers, builders,
workers, schedulers, and caching all stay flat even when they call
`Steam::Client`; only the `lib/steam/` integration boundary
(`Steam::Client`, `Steam::Response`) uses the namespace (see
Implementation Constraints). Calling `Steam::Client` is
a capability this layer *permits*, not a requirement for membership in
it — the qualifying criterion is purely "needed identically by two or
more Scenarios." *(Superseded 2026-10-19: membership is now
responsibility-based — see the Amendment section.)* Its first class is
`UserInventorySyncService`
(`app_fetcher/app/services/user_inventory_sync_service.rb`): it calls
`Steam::Client#fetch_user_inventory`, resolves known vs. missing items,
backfills missing `Item` rows, persists `user_inventories`/
`user_inventory_items`, and returns a `Result` (`success`/`error`/
`items`). Its second is `InventoryValueRecordingService`
(`app_fetcher/app/services/inventory_value_recording_service.rb`): no
Steam call at all, just a DB read/sum/upsert, originally needed
identically by `InventoryValuesController#index`'s cold-start seed and
`InventoryValueUpdateWorker`'s nightly fan-out — confirming the
qualifying criterion really is responsibility, not "touches Steam."
*(The caller-count framing here is superseded by the 2026-10-19
amendment; the read endpoint's seed was removed on 2026-10-20, leaving
`InventoryValueUpdateWorker` as the sole caller — the service stays in
this layer because recording a snapshot is its own operation, not
because a controller also called it.)* It's called as `InventoryValueRecordingService.call(steam_id)` —
the same class-method `.call` shape as `UserInventorySyncService.call`
and `PriceUpdateService.call`. (It originally shipped as an instance
method, `.new(steam_id).call!`, on the reasoning that either shape was
equally valid for this layer; revised to the mandated class-method `.call`
shape below once the resulting split call convention across this
layer's three members turned out to read as inconsistent in practice,
not merely stylistically different.)

**Return shape (superseded).** The per-service return values described
above — `UserInventorySyncService`'s nested `Result`, and
`InventoryValueRecordingService` returning the written record — no longer
describe the layer. All `app/services/` classes now return a single
shared `ServiceResult[Payload]` value object; see
`agent/adr/fetcher/service-result-contract.md` and
`agent/styleguides/fetcher/services.md`. The `.call` naming/entry-point
mandate below still holds; only the return-shape guidance is superseded.

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
  cold-start branch.

*(The former `InventoryValueRecordingService` cold-start-seed call site
was removed on 2026-10-20: `InventoryValuesController#index` is now a
pure read, and the nightly `InventoryValueUpdateWorker` is the only
writer of `InventoryValueLog` rows.)*

Everything else in `layered-ingestion-pipeline.md` is unchanged: the
general "only a worker persists" rule, `ItemsListUpdateWorker`'s own
unrelated batch-backfill role, and the three-Scenario map all still
hold for every other ingestion path in this app.

**Read-only query collaboration.** A service may use a read-only
concern query under `app/queries/` for its read step — for example,
`InventoryValueRecordingService` calling `InventoryValueQuery` to obtain
the snapshot it persists. This adds a dependency, not a second writer:
the query returns structs and performs no writes, and the service
remains the owner of the sequence and its persistence. A service is
still an *acting* operation (it writes or has side effects), not a
read-only query — and a query object never becomes a service merely
because more than one caller reads through it (see the 2026-10-19
amendment).

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
  branch (and the since-removed `#refresh` action): real DB writes (an
  `Item.upsert_all`, plus
  `user_inventories`/`user_inventory_items` persistence) now happen
  inside the request/response cycle, not just a Steam HTTP round-trip.
  Accepted deliberately in exchange for removing the FK-ordering gap.

### Risks

- A future contributor could reach for `app/services/` out of
  convenience ("this looks like business logic") rather than because a
  cohesive operation has no better existing home.
  `architecture-layers.md`'s and `services.md`'s "When to Use"/"Choosing
  the Right Home" text is the guard against that — logic that belongs to
  a parser, builder, query object, cache class, or model stays there,
  and a couple of delegating lines stay inline.
- The controller-persistence carve-out could be misread as a general
  loosening of "controllers don't persist." It is not — it applies only
  to the named call sites listed above. Any other controller wanting to
  persist synchronously needs its own explicit decision through this
  same process, not an appeal to this ADR by analogy.

## Implementation Constraints

- Classes live flat under `app/services/`, top-level, named
  `<Noun>Service` — `UserInventorySyncService` at
  `app/services/user_inventory_sync_service.rb` — not namespaced under
  `Steam::` even though it calls `Steam::Client`, like every other
  `app_fetcher` application-layer class (parsers, builders, workers,
  schedulers, caching); only the `lib/steam/` integration boundary
  (`Steam::Client`, `Steam::Response`) uses the namespace.
- A class in this layer may call `Steam::Client` directly and persist
  models — the two things parsers and builders may not do.
- Exposed as a class-method `self.call` (or `class << self; def call;
  ...; end; end`), mirroring `PriceUpdateService`/`UserInventorySyncService`
  — not an instance method (`.new(...).call!`). Originally left
  unmandated (see Decision); fixed to this one shape once the per-service
  variation it allowed read as inconsistent rather than as a meaningful
  choice.
- May be called synchronously, inline, from a controller action before
  rendering (Scenario 1) — restricted to the named call sites above,
  not a general permission for any controller.
- May also be called from a worker (Scenario 3) with the identical call
  shape — no special casing needed there, since workers could already
  persist.
- May depend on a read-only concern query under `app/queries/` for its
  read step, but that dependency never transfers write ownership: the
  query returns structs, performs no writes, and the service remains the
  only writer in the sequence.
- A class in this layer must be one cohesive business operation with a
  single reason to change and no better existing home (parser, builder,
  query object, caching, model) — not a default home for any non-trivial
  logic a controller or worker happens to need. Caller count is not a
  criterion (amended 2026-10-19): a cross-Scenario sequence and a
  single-Scenario SRP extraction are judged by the same responsibility
  test.
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

  *Superseded by the 2026-10-19 amendment:* the caller-count framing
  above no longer decides membership. Both placements are unchanged —
  `UserInventory.sync!` stays a model method because it is a model-owned
  bulk-replace step, while `InventoryValueRecordingService` is a
  snapshot-recording operation with its own preconditions and therefore
  belongs in this layer.

## Amendment (2026-10-19): Service-Layer Membership Is Responsibility, Not Caller Count

### Context

The layer originally admitted only sequences required identically by two
or more Scenarios, and `services.md` still stated that as the sole
membership rule. `PriceUpdateService` broke that framing in practice: it
is called only from `PriceUpdateWorker` and was extracted to keep
`perform` as thin orchestration glue rather than a mix of domain logic
and job mechanics (`agent/plans/refactor-price-update-worker.md`).
`architecture-layers.md` was updated at that time to admit this shape,
but this ADR and `services.md` were not, leaving three documents with two
different rules.

The narrower criterion also conflated two independent questions: *does
this logic have a home?* and *how many callers does it have?* Reuse is
evidence that a boundary is real, not the reason the boundary exists. A
worker that owns a 24h-change calculation, a transaction, and a price-log
build has more than one responsibility whether or not a second caller
ever appears.

### Decision

A class in `app/services/` is justified by **responsibility**, not by
caller count. It qualifies when both hold:

- it is one cohesive business operation with a single `.call` entry
  point, one reason to change, and boundaries testable in isolation;
- no existing layer owns it — it is not parsing, building, read-only
  aggregate querying, cache mechanics, or a model invariant.

Cross-Scenario reuse is a strong signal that the boundary is real, but it
is not a criterion: it is a common consequence of drawing the boundary
correctly, not a separate reason to create a service. Nor is a single
caller a reason to keep mixed responsibilities inline.

The rest of this ADR is unchanged: the layer still exists for
application-layer orchestration; classes remain flat, top-level
`<Noun>Service`; `.call` returns `ServiceResult[Payload]`; and the
controller-persistence carve-out still applies only to the named call
sites.

### Constraints

- A service must be a cohesive operation, not a collection of helpers
  extracted only to shorten a class. A couple of delegating lines stay
  inline.
- "No better existing home" is a hard precondition: parser, builder,
  query object, caching, and model are checked first. `app/services/` is
  not a substitute for placing logic in the layer that owns it.
- The single-`.call`/`ServiceResult[Payload]` interface, naming, and
  dependency rules in `services.md` are unchanged.
- The controller-synchronous-persistence rule is unchanged: a controller
  may call a read-only/computing service, but may persist synchronously
  only at the named call sites.
- A controller may also call a cohesive **side-effect** service that
  writes no records — e.g. `PriceWarmupService` owning the warmup cap,
  dedup key/TTL, and `PriceUpdateWorker` enqueue loop for
  `ItemPricesController#dynamics`. This is not the persistence
  carve-out: the service only performs the controller's existing
  enqueue/dedup side effect behind one nameable operation.

### Alternatives Considered

- **Keep caller count as a hard requirement.** Rejected: it rejects
  `PriceUpdateService` despite its clear SRP boundary and leaves the
  worker with mixed responsibilities; it also conflicts with
  `architecture-layers.md` and shipped code.
- **Drop the layer and use `app_core`-style `app/actions/`.** Rejected:
  the layer's `.call`/`ServiceResult` contract and worker/controller
  sharing remain useful, and a worker has no request scope.
- **Keep reuse as a SHOULD signal only.** Rejected in favour of removing
  it from the criteria entirely: a SHOULD still reads as a positional
  rule and invites the same "one caller means no service" conclusion.
  Reuse is documented as a common consequence, not a membership test.

## Related

- `agent/adr/fetcher/layered-ingestion-pipeline.md` — the ADR this
  one narrowly amends; its general Scenario map and "only a worker
  persists" rule are otherwise unchanged.
- `agent/adr/fetcher/price-cache-invalidation.md` — the closest
  precedent for introducing a new top-level layer before its first use,
  though that layer is read-only where this one persists and performs
  external I/O.
- `agent/styleguides/fetcher/architecture-layers.md` — updated
  alongside this ADR with the concrete `app/services/` Structure entry.
- `agent/styleguides/fetcher/services.md` — the layer's current rules,
  including the responsibility-based "When to Use" this amendment
  introduces.
- `agent/styleguides/rails-layering.md` — the cross-app invariant this
  decision stays inside (Controller → orchestration → Models, one
  direction).
- `agent/plans/user-inventory-persistence.md` — the plan this
  decision unblocks.
