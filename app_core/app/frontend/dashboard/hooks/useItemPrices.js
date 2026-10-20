import { useEffect, useState } from 'react'
import { RETRY_SCHEDULE_MS } from '../../shared/utils/retrySchedule'

function mapPrice(raw) {
  return {
    currentPriceCents: raw.current_price_cents,
    change24hCents: raw.change_24h_cents,
    change24hPercent: raw.change_24h_percent,
    priceUpdatedAt: raw.price_updated_at ? new Date(raw.price_updated_at).getTime() : null,
  }
}

async function fetchDynamics(fetcherUrl, bridgeToken, apiBase) {
  const response = await fetch(`${fetcherUrl}${apiBase}/item_prices/dynamics`, {
    headers: { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` },
  })
  if (!response.ok) throw new Error(`Request to item_prices/dynamics failed: ${response.status}`)
  const raw = await response.json()

  const prices = {}
  for (const [name, value] of Object.entries(raw.prices || {})) {
    prices[name] = mapPrice(value)
  }
  return { prices, pendingCount: raw.pending_count ?? 0 }
}

// names is the full skeleton item-name list — not sent to the backend
// (dynamics takes no params), used only to gate when the effect fires
// (after the skeleton resolves). Retry coverage comes from the backend's
// pending_count: the number of owned items that are marketable, not
// price_unavailable, and still missing a price. Comparing response keys
// against `names` instead would never look covered once the inventory
// contains a non-marketable or price-unavailable item.
export function useItemPrices(fetcherUrl, bridgeToken, names, apiBase = '/api/v1') {
  const [pricesByName, setPricesByName] = useState({})
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!names || names.length === 0) return undefined

    let cancelled = false
    let loaded = false
    const timers = []

    async function attempt(index) {
      try {
        const { prices, pendingCount } = await fetchDynamics(fetcherUrl, bridgeToken, apiBase)
        if (cancelled) return

        loaded = true
        setPricesByName(prices)
        setStatus('success')
        setError(null)

        if (pendingCount > 0 && index < RETRY_SCHEDULE_MS.length) {
          const timer = setTimeout(() => attempt(index + 1), RETRY_SCHEDULE_MS[index])
          timers.push(timer)
        }
      } catch (err) {
        // A failed retry must not discard prices that already loaded —
        // only the initial fetch failing leaves nothing to render.
        if (cancelled || loaded) return
        setError(err)
        setStatus('error')
      }
    }

    timers.push(setTimeout(() => attempt(0), 0))

    return () => {
      cancelled = true
      timers.forEach(clearTimeout)
    }
  }, [fetcherUrl, bridgeToken, names, apiBase])

  return { pricesByName, status, error }
}
