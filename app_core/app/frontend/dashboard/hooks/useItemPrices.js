import { useEffect, useState } from 'react'

// Deliberately matches PriceUpdateWorker's warmup dedup TTL (90s) — the
// system's own estimate of how long a warmed-up price should take.
const RETRY_SCHEDULE_MS = [3000, 6000, 12000, 24000, 45000]

function mapPrice(raw) {
  return {
    currentPriceCents: raw.current_price_cents,
    changeCents: raw.change_24h_cents,
    change24hPercent: raw.change_24h_percent,
  }
}

async function fetchDynamics(fetcherUrl, bridgeToken) {
  const response = await fetch(`${fetcherUrl}/api/v1/item_prices/dynamics`, {
    headers: { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` },
  })
  if (!response.ok) throw new Error(`Request to item_prices/dynamics failed: ${response.status}`)
  const raw = await response.json()

  const mapped = {}
  for (const [name, value] of Object.entries(raw)) {
    mapped[name] = mapPrice(value)
  }
  return mapped
}

// names is the full skeleton item-name list — not sent to the backend
// (dynamics takes no params), used only to gate when the effect fires
// (after the skeleton resolves) and to know when a retry has covered
// every owned item.
export function useItemPrices(fetcherUrl, bridgeToken, names) {
  const [pricesByName, setPricesByName] = useState({})
  const [status, setStatus] = useState('loading')

  useEffect(() => {
    if (!names || names.length === 0) return undefined

    let cancelled = false
    const timers = []

    async function attempt(index) {
      try {
        const result = await fetchDynamics(fetcherUrl, bridgeToken)
        if (cancelled) return

        setPricesByName(result)
        setStatus('success')

        const covered = Object.keys(result).length >= names.length
        if (!covered && index < RETRY_SCHEDULE_MS.length) {
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
  }, [fetcherUrl, bridgeToken, names])

  return { pricesByName, status }
}
