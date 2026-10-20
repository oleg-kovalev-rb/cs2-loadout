import { useEffect, useState } from 'react'
import { fetchJson } from '../../shared/utils/fetchJson'
import { INVENTORIES_PER_PAGE } from '../constants'

export function mapInventory(raw) {
  return {
    steamId: raw.steam_id,
    totalValueCents: raw.total_value_cents,
    change24hCents: raw.change_24h_cents,
    change24hPercent: raw.change_24h_percent,
    changeBasisAt: raw.change_basis_at ? new Date(raw.change_basis_at).getTime() : null,
    changePartial: raw.change_partial ?? false,
    changeAvailable: raw.change_available ?? true,
    itemsCount: raw.items_count,
    pricedItemsCount: raw.priced_items_count ?? null,
    pricableItemsCount: raw.pricable_items_count ?? null,
    complete: raw.complete ?? true,
    rarityBreakdown: raw.rarity_breakdown,
    lastSyncedAt: raw.last_synced_at,
  }
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
      const payload = await fetchJson(
        `${fetcherUrl}/api/public/inventories?page=${page}&per_page=${INVENTORIES_PER_PAGE}&sort=${sort}`,
        { headers: { Accept: 'application/json' } },
      )

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
