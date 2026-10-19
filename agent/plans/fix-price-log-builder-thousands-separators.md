---
status: implemented
app: fetcher
goal: Parse Steam price strings with thousands separators correctly and integer-only, instead of truncating through a float regex match
created: 2026-10-19
---

# Development Plan

## Goal

Make `PriceLogBuilder.to_cents` convert Steam price strings with
thousands separators (US `"$1,234.56"` and European `"1.234,56€"`), and
plain integer amounts (`"$1,234"`), to the correct number of cents.
Perform the conversion with integer arithmetic rather than `to_f`, so no
precision is lost.

## Expected Behavior

For `PriceLogBuilder.build` / its private `to_cents`:

- `"$38.45"` → `3845` (unchanged).
- `"$39,00"` → `3900` (unchanged; comma as decimal separator).
- `"$1,234.56"` → `123456` (comma is thousands, dot is decimal).
- `"1.234,56€"` → `123456` (dot is thousands, comma is decimal).
- `"$1,234"` → `123400` (integer amount with a thousands separator).
- `"$1234"` → `123400` (plain integer amount).
- `"$1,234,567.89"` → `123456789` (multiple thousands groups).
- `"1 234,56€"` / narrow/no-break-space thousands → `123456` (Steam
  uses locale-specific spaces; strip them before parsing).
- `nil`, `""` → `0` (unchanged).
- A string with no digits → `0` (unchanged failure behavior).
- Three digits after a single separator are treated as a thousands
  group (`"$1.234"` → `123400`), because Steam prices carry at most two
  decimal places; a one- or two-digit fraction is a decimal fraction
  (`"$39,0"` → `3900`, `"$39,00"` → `3900`).
- More than two decimal digits are rounded to the nearest cent using
  integer arithmetic (no floats).

Behavior that must remain unchanged: `volume` parsing, item_id
assignment, the DTO contract, and the nil/empty guard clauses.

## Applicable Styleguides

- `agent/styleguides/ruby-sorbet.md` — constrains the production change:
  constants wrapped in `T.let`, every helper typed with `sig`, private
  class methods inside `class << self` (not `private_class_method`), and
  guard clauses for nil/empty input.
- `agent/styleguides/rspec-conventions.md` — constrains the spec change:
  unit-level builder spec under the mirrored path, no Sorbet sigil, real
  in-memory DTOs (no stubs), and example granularity (one example per
  scenario, `aggregate_failures` for >3 expectations).
- `agent/styleguides/fetcher/architecture-layers.md` — keeps the
  conversion inside the existing builder (no persistence/external I/O),
  with the builder continuing to depend only on the model it
  instantiates.
- `agent/styleguides/rails-layering.md` — preserves the one-directional
  Controller → orchestration → Models dependency direction; no new layer
  is introduced.

## Scope

### In Scope

- Replace the current regex + `to_f` conversion in `PriceLogBuilder`.
- Add unit examples covering thousands separators, both separator
  conventions, integer amounts, and multi-group separators.
- Add unit examples for the no-digit and rounding/edge cases the new
  parser introduces.

### Out of Scope

- Changing the Steam API `currency` parameter or adding multi-currency
  support.
- Changing how prices are stored/serialized or displayed.
- Refactoring `parse_volume` or the builder's public interface.
- Reworking `PriceLog` validations or callers.

## Implementation Approach

Keep the single `PriceLogBuilder` class and its private `to_cents`
method. Extract the numeric token from the price string with a regex
that includes digits, `.`, `,`, and whitespace; strip whitespace; then
split the token deterministically:

1. Find the last `.` or `,` in the token.
2. If both separator characters occur, the rightmost one is the decimal
   separator and the other is a thousands separator.
3. If only one separator character occurs:
   - if it repeats, all occurrences are thousands separators;
   - if it occurs once with exactly three digits after it, it is a
     thousands separator;
   - otherwise it is the decimal separator.
4. Remove thousands separators from the integer part, convert it with
   `Integer#to_i`, multiply by 100, and add the fraction converted to
   cents (padded/rounded with integer arithmetic).

All helpers stay private class methods with Sorbet `sig`s, per the
existing builder style. Constants remain wrapped in `T.let`.

## Files To Modify

- `app_fetcher/app/builders/price_log_builder.rb`
  - Replace `PRICE_REGEXP` with a token regex plus numeric-splitting
    helpers.
  - Keep `to_cents` as the only public entry point (via `build`).
  - Reason: the current regex stops at the first separator and `to_f`
    loses the true magnitude.
- `app_fetcher/spec/builders/price_log_builder_spec.rb`
  - Add examples for the cases listed in Expected Behavior.
  - Reason: existing coverage only has `"$38.45"` and `"$39,00"`, so
    the bug is invisible.

## Files To Create

None.

## Test Plan

Unit spec (`spec/builders/price_log_builder_spec.rb`), constructing
`ItemPriceData` directly (no I/O/stubs needed):

