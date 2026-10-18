// Names the price hook should wait for. Non-marketable items never get a
// price, and `price_unavailable` items have no current Steam price to fetch
// (they may still carry a last known price, which the dynamics endpoint
// returns independently of this coverage list).
export function priceableNames(items) {
  if (!items) return []

  return items
    .filter((item) => item.marketable && !item.priceUnavailable)
    .map((item) => item.marketHashName)
}
