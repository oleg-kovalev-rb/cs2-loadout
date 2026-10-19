---
status: implemented
app: fetcher+core
goal: Close the remaining Steam-boundary test gaps and make the testing docs/fix_me match the current suite.
created: 2026-10-20
---

# Development Plan

## Goal

Add the missing unit coverage for `Steam::Client`, `Steam::Authenticator`,
`Steam::ProfileFetcher`, and `Steam::LoginUser`, extend the existing
session request spec to cover the login entry point, and remove stale
testing documentation that no longer describes the suite.

## Expected Behavior

### `Steam::Client` (`app_fetcher`)

- `fetch_item_price` returns a successful `Steam::Response` whose `data` is
  an `ItemPriceData` parsed from Steam's `success: true` JSON, and sends the
  request to `/market/priceoverview/` with `appid=730&currency=1` and the
  market hash name.
- `fetch_user_inventory` returns a successful response whose `data` is an
  `InventoryData`, and sends the request to
  `/inventory/<steam_id>/730/2?l=english&count=2000`.
- HTTP 200 with a falsy `success` field maps to status 404 / `"Not Found"`.
- HTTP 429 maps to status 429 / `"Rate Limit Exceeded"`.
- Any other non-200 HTTP status maps to that status / `"Steam API Error"`.
- A `Prop::RateLimited` raised by the real rate limiter maps to status 429
  with the configured retry-after value in the error message, and no HTTP
  request is made.
- Faraday transport errors and malformed JSON map to status 500 carrying the
  exception message rather than raising.

### `Steam::Authenticator` (`app_core`)

- `.auth_url(return_to, realm)` produces the Steam OpenID `checkid_setup`
  URL with the supplied return URL/realm and identifier-select claims.
- `.validate!` rejects an empty parameter hash with `Steam::AuthError`.
- `.validate!` POSTs `openid.mode=check_authentication` to Steam's OpenID
  endpoint, accepts a successful response containing `is_valid:true`, and
  extracts the numeric Steam ID from `openid.claimed_id`.
- A non-success HTTP response or a body without `is_valid:true` raises
  `Steam::AuthError`.
- A missing/malformed claimed ID raises `Steam::AuthError`.
- Network timeout errors are re-raised as `Steam::AuthError`.

### `Steam::ProfileFetcher` (`app_core`)

- Returns `nil` without making an HTTP call when `STEAM_WEB_API_KEY` is
  blank.
- Returns `{ nickname:, avatar_url: }` for a successful Steam player
  summary response, and sends the API key and Steam ID as query params.
- Returns `nil` for a non-success HTTP response, a response without a
  player, malformed JSON, or a network timeout.

### `Steam::LoginUser` (`app_core`)

- On a valid Steam OpenID callback with a successful profile lookup, creates
  a `User` with the Steam ID, nickname, and avatar.
- On a repeat login, updates the existing user's nickname/avatar instead of
  creating a second user.
- When the profile API is unavailable/blank, still creates/updates the user
  from the Steam ID alone (profile fields left untouched).
- A failed Steam validation propagates `Steam::AuthError` and persists no
  user.

### Session request boundary (`app_core`)

- `POST /session` redirects to Steam's OpenID URL with a `checkid_setup`
  request whose `return_to` is the callback URL and whose realm is the root
  URL.
- The existing callback success/failure and logout flash behavior remains
  unchanged.

### Documentation

- Testing docs and `agent/styleguides/fix_me.md` describe the suite as it
  actually is today (VCR/FactoryBot present, request specs existing, no
  reference to removed files or already-fixed deviations).

## Scope

### In Scope

- New unit specs for the four Steam classes named above.
- Additional examples in the existing `app_core/spec/requests/sessions_spec.rb`.
- Updating stale testing documentation and `fix_me.md` entries touched by
  this work.
- Any small production-code adjustment strictly required to make the
  specified behavior testable (e.g. none is anticipated).

### Out of Scope

- New system specs, browser drivers, or a login-flow Capybara journey. The
  user explicitly accepts the current absence of system specs; the request
  spec plus unit specs cover the login contract without a browser.
- Adding VCR to `app_core` only to re-test Steam OpenID via a hand-crafted
  cassette.
