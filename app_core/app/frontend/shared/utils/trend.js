// The one place a 24h change becomes an item row's trend direction. A zero
// or absent change is deliberately NOT 'up' — collapsing it into the green
// --up bucket makes a flat row read as rising and renders a misleading
// "▲ 0.0%". Every island's item row derives its direction here (see
// agent/styleguides/core/react-dashboard.md), so the flat rule can't drift
// per call site.
export function trendDirection(pct) {
  if (!pct) return 'flat' // covers 0, -0, null, undefined, NaN
  return pct > 0 ? 'up' : 'down'
}
