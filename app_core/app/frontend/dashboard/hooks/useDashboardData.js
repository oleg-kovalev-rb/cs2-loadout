import { useEffect, useState } from 'react'
import { portfolioSeries } from '../utils/portfolioSeries'
import { marketVolume } from '../utils/marketVolume'

function mapItem(raw, pointsByName) {
  const metadata = raw.metadata || {}
  const points = pointsByName[raw.market_hash_name] || []

  return {
    marketHashName: raw.market_hash_name,
    weaponType: metadata.weapon_type,
    itemName: metadata.item_name,
    condition: metadata.condition,
    stattrak: metadata.stattrak || false,
    currentPriceCents: raw.current_price_cents,
    changeCents: raw.change_24h_cents || 0,
    priceHistory: points.map((point) => ({
      at: point.at,
      priceCents: point.price_cents,
      volume: point.volume,
    })),
  }
}

function buildData(items) {
  return {
    itemsCount: items.length,
    items,
    portfolio: portfolioSeries(items),
    marketVolume: marketVolume(items),
  }
}

async function fetchJson(url, options) {
  const response = await fetch(url, options)
  if (!response.ok) throw new Error(`Request to ${url} failed: ${response.status}`)
  return response.json()
}

export function useDashboardData(fetcherUrl, bridgeToken) {
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading') // 'loading' | 'success' | 'error'
  const [historyStatus, setHistoryStatus] = useState('pending') // 'pending' | 'ready' | 'error'
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    const authHeaders = { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` }

    async function loadHistory(rawItems, names) {
      try {
        const history = await fetchJson(`${fetcherUrl}/api/v1/price_histories`, {
          method: 'POST',
          headers: { ...authHeaders, 'Content-Type': 'application/json' },
          body: JSON.stringify({ market_hash_names: names }),
        })

        const pointsByName = {}
        for (const entry of history.items) {
          pointsByName[entry.market_hash_name] = entry.points
        }

        if (cancelled) return
        setData(buildData(rawItems.map((raw) => mapItem(raw, pointsByName))))
        setHistoryStatus('ready')
      } catch {
        if (cancelled) return
        setHistoryStatus('error')
      }
    }

    async function load() {
      const inventory = await fetchJson(`${fetcherUrl}/api/v1/inventories/me`, { headers: authHeaders })
      const names = inventory.items.map((item) => item.market_hash_name)
      const items = inventory.items.map((raw) => mapItem(raw, {}))

      if (cancelled) return
      setData(buildData(items))
      setStatus('success')

      if (!names.length) {
        setHistoryStatus('ready')
        return
      }

      setHistoryStatus('pending')
      await loadHistory(inventory.items, names)
    }

    load().catch((err) => {
      if (cancelled) return
      setError(err)
      setStatus('error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, bridgeToken])

  return { data, status, historyStatus, error }
}
