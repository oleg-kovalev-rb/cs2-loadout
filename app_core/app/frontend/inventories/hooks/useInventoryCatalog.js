import { useEffect, useState } from 'react'

const PER_PAGE = 24

function mapInventory(raw) {
  return {
    steamId: raw.steam_id,
    totalValueCents: raw.total_value_cents,
    change24hCents: raw.change_24h_cents,
    change24hPercent: raw.change_24h_percent,
    itemsCount: raw.items_count,
    rarityMixPercent: raw.rarity_mix_percent,
    lastSyncedAt: raw.last_synced_at,
  }
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!response.ok) throw new Error(`Request to ${url} failed: ${response.status}`)
  return response.json()
}

// GET api/public/inventories needs no bridge token at all — it's a
// genuinely unauthenticated endpoint (Api::Public::ApplicationController
// has no auth filter), unlike dashboard/'s api/v1/* calls.
export function useInventoryCatalog(fetcherUrl, { page, sort }) {
  const [inventories, setInventories] = useState([])
  const [meta, setMeta] = useState(null)
  const [status, setStatus] = useState('loading')

  useEffect(() => {
    let cancelled = false
    setStatus('loading')

    async function load() {
      const payload = await fetchJson(`${fetcherUrl}/api/public/inventories?page=${page}&per_page=${PER_PAGE}&sort=${sort}`)

      if (cancelled) return
      setInventories(payload.inventories.map(mapInventory))
      setMeta(payload.meta)
      setStatus('success')
    }

    load().catch(() => {
      if (!cancelled) setStatus('error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, page, sort])

  return { inventories, meta, status }
}
