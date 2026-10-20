import { useEffect, useState } from 'react'
import { RETRY_SCHEDULE_MS } from '../../shared/utils/retrySchedule'

function mapPoint(point) {
  return {
    at: new Date(point.at).getTime(),
    value: point.total_value_cents,
    complete: point.complete,
    pricedItemsCount: point.priced_items_count,
    pricableItemsCount: point.pricable_items_count,
  }
}

function mapCurrent(raw) {
  if (!raw) return null

  return {
    totalValueCents: raw.total_value_cents,
    itemsCount: raw.items_count,
    pricableItemsCount: raw.pricable_items_count,
    pricedItemsCount: raw.priced_items_count,
    complete: raw.complete,
    oldestPriceAt: raw.oldest_price_at ? new Date(raw.oldest_price_at).getTime() : null,
  }
}

function mapChange(raw) {
  return {
    cents: raw.cents,
    percent: raw.percent,
    basisAt: raw.basis_at ? new Date(raw.basis_at).getTime() : null,
    partial: raw.partial,
    available: raw.available,
  }
}

export function usePortfolioHistory(fetcherUrl, bridgeToken, period) {
  const [series, setSeries] = useState([])
  const [current, setCurrent] = useState(null)
  const [change, setChange] = useState(null)
  const [status, setStatus] = useState('loading')

  useEffect(() => {
    let cancelled = false
    const timers = []
    setStatus('loading')

    async function attempt(index) {
      try {
        const response = await fetch(`${fetcherUrl}/api/v1/inventory_values?period=${period}`, {
          headers: { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` },
        })
        if (!response.ok) throw new Error(`Request to inventory_values failed: ${response.status}`)
        const payload = await response.json()

        if (cancelled) return
        setSeries((payload.history || []).map(mapPoint))
        setCurrent(mapCurrent(payload.current))
        setChange(mapChange(payload.change))
        setStatus('success')

        const retryable = payload.current == null || payload.current.complete !== true
        if (retryable && index < RETRY_SCHEDULE_MS.length) {
          const timer = setTimeout(() => attempt(index + 1), RETRY_SCHEDULE_MS[index])
          timers.push(timer)
        }
      } catch {
        if (!cancelled) setStatus('error')
      }
    }

    timers.push(setTimeout(() => attempt(0), 0))

    return () => {
      cancelled = true
      timers.forEach(clearTimeout)
    }
  }, [fetcherUrl, bridgeToken, period])

  return { series, current, change, status }
}
