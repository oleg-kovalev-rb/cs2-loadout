import { bucketByHour } from './bucketing'

const SPARKLINE_WINDOW_MS = 15 * 60 * 60 * 1000

export function marketVolume(items) {
  const allPoints = items.flatMap((item) => item.priceHistory)
  const sparkline = bucketByHour(allPoints, SPARKLINE_WINDOW_MS, (point) => point.volume).map((bucket) => bucket.value)

  return { countLast24h: sparkline[sparkline.length - 1] || 0, sparkline }
}
