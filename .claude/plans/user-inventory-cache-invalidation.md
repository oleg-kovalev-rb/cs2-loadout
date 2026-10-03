---
status: blocked
app: fetcher
goal: Give UserInventoryCache a real, event-driven invalidation trigger (a rate-limited user "refresh inventory" endpoint) and size its TTL to actual Steam-inventory change cadence, replacing the current unexplained 5-minute-only design — no scheduled worker
created: 2026-09-29
---

# Development Plan

## Goal

`UserInventoryCache` (`app_fetcher/app/caching/user_inventory_cache.rb`)
currently caches a user's resolved `market_hash_names` list for 5
minutes, with no explicit invalidation — TTL is the only thing that ever
clears it. That 5-minute number was never derived from anything (unlike
this codebase's other TTL/cap numbers, which are tied to a concrete
constraint). Give this cache a real invalidation trigger — a
user-initiated, rate-limited "refresh my inventory" endpoint — and size
the TTL against how often a Steam inventory actually changes (days, not
minutes), so the cache stops re-fetching from Steam far more often than
the underlying data could plausibly justify.

## Expected Behavior

**Normal behavior**

- `GET /api/v1/inventories/me` behavior is unchanged for a warm cache:
  served from `UserInventoryCache`, no Steam call, same response shape.
- Cache entries now live for **5 days** instead of 5 minutes (see
  Assumptions for why this number). Within that window, repeat `GET`
  requests keep serving cached names with no new Steam call — same
  mechanism as today, just a much longer window.
- New `POST /api/v1/inventories/refresh`: invalidates the calling user's
  cached inventory entry, re-fetches from Steam, and returns the same
  response shape `GET /api/v1/inventories/me` returns — synchronously,
  in the same request/response cycle (not enqueued as a background job,
  since the point of a user clicking "refresh" is seeing the result
  immediately).

**Edge cases**

- `POST /api/v1/inventories/refresh` on a cold cache (no prior `GET`)
  still works — invalidating a key that isn't set is a no-op, and the
  subsequent fetch behaves like any other cache miss.
