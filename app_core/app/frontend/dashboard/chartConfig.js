// The one place to retune chart density. Not yet known to be "right" —
// change these freely, nothing else in the dashboard needs to change.

export const RANGE_MS = {
  '24h': 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
  '1y': 365 * 24 * 60 * 60 * 1000,
}

export const X_AXIS_TICK_COUNT = 5 // x-axis labels shown (independent of point count)
export const Y_AXIS_TICK_COUNT = 4 // y-axis price labels shown

// The portfolio hero chart and the item-detail chart offer different
// range sets — InventoryValueLog only has daily granularity, so a 24h
// portfolio view isn't meaningful today; PriceLog's ~hourly granularity
// supports it for a single item.
export const PORTFOLIO_RANGES = ['7d', '30d', '1y', 'all']
export const ITEM_RANGES = ['24h', '7d', '30d', '1y', 'all']

// How much real time each range spans, independent of how many points we plot for it.
const RANGE_SPAN = {
  '24h': { units: 24, label: 'h', now: 'now' },
  '7d': { units: 7, label: 'd', now: 'today' },
  '30d': { units: 30, label: 'd', now: 'today' },
  '1y': { units: 12, label: 'mo', now: 'today' },
}

// 'all' has no fixed span to count back from — it's bounded by whatever
// data actually exists, not a known duration — so only the trailing
// "today" tick is meaningful; earlier ticks are left blank rather than
// showing a fabricated relative offset.
export function generateAxisLabels(range, tickCount = X_AXIS_TICK_COUNT) {
  if (range === 'all') {
    return Array.from({ length: tickCount }, (_, i) => (i === tickCount - 1 ? 'today' : ''))
  }

  const { units, label, now } = RANGE_SPAN[range]

  return Array.from({ length: tickCount }, (_, i) => {
    const frac = tickCount === 1 ? 1 : i / (tickCount - 1)
    const unitsAgo = Math.round(units * (1 - frac))
    return unitsAgo === 0 ? now : `${unitsAgo}${label} ago`
  })
}
