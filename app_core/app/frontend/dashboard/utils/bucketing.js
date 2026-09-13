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

export function sumAsOfEachHour(itemPointLists, windowMs, getValue) {
  const now = Date.now()
  const startHour = Math.floor((now - windowMs) / HOUR_MS) * HOUR_MS
  const nowHour = Math.floor(now / HOUR_MS) * HOUR_MS

  const sortedLists = itemPointLists.map((points) =>
    [...points].map((p) => ({ ...p, atMs: new Date(p.at).getTime() })).sort((a, b) => a.atMs - b.atMs)
  )

  const result = []
  for (let hour = startHour; hour <= nowHour; hour += HOUR_MS) {
    let total = 0
    let hasAnyData = false

    for (const points of sortedLists) {
      let latest = null
      for (const point of points) {
        if (point.atMs > hour) break
        latest = point
      }
      if (latest) {
        total += getValue(latest)
        hasAnyData = true
      }
    }

    if (hasAnyData) result.push({ at: hour, value: total })
  }

  return result
}