- Refactoring `Steam::Client`, `Steam::Authenticator`, `ProfileFetcher`, or
  `LoginUser` production behavior.
- Fixing unrelated `fix_me.md` deviations (Sorbet sigils on
  `authenticator.rb`/controllers) beyond keeping the file accurate.
- Filling unrelated coverage gaps in other classes.

## Implementation Approach

Follow `agent/styleguides/rspec-conventions.md`:

- Unit specs live at the mirrored path with no `type:` metadata and stub the
  real outbound host with WebMock.
- Exercise real collaborators inside each unit (no stubbing of
  `Steam::Client`/`Steam::Authenticator`); the login action spec lets the
  real authenticator and profile fetcher run against WebMock.
- Use `let`/`before` + a named `subject` where the example has persisted
  data or a stateful action, and an explicit `aggregate_failures` block once
  an example has more than three expectations.
- `app_core` request specs keep `type: :request`; the login entry-point
  example only asserts the redirect contract, so no cassette is needed.

For `Steam::Client` rate-limit coverage, drive the real `Prop` limiter:
temporarily lower the relevant configured threshold, make one allowed call,
then assert the next call returns the 429 response without a second HTTP
request. Restore the original `Prop` configuration after the example.

## Applicable Styleguides

- `agent/styleguides/rspec-conventions.md` — governs spec level/path,
  explicit `type:` on request specs, WebMock-vs-VCR usage, FactoryBot test
  data, `let`/`before`/named `subject` structure, and
  `aggregate_failures`. Its stale canonical-implementation references are
  corrected as part of this plan; its rules themselves are sufficient.
- `agent/styleguides/ruby-sorbet.md` — confirms new spec files get no Sorbet
  sigil, and bounds production-code typing work (none expected here).
- `agent/styleguides/rails-layering.md` — confirms specs must exercise the
  existing Controller → Action → lib/`Steam` → Model split without moving
  logic across layers.
- `agent/styleguides/core/architecture-layers.md` — places
  `Steam::LoginUser` in `app/actions/steam/` and the external I/O in
  `lib/steam/`, which the new specs mirror.
- `agent/styleguides/fetcher/steam-response-objects.md` — constrains the
  `Steam::Client` spec's expected `Steam::Response`/DTO contract and is one
  of the docs whose stale `response.data` claim is corrected.
- `agent/styleguides/fix_me.md` — its process rules decide which entries may
  be removed during the documentation audit.

## Files To Modify

- `app_core/spec/requests/sessions_spec.rb` — add a `POST /session`
  redirect-contract example; keep existing callback/logout examples.
- `app_fetcher/lib/steam/README.md` — replace the "no dedicated unit spec"
  testing note with the new `client_spec.rb` coverage.
- `agent/styleguides/rspec-conventions.md` — refresh canonical
  implementations/status text: `price_histories_spec.rb` no longer exists,
  `app_core` now has request specs and factories, VCR cassettes exist in
  `app_fetcher`, and the old controller-spec deviation is gone.
- `agent/styleguides/fetcher/steam-response-objects.md` — remove the stale
  claim that `UserInventorySyncService` performs "four separate
  `response.data` reads" if the code no longer does so; point at the actual
  current deviation state.
- `agent/styleguides/fix_me.md` — delete entries that are no longer true
  (at minimum the `app_fetcher/bin/ci` LoadError, the resolved
  `connection_pool` workaround if it is now the sanctioned exception, and
  the `users.yml` fixture entry if nothing references it); keep the genuine
  remaining deviations.

## Files To Create

- `app_fetcher/spec/lib/steam/client_spec.rb` — exhaustive unit coverage of
  the client's success, not-found, rate-limit, HTTP-error, transport-error,
  and parse-error paths plus endpoint/query contracts.
- `app_core/spec/lib/steam/authenticator_spec.rb` — OpenID URL construction,
  validation success/failure, claimed-ID extraction, and network errors.
- `app_core/spec/lib/steam/profile_fetcher_spec.rb` — missing-key, success,
  and all nil-returning failure paths.
- `app_core/spec/actions/steam/login_user_spec.rb` — create/update/no-profile
  behavior and auth-error propagation against WebMock-stubbed Steam
  endpoints.

## Test Plan

### `app_fetcher/spec/lib/steam/client_spec.rb`

