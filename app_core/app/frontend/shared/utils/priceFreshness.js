const HOUR_MS = 60 * 60 * 1000
export const STALE_PRICE_AFTER_MS = 24 * HOUR_MS

// A missing timestamp means "never priced", not "stale": the unpriced row is
// handled by the price/nil rendering, not by this freshness marker.
export function isPriceStale(updatedAt, now = Date.now()) {
  if (updatedAt == null) return false
  return now - updatedAt > STALE_PRICE_AFTER_MS
}

export function priceAgeLabel(updatedAt, now = Date.now()) {
  if (updatedAt == null) return null

  const hours = Math.max(0, Math.floor((now - updatedAt) / HOUR_MS))
  if (hours < 1) return 'less than an hour ago'
  if (hours < 24) return `${hours}h ago`

  return `${Math.floor(hours / 24)}d ago`
}
