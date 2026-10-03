import { useEffect, useState } from 'react'

function mapTrend(raw) {
  const mapped = {}
  for (const [name, points] of Object.entries(raw)) {
    mapped[name] = points.map((point) => ({ at: point.at, priceCents: point.price_cents, volume: point.volume }))
  }
  return mapped
}

// names is the full skeleton item-name list — gates when the effect fires
// (after the skeleton resolves) so UserInventoryCache is guaranteed to
// already have a row for this steam_id. Not sent to the backend; trend
// takes no params.
export function useItemTrend(fetcherUrl, bridgeToken, names) {
  const [trendByName, setTrendByName] = useState({})
  // 'pending' | 'ready' | 'error' — matches MarketVolumeTile's existing
  // historyStatus prop contract directly, so Dashboard.jsx can pass this
  // hook's status straight through with no vocabulary translation.
  const [status, setStatus] = useState('pending')

  useEffect(() => {
    if (!names || names.length === 0) return undefined

    let cancelled = false

    async function load() {
      const response = await fetch(`${fetcherUrl}/api/v1/item_prices/trend`, {
        headers: { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` },
      })
      if (!response.ok) throw new Error(`Request to item_prices/trend failed: ${response.status}`)
      const raw = await response.json()

      if (cancelled) return
      setTrendByName(mapTrend(raw))
      setStatus('ready')
    }

    load().catch(() => {
      if (!cancelled) setStatus('error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, bridgeToken, names])

  return { trendByName, status }
}
