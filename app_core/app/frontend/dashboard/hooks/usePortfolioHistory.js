import { useEffect, useState } from 'react'

export function usePortfolioHistory(fetcherUrl, bridgeToken, period) {
  const [series, setSeries] = useState([])
  const [status, setStatus] = useState('loading')

  useEffect(() => {
    let cancelled = false
    setStatus('loading')

    async function load() {
      const response = await fetch(`${fetcherUrl}/api/v1/inventory_values?period=${period}`, {
        headers: { Accept: 'application/json', Authorization: `Bearer ${bridgeToken}` },
      })
      if (!response.ok) throw new Error(`Request to inventory_values failed: ${response.status}`)
      const points = await response.json()

      if (cancelled) return
      setSeries(points.map((point) => ({ at: new Date(point.date).getTime(), value: point.total_value_cents })))
      setStatus('success')
    }

    load().catch(() => {
      if (!cancelled) setStatus('error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, bridgeToken, period])

  return { series, status }
}