1. `#fetch_item_price` success: status 200, `data` fields, request URL/query.
2. `#fetch_user_inventory` success: status 200, `data` assets/descriptions,
   request path/query.
3. 200 + `success: false` → 404 `"Not Found"`.
4. HTTP 429 → 429 `"Rate Limit Exceeded"`.
5. HTTP 500 → 500 `"Steam API Error"`.
6. Real `Prop` limit exceeded → 429 with retry-after text, no HTTP call.
7. Faraday timeout → 500 with the exception message.
8. Malformed JSON body → 500 with the parse-error message.

### `app_core/spec/lib/steam/authenticator_spec.rb`

1. `.auth_url` query contract.
2. Valid validation response extracts the Steam ID and posts
   `check_authentication`.
3. Empty payload raises `AuthError`.
4. `is_valid:false`/non-success HTTP raises `AuthError`.
5. Missing or malformed claimed ID raises `AuthError`.
6. `Net::OpenTimeout` is wrapped in `AuthError`.

### `app_core/spec/lib/steam/profile_fetcher_spec.rb`

1. Blank API key returns `nil` and makes no request.
2. Successful summary returns nickname/avatar and sends the expected query.
3. Non-success HTTP, empty players, malformed JSON, and timeout each return
   `nil`.

### `app_core/spec/actions/steam/login_user_spec.rb`

1. New Steam user is persisted with profile data (real authenticator +
   profile fetcher through WebMock).
2. Existing Steam user is updated, not duplicated.
3. Profile unavailable (blank key) still persists the user.
4. Invalid Steam validation raises and creates no user.

### `app_core/spec/requests/sessions_spec.rb`

1. New: `POST /session` redirects to Steam OpenID with `checkid_setup`,
   callback return URL, and root realm.
2. Existing callback success, callback failure, and logout examples continue
   to pass.

## Implementation Steps

1. Create `app_fetcher/spec/lib/steam/client_spec.rb` using WebMock for every
   endpoint/status branch and the real `Prop` limiter for the 429 path.
2. Run the new client spec inside the `app_fetcher` test container and fix
   only the spec (or a genuinely required client test seam) until green.
3. Create `app_core/spec/lib/steam/authenticator_spec.rb` with WebMock
   stubs for the OpenID POST.
4. Create `app_core/spec/lib/steam/profile_fetcher_spec.rb` with an ENV stub
   for `STEAM_WEB_API_KEY` and WebMock stubs for the summary endpoint.
5. Create `app_core/spec/actions/steam/login_user_spec.rb` using WebMock for
   both external calls (no class-level stubbing of the Steam collaborators).
6. Extend `app_core/spec/requests/sessions_spec.rb` with the `POST /session`
   redirect-contract example.
7. Run the `app_core` unit/request specs and fix spec-only issues.
8. Update the testing docs (`README.md`, `rspec-conventions.md`,
   `steam-response-objects.md`) to match the final suite.
9. Audit `fix_me.md` for entries that are now false and remove only those.
10. Run both full RSpec suites plus RuboCop on the touched Ruby files.

## Verification

- `app_fetcher`: `bundle exec rspec spec/lib/steam/client_spec.rb`, then the
  full `bundle exec rspec` suite.
- `app_core`: `bundle exec rspec spec/lib/steam spec/actions/steam
  spec/requests/sessions_spec.rb`, then the full `bundle exec rspec` suite.
- RuboCop on every new/modified Ruby file in both apps.
- Confirm no network access is attempted in the new unit specs (WebMock
  blocks it by default).
- Re-read the updated docs to confirm every referenced spec path exists and
  every `fix_me.md` entry still applies.

## Risks

- `Prop` configuration is global; the rate-limit example must restore the
  original threshold to avoid leaking into later examples.
- `app_fetcher`'s test environment uses `solid_cache_store`; the real
  limiter depends on `Rails.cache` supporting `increment`. Existing
  `rails_helper` clears the cache before each example, but the limiter
  example still needs a stable threshold reset.
- `Steam::ProfileFetcher` reads `ENV` directly; stubbing `ENV.fetch` must be
  scoped narrowly so Rails/test setup is unaffected.