- US thousands + decimal: `"$1,234.56"` → `123456`.
- EU thousands + decimal: `"1.234,56€"` → `123456`.
- Integer with thousands separator: `"$1,234"` → `123400`.
- Plain integer: `"$1234"` → `123400`.
- Multiple thousands groups: `"$1,234,567.89"` → `123456789`.
- Space thousands separator: `"1 234,56€"` → `123456`.
- No digits: e.g. `"N/A"` → `0`.
- Existing populated/nil/empty examples remain green.
- Use a compact table-driven example (one `it` per scenario group via a
  loop over `[input, expected]`) if it keeps the spec readable; each
  expectation about the same conversion belongs in the same example.

## Implementation Steps

1. Add failing unit examples to
   `app_fetcher/spec/builders/price_log_builder_spec.rb` for the
   thousand-separator, both-convention, integer, multi-group,
   space-separator, no-digit, and rounding cases.
2. Run the builder spec to confirm the new examples fail for the right
   reason.
3. Rewrite `PriceLogBuilder`'s private conversion:
   - numeric-token extraction incl. whitespace separators;
   - decimal/thousands split helpers;
   - integer-only cents calculation with rounding.
4. Run the builder spec until green.
5. Run the broader `app_fetcher` spec suite and linters/typecheck.

## Verification

From `app_fetcher/` (Docker-compose based, matching `bin/ci`):

- `bundle exec rspec spec/builders/price_log_builder_spec.rb`
- `bundle exec rspec spec/services/price_update_service_spec.rb spec/workers/price_update_worker_spec.rb`
- `bundle exec rspec` (full app_fetcher suite)
- `bundle exec rubocop app/builders/price_log_builder.rb spec/builders/price_log_builder_spec.rb`
- `bundle exec srb tc`
- Prettier/ESLint are unaffected (Ruby-only change).

## Risks

- Separator ambiguity for a single separator followed by three digits
  (`"1.234"`): treated as a thousands group by design. Steam's USD
  responses always use two decimal digits, so this is the safer choice.
- Currency strings with a leading/trailing symbol are handled by token
  extraction; a string containing unrelated digits later in the text
  would still pick the first numeric token, as before.
- Space separators require stripping ordinary, non-breaking, and
  narrow no-break spaces; the regex/`gsub` must cover all three.

## Assumptions

- Steam continues to return at most two decimal digits for the
  configured USD currency; the three-digit rule above is therefore
  unambiguous in practice.
- `currency: 1` (USD) stays fixed for now; European parsing support is
  defensive for future locale changes and for legacy/market strings.

## Completion Criteria

- New spec examples fail on the old implementation and pass on the new
  one.
- All price formats above convert to the stated cents values.
- No float arithmetic is used for price conversion.
- Builder, service, and worker specs pass; RuboCop and `srb tc` pass.

# Implementation Summary

## Implemented

- `app_fetcher/app/builders/price_log_builder.rb`
  - Replaced the single-number `PRICE_REGEXP` + `to_f` conversion with
    integer-only parsing that extracts the full numeric token (digits,
    `.`, `,`, ordinary/non-breaking/narrow spaces).
  - Added private helpers `split_price`, `decimal_separator?`, and
    `fraction_to_cents`:
    - the rightmost separator is decimal when both separator characters
      are present;
    - repeated separators are thousands groups;
    - a single separator followed by exactly three digits is a thousands
      group, otherwise it is decimal;
    - cents are computed with `Integer#to_i`/integer division, with
      half-up rounding for more than two fractional digits.
- `app_fetcher/spec/builders/price_log_builder_spec.rb`
  - Added regression examples for US/EU thousands separators, multiple
    groups, whole-currency amounts, plain integers, space/non-breaking
    space separators, fractional-cent rounding, and no-digit input.

## Tests

Executed inside the `app_fetcher` container (mounted worktree,
`RAILS_ENV=test`, `steam_project_default` network):

- `bundle exec rspec spec/builders/price_log_builder_spec.rb`
- `bundle exec rspec spec/builders/price_log_builder_spec.rb spec/services/price_update_service_spec.rb spec/workers/price_update_worker_spec.rb`
- `bundle exec rspec` (396 examples)
- `bundle exec rubocop app/builders/price_log_builder.rb spec/builders/price_log_builder_spec.rb`
- `bundle exec srb tc`

## Verification

- Builder spec: 10 examples, 0 failures.
- Builder + service + worker specs: 19 examples, 0 failures.
- Full `app_fetcher` suite: 396 examples, 0 failures.
- RuboCop: no offenses.
- Sorbet: no errors.

## Deviations

None.

## Remaining Issues

- `parse_volume` still only strips commas (`"1.234"` would parse as `1`),
  which is outside this plan's price-focused scope. USD Steam responses
  use comma thousands separators, so current data is unaffected; revisit
  if the volume parser is ever expected to accept EU-formatted values.

