const HOUR_MS = 60 * 60 * 1000

export function bucketByHour(points, windowMs, getValue) {
  const cutoff = Date.now() - windowMs
  const buckets = new Map()

  for (const point of points) {
    const at = new Date(point.at).getTime()
    if (at < cutoff) continue

    const hourKey = Math.floor(at / HOUR_MS) * HOUR_MS
    buckets.set(hourKey, (buckets.get(hourKey) || 0) + getValue(point))
  }

  return [...buckets.entries()].sort((a, b) => a[0] - b[0]).map(([at, value]) => ({ at, value }))
}
