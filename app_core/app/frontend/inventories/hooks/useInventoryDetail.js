import { useEffect, useState } from 'react'

class NotFoundError extends Error {}

function mapItemSummary(item) {
  const metadata = item.metadata || {}

  return {
    marketHashName: item.market_hash_name,
    weaponType: metadata.weapon_type,
    itemName: metadata.item_name,
    condition: metadata.condition,
    stattrak: metadata.stattrak || false,
    iconUrl: metadata.icon_url,
    currentPriceCents: item.current_price_cents,
    change24hCents: item.change_24h_cents ?? 0,
    change24hPercent: item.change_24h_percent ?? 0,
    priceUpdatedAt: item.price_updated_at ? new Date(item.price_updated_at).getTime() : null,
    trendPoints: (item.trend_7d || []).map((point) => ({
      at: new Date(point.at).getTime(),
      priceCents: point.price_cents,
    })),
  }
}

function mapDetail(raw) {
  return {
    steamId: raw.steam_id,
    lastSyncedAt: raw.last_synced_at,
    portfolio: {
      totalValueCents: raw.portfolio.total_value_cents,
      changeCents: raw.portfolio.change_cents,
      changePercent: raw.portfolio.change_percent,
      changeBasisAt: raw.portfolio.change_basis_at
        ? new Date(raw.portfolio.change_basis_at).getTime()
        : null,
      changePartial: raw.portfolio.change_partial ?? false,
      changeAvailable: raw.portfolio.change_available ?? true,
      complete: raw.portfolio.complete ?? true,
      pricedItemsCount: raw.portfolio.priced_items_count ?? null,
      pricableItemsCount: raw.portfolio.pricable_items_count ?? null,
      oldestPriceAt: raw.portfolio.oldest_price_at
        ? new Date(raw.portfolio.oldest_price_at).getTime()
        : null,
      period: raw.portfolio.period,
      history: raw.portfolio.history.map((point) => ({
        at: new Date(point.at).getTime(),
        value: point.total_value_cents,
        complete: point.complete ?? true,
        pricedItemsCount: point.priced_items_count ?? null,
        pricableItemsCount: point.pricable_items_count ?? null,
      })),
    },
    itemsCount: raw.items_count,
    avgItemValueCents: raw.avg_item_value_cents,
    priciestItem: raw.priciest_item ? mapItemSummary(raw.priciest_item) : null,
    rarityBreakdown: raw.rarity_breakdown,
    topItems: {
      meta: raw.top_items.meta,
      entries: raw.top_items.entries.map(mapItemSummary),
    },
  }
}

async function fetchDetailJson(url, token = null) {
  const headers = { Accept: 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`

  const response = await fetch(url, { headers })
  if (response.status === 404) throw new NotFoundError()
  if (!response.ok) throw new Error(`Request to ${url} failed: ${response.status}`)
  return response.json()
}

// GET api/public/inventories/:steam_id needs no bridge token at all —
// same unauthenticated endpoint family as useInventoryCatalog. Unlike
// dashboard's multi-hook progressive-hydration design, this endpoint
// already returns one fully composed payload per request, so a single
// hook with a flat status is correct here — no need to split loading
// into independently-resolving stages this page doesn't have.
export function useInventoryDetail(
  fetcherUrl,
  steamId,
  { period, sort, page, perPage, demo = false, demoToken = null, apiBase = '/api/public' },
) {
  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading')

  useEffect(() => {
    let cancelled = false
    setStatus('loading')

    async function load() {
      const query = `period=${period}&sort=${sort}&page=${page}&per_page=${perPage}`
      const url = demo
        ? `${fetcherUrl}${apiBase}/inventory_detail?${query}`
        : `${fetcherUrl}/api/public/inventories/${steamId}?${query}`
      const payload = await fetchDetailJson(url, demo ? demoToken : null)

      if (cancelled) return
      setData(mapDetail(payload))
      setStatus('success')
    }

    load().catch((err) => {
      if (cancelled) return
      setStatus(err instanceof NotFoundError ? 'not_found' : 'error')
    })

    return () => {
      cancelled = true
    }
  }, [fetcherUrl, steamId, period, sort, page, perPage, demo, demoToken, apiBase])

  return { data, status }
}
