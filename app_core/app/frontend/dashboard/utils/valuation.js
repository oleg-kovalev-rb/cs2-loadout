// Pure derived-data helpers for the portfolio hero's "estimating" state.
//
// An inventory is "fully priced" once none of its `marketable` items is
// still missing a price. `non-marketable` items never get a price, so
// they must not block readiness. This mirrors the backend predicate in
// app_fetcher/app/services/inventory_value_recording_service.rb
// (`items.marketable.where(current_price_cents: nil)`), which gates the
// first InventoryValueLog row on the same condition — keep the two in
// sync.
//
// `items` are the dashboard's merged items (carrying `marketable` and
// `currentPriceCents`); a partially-loaded or empty list is a normal
// input, not an error.

export function isFullyPriced(items) {
  if (!items || items.length === 0) return true
  return items.every((item) => !item.marketable || item.currentPriceCents != null)
}

export function pricedTotalCents(items) {
  if (!items || items.length === 0) return 0
  return items.reduce((sum, item) => sum + (item.currentPriceCents || 0), 0)
}
