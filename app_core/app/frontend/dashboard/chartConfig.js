// The one place to retune chart density. Not yet known to be "right" —
// change these freely, nothing else in the dashboard needs to change.

export const RANGE_POINTS = { '24h': 24, '7d': 7, '30d': 30 } // data points plotted per range
export const X_AXIS_TICK_COUNT = 5 // x-axis labels shown (independent of point count)
export const Y_AXIS_TICK_COUNT = 4 // y-axis price labels shown

export const RANGES = ['24h', '7d', '30d']

// How much real time each range spans, independent of how many points we plot for it.
const RANGE_SPAN = { '24h': { units: 24, label: 'h', now: 'now' }, '7d': { units: 7, label: 'd', now: 'today' }, '30d': { units: 30, label: 'd', now: 'today' } }

export function generateAxisLabels(range, tickCount = X_AXIS_TICK_COUNT) {
  const { units, label, now } = RANGE_SPAN[range]

  return Array.from({ length: tickCount }, (_, i) => {
    const frac = tickCount === 1 ? 1 : i / (tickCount - 1)
    const unitsAgo = Math.round(units * (1 - frac))
    return unitsAgo === 0 ? now : `${unitsAgo}${label} ago`
  })
}
