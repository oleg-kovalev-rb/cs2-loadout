import { RANGE_POINTS } from '../chartConfig'

function hashString(str) {
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = (Math.imul(31, hash) + str.charCodeAt(i)) | 0
  }
  return hash
}

function mulberry32(seed) {
  let a = seed
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// Deterministic (not random) so the same item always draws the same shape —
// derived entirely from real fields (currentPriceCents + changeCents), no
// server-shipped history needed. Shared by row/volume sparklines and the
// hero chart's item-mode view.
export function itemSeries(item, range) {
  const points = RANGE_POINTS[range]
  const end = item.currentPriceCents
  const start = end - item.changeCents
  const rnd = mulberry32(hashString(item.marketHashName) + points)

  const values = Array.from({ length: points }, (_, i) => {
    const t = points === 1 ? 1 : i / (points - 1)
    const base = start + (end - start) * t
    const wiggle = (rnd() - 0.5) * (Math.abs(end - start) || end * 0.06) * 0.5
    return Math.max(1, base + wiggle)
  })
  values[values.length - 1] = end

  return values
}
