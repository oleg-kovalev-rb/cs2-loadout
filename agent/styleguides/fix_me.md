# Style Deviations

Files that deviate from an established convention or styleguide rule,
found while writing/updating a styleguide, doing research, or
implementing a plan.

This is not a task backlog and not a place to design a fix. It exists so:

- a deviation found while extracting a styleguide doesn't get silently
  folded in as an "alternative" convention, or fixed on the spot (out of
  scope for `create-styleguide`/`create-styleguide-from-scratch`);
- anyone who later touches one of these files already knows it's
  non-conforming, instead of re-deriving that from scratch.

Format: one line per file —

```
- <path> — <which rule/convention it deviates from, in one line>
```

Group entries under the scope they belong to (mirrors
`agent/styleguides/` itself). Once a file is brought into compliance,
delete its entry — don't leave a stale line behind.

`implement-plan` checks this file for any file it's about to touch: if the
fix is small and within the styleguide already being followed for that
change, fix it as part of that change and remove the entry. Don't expand
a change's scope just because an unrelated file is flagged here.

---

## Shared

(none yet)

## `app_fetcher`

- `app_fetcher/app/parsers/item_parser.rb` (current flat path — not
  `app/parsers/steam/`, see the `architecture-layers.md`/`ruby-sorbet.md`
  entries below) — `.parse`'s `else` branch (no `WEAPON_TYPE_SEPARATOR` in
  the name) returns `item_name: clean_name`, which Sorbet infers as
  `T.nilable(String)` even though `String#gsub` never returns `nil` —
  confirmed as a real, pre-existing `srb tc` error (`7005`, result-type
  mismatch against `ItemDto`'s `item_name: String`) that predates the
  `icon_url` key added to `ItemDto` for item-icon support (and now also the
  `marketable`/`tradable`/`rarity` keys added for marketability/rarity
  metadata support); discovered while adding `icon_url`, not introduced by
  it, and not introduced by the later keys either — the mismatch is solely
  about `item_name`'s inferred type, unrelated to how many sibling keys
  exist alongside it. Root cause (why Sorbet widens `clean_name`'s type
  across the two `gsub` reassignments) wasn't investigated — out of scope
  for either change.
- `app_fetcher/app/schedulers/inventory_value_scheduler.rb` —
  `sidekiq_options` has no `retry:`, unlike both workers
  (`PriceUpdateWorker: retry: 5`, `InventoryValueUpdateWorker: retry: 3`), so
  it silently falls back to Sidekiq's default of 25 retries over ~3
  weeks. Not confirmed by a tool the way the two entries above are (this
  is a Sidekiq runtime default, not a static check) — judgment call based
  on the other two jobs always setting it explicitly. New schedulers
  (e.g. `UserInventorySyncScheduler`) set an explicit `retry:` per this
  reading; `price_scheduler.rb` was fixed the same way
  (`retry: 3`, matching `UserInventorySyncScheduler`'s precedent) when the
  "Skip fetching non-marketable items" change touched it anyway —
  `inventory_value_scheduler.rb` wasn't touched by that change and still
  needs it. See `agent/styleguides/fetcher/background-jobs.md`.
- `app_fetcher/app/controllers/api/v1/item_prices_controller.rb` —
  `#dynamics` guards `next if item.current_price_cents.nil?` (line 22) but
  then re-reads `item.current_price_cents` as a fresh method call at line
  25 (`base = item.current_price_cents - change`); Sorbet can't carry a
  `nil?`-guard's narrowing across two separate calls to the same method
  (only a local-variable narrowing persists), so this is a real `srb tc`
  error (`7003`, `-` on `NilClass` component of `T.nilable(Integer)`).
  Newly *surfaced*, not introduced, by the "Skip fetching non-marketable
  items" change: before that change, `Item#current_price_cents` itself
  wasn't resolvable at all under `srb tc` (no DSL RBI had ever been
  generated for `Item`, so every call on it was silently invisible to the
  typechecker, column attributes included), which masked this mismatch
  entirely. Fix is to capture `item.current_price_cents` in a local
  before the guard so the narrowing holds; out of scope for a scheduler/
  model change that doesn't touch this controller.
- `app_fetcher/app/workers/price_update_worker.rb` — `#perform` calls
  `publish_to_stream(item.market_hash_name, item.current_price_cents,
  item.change_24h_cents)` (line 24), but `publish_to_stream`'s `sig`
  declares `price:`/`change_24h:` as non-nilable `Integer` while both
  `current_price_cents`/`change_24h_cents` are genuinely `T.nilable(
  Integer)` columns — a real `srb tc` error (`7002`, nilable argument
  mismatch), same "newly surfaced, not introduced" cause as the entry
  above. Fixing this means deciding whether `publish_to_stream` should
  accept nilable values (and what the stream payload should contain for a
  not-yet-priced item) or whether `#perform` should guard before
  publishing — a real product decision, not a one-line type fix; out of
  scope for this change.
- `app_fetcher/app/models/item.rb` had a latent runtime bug in
  `#stattrak` (`super.nil? ? false : super`): calling it on an item
  loaded via a relation query (not a freshly-`.create!`d instance) with
  no `"stattrak"` key in `metadata` raised `TypeError: Return value:
  Expected type T::Boolean, got type String with value "stattrak"` at
  the `sig`-wrapped boundary — root cause traced to
  `ActiveRecord::Store`'s generated reader (`super_method.call`)
  returning the attribute's own key name instead of `nil`/the stored
  value in that specific case; reproducible with zero controller code
  involved (`Item.all.to_a[0].stattrak`). **Fixed** as part of
  admin-panel-backend-foundation (not left as a fix_me entry) since the
  new `Api::Admin::ItemsController#index`/`#show` genuinely needed
  `Item.all`/`Item.find_by` + `.stattrak` to work; replaced with a direct
  `!!metadata["stattrak"]` read that doesn't go through the buggy `super`
  path. `Api::Public::ItemsController#item_json` (which also calls
  `.stattrak`) benefits from the same fix as a side effect; its own spec
  coincidentally never exercised the triggering combination (2+ items in
  one query, missing `"stattrak"` key) so it never surfaced there.
- `app_fetcher/spec/fixtures/items.yml`, `price_logs.yml` — Rails
  fixtures; `agent/styleguides/rspec-conventions.md` now standardizes
  on `FactoryBot` for test data. Existing rows (`redline`,
  `redline_recent`, etc.) stay loaded and referenced by their current
  specs; don't add new fixture rows here — use a factory instead. See
  `agent/adr/fetcher/rspec-testing-strategy.md`.
- `app_fetcher/app/services/user_inventory_sync_service.rb` — `#call`
  reads `response.data.more_items`/`.market_hash_names` (and, since
  item-icon support, `.icon_urls_by_name`; since marketability/rarity
  support, `.item_attributes_by_name`) after only checking
  `response.success?`, not narrowing `response.data` itself; Sorbet can't
  infer that a `200` status implies a non-nil `data` on
  `Steam::Response`, so all four calls are real `srb tc` errors (`7003`,
  method on `NilClass` component of `T.nilable(...)`) that autocorrect
  would wrap in `T.must(response.data)`. The first two predate item-icon
  support; the third (`icon_urls_by_name`) and fourth
  (`item_attributes_by_name`) were each added alongside their respective
  feature, matching the file's existing (unfixed) pattern rather than
  fixing only the new call site each time. Fixing this properly means
  either restructuring `Steam::Response` so success implies non-nil data,
  or widening every call site here — both out of scope for either
  small-field addition.
- `app_fetcher/spec/requests/api/v1/inventories_spec.rb`,
  `price_histories_spec.rb` — `inventories_spec.rb` hand-writes a
  `WebMock` `stub_request` body for a Steam API call at the request
  level; `rspec-conventions.md` now requires a VCR cassette at that
  level (unit specs keep using `WebMock` directly). Not migrated here;
  migrate the next time either file is otherwise touched.

## `app_core`

- `app_core/lib/steam/authenticator.rb` — missing a Sorbet `# typed:`
  sigil entirely; every sibling in `lib/steam/` (`bridge_token.rb`,
  `profile_fetcher.rb`) is `typed: strict`.
- `app_core/app/controllers/application_controller.rb` — no Sorbet sigil
  at all.
- `app_core/app/controllers/sessions_controller.rb` — `typed: true`
  instead of `typed: strict`.
  Both are real, hand-written controllers with actual logic, not
  boilerplate — `app_fetcher`'s controllers prove `strict` works fine on
  controllers, so this isn't a justified exception, just drift. See
  `agent/styleguides/ruby-sorbet.md`.
- `app_core/spec/fixtures/users.yml` — Rails fixture; same deviation and
  same rationale as the `app_fetcher` fixtures entry above. Existing
  `users(:one)` reference stays as-is; new scenarios use a `FactoryBot`
  factory instead.
- `app_core/app/views/layouts/application.html.erb` never renders
  `flash` — `SessionsController#callback`/`#destroy` set
  `notice:`/`alert:` on their `redirect_to` calls, but nothing in the
  layout (or any view) outputs `flash[:notice]`/`flash[:alert]`, so those
  messages are silently dropped today. Confirmed while amending
  `agent/styleguides/core/admin-authentication.md` for the
  admin-panel-frontend plan's format-aware login flow — that plan's own
  login-failure error is passed as an explicit `@error` local instead of
  `flash`, specifically to avoid building a new feature on top of this
  gap. Not fixed here since `application.html.erb` isn't otherwise
  touched by that work.
