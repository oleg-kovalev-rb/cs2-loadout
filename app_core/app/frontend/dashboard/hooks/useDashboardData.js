import { useEffect, useState } from 'react'

function mapItem(raw) {
  return {
    marketHashName: raw.market_hash_name,
    weaponType: raw.weapon_type,
    itemName: raw.item_name,
    condition: raw.condition,
    stattrak: raw.stattrak,
    currentPriceCents: raw.current_price_cents,
    changeCents: raw.change_24h_cents,
  }
}

function mapData(raw) {
  return {
    itemsCount: raw.items_count,
    items: raw.items.map(mapItem),
    portfolio: {
      currentValueCents: raw.portfolio.current_value_cents,
      series: raw.portfolio.series,
    },
    marketVolume: {
      countLast24h: raw.market_volume.count_24h,
      sparkline: raw.market_volume.sparkline,
    },
  }
}

export function useDashboardData(apiUrl) {
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading') // 'loading' | 'success' | 'error'
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false

    fetch(apiUrl, { headers: { Accept: 'application/json' } })
      .then((response) => {
        if (!response.ok) throw new Error(`Request failed: ${response.status}`)
        return response.json()
      })
      .then((raw) => {
        if (cancelled) return
        setData(mapData(raw))
        setStatus('success')
      })
      .catch((err) => {
        if (cancelled) return
        setError(err)
        setStatus('error')
      })

    return () => {
      cancelled = true
    }
  }, [apiUrl])

  return { data, status, error }
}
