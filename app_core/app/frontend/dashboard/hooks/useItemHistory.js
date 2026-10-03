import { useEffect, useState } from 'react'

export function useItemHistory(fetcherUrl, bridgeToken, marketHashName, period) {
  const [series, setSeries] = useState([])
  const [status, setStatus] = useState('pending')

  useEffect(() => {
    if (!marketHashName) {
      setSeries([])
      setStatus('pending')
      return undefined
    }

    let cancelled = false
    setStatus('pending')

    async function load() {
      const url = `${fetcherUrl}/api/v1/item_prices/${encodeURIComponent(marketHashName)}/history?period=${period}`
      const response = await fetch(url, {
        headers: { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` },
      })
      if (!response.ok) throw new Error(`Request to item_prices/history failed: ${response.status}`)
      const points = await response.json()

      if (cancelled) return
      setSeries(points.map((point) => ({ at: new Date(point.at).getTime(), value: point.price_cents })))
      setStatus('ready')
    }

    load().catch(() => {
      if (!cancelled) setStatus('error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, bridgeToken, marketHashName, period])

  return { series, status }
}