- `Steam::Authenticator` has no Sorbet sigil (already logged in `fix_me.md`);
  the new spec does not require changing that, and doing so would expand
  scope into unrelated type work.
- `Steam::LoginUser`'s spec intentionally runs the real authenticator and
  profile fetcher. If a future refactor changes their internal HTTP calls,
  this spec will need the same WebMock updates; that is the desired
  boundary-level coupling, not an accident.
- `app_core` has no VCR setup; adding a login request/system flow that calls
  Steam would require new test infrastructure. It is deliberately deferred.

## Assumptions

- The user accepts the current absence of system specs, so no Capybara
  login journey is added.
- `agent/styleguides/fix_me.md` should be made accurate rather than
  rewritten; only demonstrably stale lines are removed.
- `Steam::Client`'s current production behavior is correct and only needs
  tests, not redesign.

## Completion Criteria

- All four new spec files exist and pass.
- The session request spec covers the login entry point without weakening
  the existing callback/logout coverage.
- Both full RSpec suites pass.
- RuboCop passes on the changed Ruby files.
- Testing docs and `fix_me.md` no longer reference removed specs or
  already-resolved deviations.

# Implementation Summary

## Implemented

- Added `app_fetcher/spec/lib/steam/client_spec.rb`: success, not-found,
  HTTP 429, other-status, real `Prop` rate-limit, transport-error, and
  malformed-JSON branches for both client endpoints, with URL/query
  assertions.
- Added `app_core/spec/lib/steam/authenticator_spec.rb`: OpenID URL
  construction, successful validation/Steam-ID extraction, empty payload,
  rejected assertion, non-success HTTP, missing/malformed claimed ID, and
  timeout handling.
- Added `app_core/spec/lib/steam/profile_fetcher_spec.rb`: blank key,
  successful profile, non-success HTTP, empty players, malformed JSON, and
  timeout.
- Added `app_core/spec/actions/steam/login_user_spec.rb`: new user,
  repeat-login update, missing profile, and rejected authentication, with
  the real authenticator/profile fetcher exercised through WebMock.
- Extended `app_core/spec/requests/sessions_spec.rb` with the
  `POST /session` Steam OpenID redirect contract.
- Removed the unused `app_core/spec/fixtures/users.yml` fixture and its
  stale `fix_me.md` entry.
- Refreshed `app_fetcher/lib/steam/README.md`,
  `agent/styleguides/rspec-conventions.md`, and
  `agent/styleguides/fetcher/steam-response-objects.md`; removed resolved
  `fix_me.md` entries; added a current-suite note to the RSpec strategy ADR.

## Tests

Executed inside the compose CI override (with a local override only to drop
published ports, since another worktree already owned 3001/6380):

- `docker compose ... run --rm app_fetcher bundle exec rspec` — 483
  examples, 0 failures.
- `docker compose ... run --rm app_core bundle exec rspec` — 74 examples,
  0 failures.
- `docker compose ... run --rm app_fetcher bundle exec rspec
  spec/lib/steam/client_spec.rb` — 9 examples, 0 failures.
- `docker compose ... run --rm app_core bundle exec rspec spec/lib/steam
  spec/actions/steam spec/requests/sessions_spec.rb` — 26 examples, 0
  failures.

## Verification

- `bundle exec rubocop` on all new/changed Ruby files: 1 file in
  `app_fetcher`, 4 files in `app_core`, no offenses.
- `bundle exec srb tc` in both apps: no errors.
- Final diff reviewed: only the planned specs plus documentation/fixture
  cleanup changed.

## Deviations

- Deleted `app_core/spec/fixtures/users.yml` instead of only removing its
  `fix_me.md` entry. It was unreferenced, and its globally loaded row
  collided with the new login specs' Steam ID.
- Added a short "Current suite note" to
  `agent/adr/fetcher/rspec-testing-strategy.md` rather than rewriting its
  historical Context/Consequences.
- No system spec was added; the plan scoped it out per the request.

## Remaining Issues

- The RSpec strategy ADR still contains historical references in its
  Context/Consequences; the new note explains that they describe the
  decision-time state.
- `Steam::Authenticator` still lacks a Sorbet sigil and the two `app_core`
  controllers still use lower sigils; those remain in `fix_me.md` as
  unrelated deviations.
- No browser-level login/system spec exists yet.
