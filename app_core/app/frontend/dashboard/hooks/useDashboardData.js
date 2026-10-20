import { useEffect, useState } from 'react'
import { fetchJson } from '../../shared/utils/fetchJson'

function mapItem(raw) {
  const metadata = raw.metadata || {}

  return {
    marketHashName: raw.market_hash_name,
    weaponType: metadata.weapon_type,
    itemName: metadata.item_name,
    condition: metadata.condition,
    stattrak: metadata.stattrak || false,
    marketable: metadata.marketable || false,
    priceUnavailable: raw.price_unavailable || false,
    iconUrl: metadata.icon_url,
    currentPriceCents: null,
    change24hCents: 0,
    change24hPercent: 0,
    trendPoints: [],
  }
}

// Skeleton-only: this hook's single job is "what does this user own."
// Prices (useItemPrices), trend (useItemTrend), and portfolio/item history
// (usePortfolioHistory/useItemHistory) are separate hooks, each gated on
// this one having resolved first.
export function useDashboardData(fetcherUrl, bridgeToken, apiBase = '/api/v1') {
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    const authHeaders = { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` }

    async function load() {
      const inventory = await fetchJson(`${fetcherUrl}${apiBase}/inventories/me`, {
        headers: authHeaders,
      })

      if (cancelled) return
      setData({ itemsCount: inventory.items_count, items: inventory.items.map(mapItem) })
      setStatus('success')
    }

    load().catch((err) => {
      if (cancelled) return
      setError(err)
      setStatus('error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, bridgeToken, apiBase])

  return { data, status, error }
}
