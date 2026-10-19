// Same derivation as ItemCatalogSerializer: compare against yesterday's
// price (current - change), not the current price itself. A missing price or
// a zero base is deliberately 0, so the caller's trendDirection maps it to
// 'flat' rather than a misleading rise.
export function changePercent(currentPriceCents, changeCents) {
  if (currentPriceCents == null) return 0

  const change = changeCents || 0
  const base = currentPriceCents - change

  return base === 0 ? 0 : (change / base) * 100
}