- A second `POST /api/v1/inventories/refresh` for the same `steam_id`
  within the same day is rejected before any Steam call, via a
  per-`steam_id` dedup flag independent of the main 5-day data TTL (a
  user can refresh again the next day even if their existing cache entry
  hasn't naturally expired yet).

**Failure behavior**

- `POST /api/v1/inventories/refresh` when the Steam call itself fails:
  identical `{ message: response.error }` / `:bad_request` behavior to
  `GET /api/v1/inventories/me`'s existing failure branch — same
  underlying orchestration logic, called from both actions (see
  Implementation Approach), each action still renders its own response
  explicitly.
- `POST /api/v1/inventories/refresh` when already rate-limited for today:
  returns `{ message: "..." }` with `:too_many_requests` (`429`) —
  unlike the existing silent warmup-dedup (a background optimization
  nobody's waiting on), this is a direct user action, so the caller needs
  to know why nothing happened.

**Must remain unchanged**

- `GET /api/v1/inventories/me`'s response shape, its existing cache-hit
  behavior, its warmup-enqueue behavior, and its handling of
  DB-missing items — none of that changes.
- `ItemPriceCache`/`PriceHistoryCache` and their invalidation from
  `PriceUpdateWorker` — untouched.

## Scope

### In Scope

- `UserInventoryCache`: TTL bump (5 minutes → 5 days), add
  `.invalidate(steam_id)`.
- A new `Steam::ResolveInventory` action object holding the
  cache-or-Steam-fetch + item-resolution + warmup-enqueue orchestration
  currently inline in `InventoriesController#show`, so `show` and the
  new `refresh` action can both call it and each render their own
  response explicitly (no shared private render method — see
  Implementation Approach).
- `Api::V1::InventoriesController`: `show` shrinks to calling the action
  object and rendering; new `refresh` action with its own per-`steam_id`
  daily dedup flag, calling the same action object after invalidating.
- `config/routes.rb`: one new route.
- Test coverage for all of the above (unit spec for `.invalidate`,
  request spec for the new endpoint and its rate limit).
- A short follow-up note appended to
  `.claude/plans/fetcher-price-caching.md`'s existing
  "Post-Implementation Addition: `UserInventoryCache`" section, pointing
  at this plan (historical record, not rewritten).

### Out of Scope

- **A scheduled/periodic worker that iterates known users and
  re-checks/invalidates their inventory cache** — explicitly considered
  and rejected during design discussion with the user. Unlike
  `PriceScheduler` (which refreshes `Item`, a shared table where one
  refresh benefits every viewer of that item), a per-user inventory
  refresh benefits exactly one person; a blind periodic sweep would
  spend the shared `steam_inventory_rpd: 1000/day` Prop budget
  (`config/initializers/prop.rb`) on dormant accounts for no
  freshness benefit a well-sized TTL doesn't already provide for active
  users, for free. Do not add one.
- Moving the `Steam::Client` call into `UserInventoryCache` itself — it
  stays a controller responsibility. `internal-api-controllers.md`
  already scopes `Steam::Client` calls to controllers/workers, and
  `caching.md`'s Dependencies section scopes `app/caching/` classes to
  calling `Item`/`PriceLog` (i.e. the DB), not external HTTP.
- Any change to `ItemPriceCache`/`PriceHistoryCache`.
- Writing the actual `.claude/styleguides/fetcher/caching.md` edit — seе
  "Styleguide Follow-Up" below. This plan documents the decision that
  motivates the edit; producing the edited styleguide text is
  `styleguides-check`'s job, per this project's pipeline.
- Any `app_core`/frontend work — this plan adds only the backend
  endpoint a future "refresh" button would call, not the button itself.

## Implementation Approach

**`UserInventoryCache` changes.** Bump `TTL` from `5.minutes` to
`5.days` (see Assumptions). Add a class method mirroring
`ItemPriceCache.invalidate`'s exact shape:

```ruby
sig { params(steam_id: String).void }
def invalidate(steam_id)
  Rails.cache.delete(cache_key(steam_id))
end
```

No change to `.read`/`.write` — they keep calling the DB/Steam
themselves as before; this class still never calls `Steam::Client`.

**New `Steam::ResolveInventory` action object**, not a private controller
method. `show`'s current body — read-or-fetch-from-Steam, resolve items
via `ItemPriceCache`, enqueue missing-item backfill, enqueue price
warmup — is pure orchestration with no rendering in it until the very
last line; that's exactly the case
`internal-api-controllers.md`'s existing SHOULD rule already anticipates
("If an action needs more than one collaborator call... that's a sign
the logic belongs in a builder/action object instead of the
controller"). Extracting it into a private controller method would still
leave rendering implicit/shared; the user asked instead for the
orchestration to move into a real, independently-testable object, with
each action writing its own `render` call explicitly. Shape, mirroring
`app_core`'s existing `Steam::LoginUser`/`Steam::ProfileFetcher`
action-object convention (`self.call`, `Steam::` namespace since this
*is* Steam-domain orchestration, unlike the deliberately-generic
top-level `app/caching/` classes):

```ruby
module Steam
  class ResolveInventory
    extend T::Sig

    class Result < T::Struct
      const :success, T::Boolean
      const :error, T.nilable(String)
      const :inventory_items, T.nilable(T::Array[Item])
    end

    sig { params(steam_id: String).returns(Result) }
    def self.call(steam_id)
      items_names = UserInventoryCache.read(steam_id)

      unless items_names
        response = Steam::Client.new.fetch_user_inventory(steam_id)
        return Result.new(success: false, error: response.error, inventory_items: nil) unless response.success?

        items_names = response.data.market_hash_names
        UserInventoryCache.write(steam_id, items_names)
      end

      items = ItemPriceCache.fetch_for(items_names)
      missing_names = items_names - items.keys
      save_missing_items(missing_names)
      new_items = missing_names.map { |name| Item.new(Steam::ItemParser.parse(name)) }
      inventory_items = items.values + new_items
      enqueue_price_warmup(items.values)

      Result.new(success: true, error: nil, inventory_items: inventory_items)
    end

    # save_missing_items / enqueue_price_warmup move here as private
    # class methods, unchanged from their current controller bodies —
    # neither depends on anything HTTP-specific.
  end
end
```

`Result` is a distinct type from `Steam::Response[DataClass]` —
`steam-response-objects.md` explicitly scopes that struct to "the return
value of any `Steam::Client` method," not general `app_fetcher` domain
data (this result carries resolved `Item` records, not a Steam DTO) — so
this plan introduces a new, smaller struct rather than reusing or
extending that one, while keeping the same familiar `success?`/`error`
shape for consistency.

The controller becomes:

```ruby
sig { void }
def show
  render_resolved_inventory(Steam::ResolveInventory.call(current_steam_id))
end

sig { void }
def refresh
  dedup_key = "inventory_refresh_pending:#{current_steam_id}"
  unless Rails.cache.write(dedup_key, true, unless_exist: true, expires_in: REFRESH_DEDUP_TTL)
    render json: { message: "Inventory refresh already requested today" }, status: :too_many_requests
    return
  end

  UserInventoryCache.invalidate(current_steam_id)
  render_resolved_inventory(Steam::ResolveInventory.call(current_steam_id))
end

private

sig { params(result: Steam::ResolveInventory::Result).void }
def render_resolved_inventory(result)
  unless result.success
    render json: { message: result.error }, status: :bad_request
    return
  end

  render json: {
    items_count: result.inventory_items.size,
    items: result.inventory_items.as_json(only: [ :market_hash_name, :metadata, :current_price_cents, :change_24h_cents ])
  }, status: :ok
end
```

This keeps a tiny private helper for the JSON-shaping part specifically
(so the response format literally can't drift between `show` and
`refresh`), while the actual business orchestration — the part the user
wants out of the controller — lives entirely in `Steam::ResolveInventory`
and is unit-testable on its own, independent of any HTTP request. If
`styleguides-check` judges even this JSON-shaping helper unnecessary
(e.g. prefers each action to inline its own `render`), that's a small,
easily-adjusted implementation detail, not a scope change.

`REFRESH_DEDUP_TTL = T.let(1.day, ActiveSupport::Duration)`, named and
shaped like the existing `WARMUP_DEDUP_TTL` constant.

**Routing.** Add `post "inventories/refresh", to: "inventories#refresh"`
to the existing `namespace :api do; namespace :v1 do; ... end; end`
block in `config/routes.rb`, alongside the existing `inventories/me`
route. `POST` because this triggers a side effect (cache invalidation +
a forced external call), matching `internal-api-controllers.md`'s
existing "POST when the action does more than a trivial read" pattern
already used for `price_histories`.

**Styleguide Follow-Up (for `styleguides-check`, not this plan).**
`.claude/styleguides/fetcher/caching.md`'s current "Interface" section
mandates exactly `.fetch_for`/`.invalidate` per caching class.
`UserInventoryCache` now has three public methods
(`.read`/`.write`/`.invalidate`) — a different, equally legitimate shape
for a different data-flow: its fallback source (`Steam::Client`) can
fail in a way the caller must branch on, so (per
`internal-api-controllers.md` and this class's own Dependencies) the
fetch itself must stay in the controller rather than being owned
internally by a self-contained `.fetch_for` the way `ItemPriceCache`
owns its DB fallback. The agreed direction (discussed at length with the
user this session, not to be re-litigated) is for the styleguide to
describe a small vocabulary of primitives with fixed meaning —
`.fetch_for` (bulk, self-contained fallback), `.read`/`.write`
(single-key, caller-supplied value), `.invalidate` (single-key delete,
added only when a real caller triggers it) — with each class documenting
which subset it implements, instead of a single mandatory two-method
shape. It should also note that for a class with no scheduled writer
(like this one), the TTL isn't a pure safety net the way it is for
`ItemPriceCache`/`PriceHistoryCache` — it doubles as the only automatic
refresh path for a user who never uses the manual endpoint, and should
be sized accordingly (see Assumptions). `UserInventoryCache` becomes the
styleguide's second canonical implementation. This plan intentionally
does not draft that wording — flagging it here is what lets
`styleguides-check` do that work with full context instead of
rediscovering it.

Also note: `.claude/styleguides/fetcher/caching.md` currently has an
unrelated, uncommitted, superseded edit on disk from earlier in this
session (an abandoned attempt at documenting a "TTL-only variant"). The
implementer should treat the file's current on-disk content as scratch
and let `styleguides-check` produce the final text fresh, rather than
trying to preserve or diff against that abandoned edit.

**Action/Service Layer Follow-Up (also for `styleguides-check`).**
`Steam::ResolveInventory` is `app_fetcher`'s *first* action/service-style
object — CLAUDE.md's structure overview for `app_fetcher` lists
`parsers/builders/workers/schedulers/controllers` only, no
`app/actions/`. The only existing textual precedent for this in
`app_fetcher` is `internal-api-controllers.md`'s SHOULD rule mentioning
"a builder/action object" as an escape valve, without defining its
shape, naming, location, or a result-type convention. This plan proposes
a concrete starting point — `app/actions/steam/`, `Steam::` namespace,
`self.call`, mirroring `app_core`'s existing `app/actions/steam/`
directory (`Steam::LoginUser`) for cross-app symmetry, plus a small
per-action `Result` struct distinct from `Steam::Response` (see above) —
but, per this project's own precedent for `app/caching/` (which got a
dedicated ADR + styleguide before its first real usage), introducing
`app_fetcher`'s first action-object layer is exactly the kind of "guide
is missing" case `styleguides-check`/`create-styleguide-from-scratch` is
for. Treat the shape proposed here as a starting draft for that step to
confirm or revise, not as a settled convention.

## Files To Modify

- `app_fetcher/app/caching/user_inventory_cache.rb` — bump `TTL` to
  `5.days`; add `.invalidate(steam_id)`.
- `app_fetcher/app/controllers/api/v1/inventories_controller.rb` —
  `show` shrinks to calling `Steam::ResolveInventory.call` + rendering;
  add `refresh` action, `REFRESH_DEDUP_TTL` constant, and the small
  `render_resolved_inventory` JSON-shaping helper; remove
  `save_missing_items`/`enqueue_price_warmup` (moved into the new action
  object).
- `app_fetcher/config/routes.rb` — add the `POST /api/v1/inventories/refresh` route.
- `app_fetcher/spec/caching/user_inventory_cache_spec.rb` — add
  `.invalidate` coverage (mirroring `item_price_cache_spec.rb`'s
  `.invalidate` example).
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb` — add a new
  `RSpec.describe "POST /api/v1/inventories/refresh", type: :request`
  block (a second top-level `describe` in this file, mirroring
  `price_histories_spec.rb`'s per-endpoint naming style; the file is
  already scoped to `Api::V1::InventoriesController` as a whole per
  `rspec-conventions.md`'s controller-mirroring rule, not to one action).
  Existing examples should need no behavioral changes, only continuing
  to pass, since `Steam::ResolveInventory` is a pure extraction of
  `show`'s current logic.
- `.claude/plans/fetcher-price-caching.md` — append a short, dated
  follow-up note to the existing "Post-Implementation Addition:
  `UserInventoryCache`" section, pointing at this plan, instead of
  leaving its "known gap" language as the last word.

## Files To Create

- `app_fetcher/app/actions/steam/resolve_inventory.rb` —
  `Steam::ResolveInventory`, the new action object described in
  Implementation Approach. Necessary because the orchestration currently
  inline in `show` needs to run identically from two actions (`show`,
  `refresh`) and be independently unit-testable, per the user's explicit
  request to move it out of the controller rather than share it via a
  private controller method.
- `app_fetcher/spec/actions/steam/resolve_inventory_spec.rb` — unit spec
  (no `type:` metadata, per `rspec-conventions.md`'s layer→level mapping
  for action/plain-class objects) covering: cache hit (no Steam call, no
  `Item` query beyond `ItemPriceCache.fetch_for`'s own), cache miss
  fetches from Steam and writes the cache, Steam failure returns a
  `Result` with `success: false` and the underlying error, missing-item
  backfill enqueue, and price-warmup enqueue (cap + dedup) — effectively
  the same scenarios `inventories_spec.rb` covers today for `show`, now
  exercisable directly without an HTTP round-trip.

## Test Plan

- **`spec/caching/user_inventory_cache_spec.rb`** (unit, no `type:`):
  add a `.invalidate` example — write a value, invalidate it, assert a
  subsequent `.read` returns `nil` again (mirrors
  `item_price_cache_spec.rb`'s `.invalidate` example, adapted to
  `.read` instead of `.fetch_for` since there's no DB fallback to count
  queries against).
- **`spec/actions/steam/resolve_inventory_spec.rb`** (new, unit, no
  `type:`) — per `rspec-conventions.md`'s "prefer a unit spec over a
  request spec to exercise a class's edge cases," this is now where the
  orchestration's own branches get exhaustive coverage, calling
  `Steam::ResolveInventory.call(steam_id)` directly (no HTTP):
  - Cache hit: `UserInventoryCache` pre-populated, no Steam call made,
    `Result.success` is `true` with the expected `inventory_items`.
  - Cache miss: Steam is called once (`WebMock`, per this codebase's
    unit-level convention — see `rspec-conventions.md`'s Dependencies),
    `UserInventoryCache` ends up written with the fetched names.
  - Steam failure (`success: 0` / non-200 via `WebMock`): `Result.success`
    is `false`, `Result.error` is the underlying error, no cache write.
  - Missing-item backfill: names not backed by an `Item` row enqueue
    `ItemsListUpdateWorker` in slices of 500 (`Sidekiq::Testing.fake!`).
  - Price warmup: unpriced items enqueue `PriceUpdateWorker` up to the
    existing cap (20) with the existing dedup-flag behavior — this is a
    straight move of `inventories_spec.rb`'s existing warmup/warmup-cap
    examples down to this new unit level, since they're really about
    `Steam::ResolveInventory`'s own branches, not the HTTP boundary.
- **`spec/requests/api/v1/inventories_spec.rb`**:
  - `GET /api/v1/inventories/me` narrows to boundary concerns per
    `rspec-conventions.md`'s Responsibilities section (auth, one
    representative happy path, response shape) now that the exhaustive
    cache-hit/warmup/warmup-cap branches live in
    `resolve_inventory_spec.rb` — existing examples can stay if
    `styleguides-check`/implementation judges the duplication harmless,
    but the new unit spec is the source of truth for those branches
    going forward; don't maintain both in perpetuity.
  - New `POST /api/v1/inventories/refresh` context, following the file's
    existing WebMock-stub-in-`before` style — this one *is* about the
    boundary (the dedup rate-limit is HTTP-request-shaped), so it stays
    at the request level:
    - A first refresh call, on a warm cache, invalidates it and hits
      Steam again (assert via `have_been_made.once` scoped to the
      refresh call, after priming the cache with a prior `GET`) and
      returns the same response shape as `show`.
    - A second refresh call for the same `steam_id` within the same day
      is rejected (`:too_many_requests`, no new Steam call).
    - A refresh call on a cold cache (no prior `GET`) still succeeds and
      hits Steam once.
    - A refresh call when the Steam response fails returns
      `{ message: ... }` / `:bad_request` — exercises
      `render_resolved_inventory`'s failure branch through the actual
      HTTP boundary once, complementing (not duplicating)
      `resolve_inventory_spec.rb`'s own failure-branch coverage.
  - Regression: existing `GET` examples must keep passing unmodified in
    observable shape, confirming the `Steam::ResolveInventory` extraction
    changes nothing externally visible.

## Implementation Steps

1. TDD `UserInventoryCache.invalidate` against
   `spec/caching/user_inventory_cache_spec.rb`; bump `TTL` to `5.days`
   in the same class.
2. Create `Steam::ResolveInventory` (`app/actions/steam/resolve_inventory.rb`)
   by moving `show`'s current body — including the private
   `save_missing_items`/`enqueue_price_warmup` methods — out of the
   controller verbatim, behind TDD in the new
   `spec/actions/steam/resolve_inventory_spec.rb`.
3. Update `InventoriesController#show` to call
   `Steam::ResolveInventory.call` + the new `render_resolved_inventory`
   helper; re-run the full existing `inventories_spec.rb` suite to
   confirm it's still green before adding anything new (isolates the
   extraction from the new feature).
4. Add the `POST /api/v1/inventories/refresh` route, the `refresh`
   action, and `REFRESH_DEDUP_TTL`; TDD against new examples in
   `inventories_spec.rb` (happy path, dedup rejection, cold-cache path,
   Steam-failure path).
5. Append the follow-up note to
   `.claude/plans/fetcher-price-caching.md`.

## Verification

- `docker compose run --rm app_fetcher bash -c "RAILS_ENV=test bundle exec rspec"` — full suite green.
- `docker compose run --rm app_fetcher bash -c "bin/rubocop <touched files> -f simple"` — clean (autocorrect if needed, matching this codebase's established pattern for array-literal bracket spacing).
- `docker compose run --rm app_fetcher bash -c "bundle exec srb tc"` — compare error count/categories against the baseline already recorded in `fetcher-price-caching.md`'s Verification section; no new category introduced.
- `docker compose run --rm app_fetcher bin/brakeman --no-pager`.
- Manual: `curl` (or the request spec itself) confirming a `POST
  /api/v1/inventories/refresh` immediately after a `GET
  /api/v1/inventories/me` triggers a second Steam call, and a repeat
  `POST` within the same day is rejected.

## Risks

- Moving `show`'s entire body into `Steam::ResolveInventory` touches the
  one action this codebase's existing request spec suite covers most
  heavily (cache-hit, warmup, warmup-cap, missing-items) — a mechanical
  slip here would show up as regressions across several existing
  examples, not just new ones. Step 3's "extract, then re-run the full
  existing suite before adding anything new" ordering exists specifically
  to isolate that risk from the new feature's own bugs.
- This is a larger extraction than a same-file private-method refactor
  would have been — real risk of behavior drift (e.g. subtly changing
  argument shapes between `save_missing_items`/`enqueue_price_warmup`'s
  controller-private form and their new action-object-private form).
  Mitigated by moving the bodies verbatim in step 2 rather than
  rewriting them, and by the regression pass in step 3.
- `Steam::ResolveInventory` is `app_fetcher`'s first action-object class
  — there's no existing styleguide governing its shape yet (see "Action/
  Service Layer Follow-Up" above). `styleguides-check` may revise the
  namespace, location, or `Result` shape proposed here; treat this plan's
  code sketch as a concrete starting point, not a locked-in design.
- `show`'s existing Steam-failure branch (`response.success?` false) has
  no dedicated existing spec exercising it directly today. This plan
  adds coverage for it at the new unit level
  (`resolve_inventory_spec.rb`) as part of moving the logic there, which
  closes the gap as a side effect rather than requiring separate
  backfill work.
- Two top-level `RSpec.describe` blocks in one spec file
  (`inventories_spec.rb`) is a minor deviation from the single-`describe`
  shape every other spec file in this codebase uses — flagged for
  `styleguides-check`/review rather than assumed acceptable; the
  alternative (a second file, e.g. `inventories_refresh_spec.rb`) is a
  reasonable fallback if that turns out to be the preferred shape.

## Assumptions

- **TTL = 5 days.** Not derivable from code — a product judgment call.
  The user's own stated reference point was Steam inventory changes
  landing on the order of "at least once every few weeks, sometimes a
  case drop about once a week." 5 days is deliberately a bit shorter
  than that weekly cadence, so the TTL alone tends to self-heal before
  the next plausible real change even for a user who never uses the
  manual refresh endpoint — confirm this number feels right once it
  ships; it's a starting point, not a derived constant like the warmup
  cap/dedup numbers elsewhere in this codebase.
- **Refresh dedup TTL = 1 day** (one manual refresh per `steam_id` per
  day). Matches the "daily limit" framing already used when this was
  discussed; not tied to a Prop-configured rate limit the way the
  warmup cap is, since there's no equivalent per-minute Steam quota
  concern for a single user's manual, human-paced clicks — the daily cap
  exists to bound worst-case abuse (scripted repeated clicking), not
  normal use.
- No `app_core`/frontend button exists yet to call this endpoint from —
  out of scope here, assumed to be a separate future task.
- **`app/actions/steam/`, `Steam::` namespace, `self.call`, a per-action
  `Result` struct** are this plan's proposed shape for `app_fetcher`'s
  first action object, based on `app_core`'s existing convention and
  `steam-response-objects.md`'s scoping of `Steam::Response` to literal
  `Steam::Client` outputs only — not verified against a fetcher-specific
  styleguide, because none exists yet (see Action/Service Layer
  Follow-Up). `styleguides-check` owns confirming or revising this.

## Missing Styleguides

### `.claude/styleguides/fetcher/architecture-layers.md` + `.claude/adr/fetcher/layered-ingestion-pipeline.md` — **active conflict, not just a gap**

This isn't a missing-guidance case — a sufficient, directly applicable
ADR already exists and it says the opposite of what this plan's
Implementation Approach proposes.

`layered-ingestion-pipeline.md`'s Decision section, Scenario 1, states
explicitly (lines ~108-120):

> `Steam::Client`... is `app_fetcher`'s equivalent of a "service" layer
> for talking to an external system — **there is no `app/actions/` here;
> that's an `app_core`-specific name**... for its own
> request-orchestration layer, **not something this app has or needs**.

And `architecture-layers.md`'s own Scenario 1 diagram shows
`Api::V1::InventoriesController#show` calling `Steam::Client` and
`Steam::ItemParser` **directly**, citing
`inventories_controller.rb` itself as the Canonical Implementation of
that shape — with an explicit carve-out justifying why this is fine
(parsing is cheap/pure/safe to run inline; only persistence is deferred
to a worker).

This plan's Implementation Approach proposes exactly the thing the ADR's
own **Risks** section pre-emptively warns against:

> A future contributor could read `InventoriesController#show` calling
> `Steam::ItemParser` directly as drift/inconsistency and "fix" it by
> [adding an orchestration layer]... **This ADR is what should stop that
> "fix."**

Introducing `Steam::ResolveInventory` under a new `app/actions/steam/`
puts a class between the controller and `Steam::Client`/`Steam::ItemParser`
— which is precisely the layer this ADR says `app_fetcher` doesn't have
and doesn't need. Per CLAUDE.md's pipeline note ("if a stage surfaces a
contradiction with an earlier stage, stop and go back to that stage"),
this plan must not be finalized as-is.

**What this blocks**: the entire "New `Steam::ResolveInventory` action
object" subsection of Implementation Approach, and its downstream Files
To Create/Modify/Test Plan/Risks entries.

**What resolves it** — one of two paths, needing the user's explicit
choice (not something `styleguides-check` can silently pick, since both
are legitimate and the ADR was written this way deliberately):

1. **Drop the action-object extraction.** Go back to sharing the
   orchestration between `show` and `refresh` via a plain private
   controller method (this plan's own original shape, before the
   action-object revision) — zero new files, zero architecture change,
   fully compliant with the existing ADR as written today.
2. **Amend `layered-ingestion-pipeline.md` and
   `architecture-layers.md`.** The ADR's "no `app/actions/`, not
   something this app needs" conclusion was reached when every Scenario-1
   controller action had exactly one call site for its own logic. This
   plan's `refresh` action is the first case where the *same* Scenario-1
   orchestration must run from two call sites — arguably a materially
   different situation than what the ADR evaluated (compare: this is
   exactly the "does a second call site justify extraction" reasoning
   already used elsewhere in this project's own recent history, e.g. why
   `PriceUpdateWorker`'s invalidation call justified a dedicated
   `app/caching/` layer while `UserInventoryCache`'s single call site
   didn't justify one for `Steam::Client`). If the user wants to proceed
   with a real fetcher-side action layer, this needs a formal ADR
   amendment (or a new ADR that explicitly supersedes this part of the
   old one) plus new rules in `architecture-layers.md` — i.e. a
   `create-styleguide-from-scratch`-equivalent pass, with user sign-off,
   not a decision this plan or this check can make unilaterally.

### `.claude/styleguides/fetcher/caching.md` — insufficient for the planned `UserInventoryCache` shape

Independent of the conflict above. Already identified during
`create-dev-plan` (see the plan's own "Styleguide Follow-Up" note) and
confirmed here: the current Interface section mandates exactly
`.fetch_for`/`.invalidate` per caching class ("No other public methods");
`UserInventoryCache` needs three (`.read`/`.write`/`.invalidate`) for a
data-flow the current text doesn't cover. Must define:

- the vocabulary-of-primitives framing (`.fetch_for` vs `.read`/`.write`
  vs `.invalidate`, each with fixed meaning) instead of one mandatory
  two-method shape;
- the MUST NOT rule against exposing `.read`/`.write` alongside
  `.fetch_for` for the same resource;
- that TTL doubles as the only auto-refresh path (not a pure safety net)
  for a class with no scheduled writer, and should be sized against real
  data-change cadence accordingly;
- `UserInventoryCache` as a second Canonical Implementation.

This one does not need an ADR amendment — `caching.md` isn't contradicted
by this plan, just incomplete for it, matching a normal
`create-styleguide` update.

**Depends on** which path resolves the architecture-layers.md conflict
above (`.invalidate`'s caller changes from "the refresh action, via an
action object" to "the refresh action, inline in the controller" —
`caching.md`'s own content doesn't need to know which, but don't
finalize its wording using code examples that assume the losing path).

## Completion Criteria

- [x] Desired behavior made explicit (TTL change, `.invalidate`, refresh
  endpoint, including edge/failure cases).
- [x] Scope explicit (no scheduler; no `Steam::Client` move into the
  cache class; styleguide wording deferred to `styleguides-check`).
- [x] Affected files/components identified.
- [x] Test strategy defined.
- [x] Implementation steps ordered.
- [x] Verification defined.
- [ ] Plan checked against styleguides — **blocked**, see "Missing
  Styleguides" above: an active conflict with
  `.claude/adr/fetcher/layered-ingestion-pipeline.md`/
  `architecture-layers.md` needs a user decision before this can proceed,
  plus a normal `caching.md` Interface update.
- [ ] Implemented (`implement-plan` — pending).
