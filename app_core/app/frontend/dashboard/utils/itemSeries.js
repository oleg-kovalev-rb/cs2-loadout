import { RANGE_MS } from '../chartConfig'

export function itemSeries(item, range) {
  const cutoff = Date.now() - RANGE_MS[range]

  const points = (item.priceHistory || [])
    .filter((point) => new Date(point.at).getTime() >= cutoff)
    .sort((a, b) => new Date(a.at) - new Date(b.at))
    .map((point) => ({ at: new Date(point.at).getTime(), value: point.priceCents }))

  if (item.currentPriceCents == null) return points
  if (points[points.length - 1]?.value !== item.currentPriceCents) {
    points.push({ at: Date.now(), value: item.currentPriceCents })
  }

  return points
}
