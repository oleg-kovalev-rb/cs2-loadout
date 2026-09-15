# `Steam::` — Steam API client

Everything under `app_fetcher/lib/steam/` talks to Steam's public HTTP
endpoints on behalf of the rest of `app_fetcher`. Nothing outside this
directory (workers, controllers) makes an HTTP call to Steam directly —
they all go through `Steam::Client`.

## Components

- **`client.rb` — `Steam::Client`.** One public method per Steam endpoint
  currently in use:
  - `fetch_item_price(market_hash_name)` — Steam Community Market price
    overview for a single item.
  - `fetch_user_inventory(steam_id)` — a user's CS2 (`appid` `730`)
    inventory.

  Both delegate to the single private `perform_request`, which applies
  rate limiting, makes the HTTP call, and maps the result into a
  `Steam::Response`.

- **`response.rb` — `Steam::Response[DataClass]`.** A generic result
  struct (`status`, `data`, `error`, `success?`) returned by every
  `Steam::Client` method. See
  `.claude/styleguides/fetcher/steam-response-objects.md` for the rules
  around this type and the DTOs that plug into it.

- **`response/data/item_price_data.rb`, `response/data/inventory_data.rb`**
  — the two DTOs (`Steam::Response::Data::ItemPriceData`,
  `Steam::Response::Data::InventoryData`) that `Response#data` holds for
  each endpoint. Namespaced under `Response::Data` since they only exist
  to be its payload.

- **`../faraday/user_agent_rotator.rb` — `Faraday::UserAgentRotator`.** A
  Faraday request middleware that picks a random User-Agent string from a
  fixed pool for every outbound request. This exists to reduce the chance
  of Steam's endpoint rate-limiting or blocking requests based on a
  single, fixed User-Agent fingerprint — it's a complement to the
  explicit request-count throttling below, not a replacement for it.

## Request flow

```text
Client#fetch_item_price / #fetch_user_inventory
    ↓
Client#perform_request
    ↓ Prop.throttle!(:"#{limit_key}_rpm", "global")
    ↓ Prop.throttle!(:"#{limit_key}_rpd", "global")
    ↓ Faraday GET, through UserAgentRotator middleware
    ↓ map HTTP status + JSON body →
Steam::Response[DtoClass]  (DtoClass.from_hash on success)
```

## Rate limits

Configured centrally in `config/initializers/prop.rb`, backed by
`Rails.cache`. Each endpoint has its own two-tier budget:

| `limit_key`         | per minute | per day |
|----------------------|-----------:|--------:|
| `steam_price`         | 20         | 1000    |
| `steam_inventory`      | 20         | 1000    |

Adding a new `Steam::Client` method means adding a new `limit_key` here
too — see the ADR below for why this is centralized instead of handled by
each caller.

## Error handling

`perform_request` never raises for an expected failure — it always
returns a `Steam::Response` with `success?` false:

| Condition                                   | `status` | `error`                                  |
|----------------------------------------------|---------:|-------------------------------------------|
| HTTP 200, body `success` is falsy             | 404      | `"Not Found"`                              |
| HTTP 429, or caught `Prop::RateLimited`       | 429      | `"Rate Limit Exceeded"` (+ `retry_after` if caught from Prop) |
| Any other non-200 status                      | (status) | `"Steam API Error"`                        |
| `Faraday::Error` / `JSON::ParserError`        | 500      | exception message                          |

Callers branch on `response.success?`; on failure they either log and
move on (`PriceUpdateWorker`) or surface `response.error` to their own
caller (`InventoriesController`).

## Testing

There's no dedicated unit spec for `Steam::Client`/`Steam::Response`
today. Coverage is indirect, through the request specs in
`spec/requests/api/v1/` (e.g. `inventories_spec.rb`), which stub the real
Steam endpoint with WebMock and assert on the controller's JSON response.

## See also

- `.claude/adr/fetcher/steam-client-response-objects-and-rate-limiting.md` — why rate limiting
  is centralized in the client and why failures are result objects
  instead of exceptions.
- `.claude/styleguides/fetcher/steam-response-objects.md` — rules for
  `Steam::Response` and its DTOs.
