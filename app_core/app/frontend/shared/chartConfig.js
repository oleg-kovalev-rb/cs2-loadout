// The one place to retune chart density/axis-label mechanics shared by
// every island's chart. Not yet known to be "right" — change these
// freely, nothing else needs to change. Per-island period-set choices
// (which of these periods a given chart actually offers) live in that
// island's own chartConfig.js, not here.

export const PERIOD_MS = {
  '24h': 24 * 60 * 60 * 1000,
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
  '1y': 365 * 24 * 60 * 60 * 1000,
}

export const X_AXIS_TICK_COUNT = 5 // x-axis labels shown (independent of point count)
export const Y_AXIS_TICK_COUNT = 4 // y-axis price labels shown

const PERIOD_LABEL = {
  '24h': { label: 'h', now: 'now' },
  '7d': { label: 'd', now: 'today' },
  '30d': { label: 'd', now: 'today' },
  '1y': { label: 'mo', now: 'today' },
}

const UNIT_MS = {
  h: 60 * 60 * 1000,
  d: 24 * 60 * 60 * 1000,
  mo: (365 * 24 * 60 * 60 * 1000) / 12,
}

// Whole-unit labels stop being readable when the span has fewer units than
// there are gaps between ticks: rounding then produces duplicate labels.
const MIN_UNITS_FOR_WHOLE_LABELS = X_AXIS_TICK_COUNT - 1

function labelUnit(nominalLabel, spanMs) {
  if (nominalLabel === 'h') return 'h'
  if (spanMs / UNIT_MS[nominalLabel] >= MIN_UNITS_FOR_WHOLE_LABELS) return nominalLabel

  return nominalLabel === 'mo' ? 'd' : 'h'
}

// `start`/`end` are the effective x-axis extent, not the nominal period: the
// chart extends the axis to include the data (Recharts' allowDataOverflow is
// false), so a short series gets labels for the span it actually has instead
// of a left-hand label claiming history that doesn't exist.
export function generateAxisLabels(period, start, end, tickCount = X_AXIS_TICK_COUNT) {
  // 'all' has no fixed span to count back from — it's bounded by whatever
  // data actually exists, not a known duration — so only the trailing
  // "today" tick is meaningful; earlier ticks are left blank rather than
  // showing a fabricated relative offset.
  if (period === 'all') {
    return Array.from({ length: tickCount }, (_, i) => (i === tickCount - 1 ? 'today' : ''))
  }

  const { label: nominalLabel, now } = PERIOD_LABEL[period]
  const span = end > start ? end - start : PERIOD_MS[period]
  const label = labelUnit(nominalLabel, span)
  const spanUnits = span / UNIT_MS[label]

  return Array.from({ length: tickCount }, (_, i) => {
    const frac = tickCount === 1 ? 1 : i / (tickCount - 1)
    const unitsAgo = Math.round(spanUnits * (1 - frac))
    return unitsAgo === 0 ? now : `${unitsAgo}${label} ago`
  })
}
