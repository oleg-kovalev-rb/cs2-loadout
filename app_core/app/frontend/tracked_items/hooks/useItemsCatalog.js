import { useEffect, useRef, useState } from 'react'

const SEARCH_DEBOUNCE_MS = 300

function mapItem(raw) {
  const metadata = raw.metadata || {}

  return {
    marketHashName: raw.market_hash_name,
    weaponType: metadata.weapon_type,
    itemName: metadata.item_name,
    category: metadata.category,
    condition: metadata.condition,
    stattrak: metadata.stattrak || false,
    iconUrl: metadata.icon_url,
    rarity: metadata.rarity,
    currentPriceCents: raw.current_price_cents,
    changeCents: raw.change_24h_cents,
    change24hPercent: raw.change_24h_percent,
    trendPoints: (raw.trend_7d || []).map((point) => ({
      at: point.at,
      priceCents: point.price_cents,
    })),
  }
}

function mapMeta(raw) {
  return {
    page: raw.page,
    perPage: raw.per_page,
    totalCount: raw.total_count,
    totalPages: raw.total_pages,
    gainingCount: raw.gaining_count,
    losingCount: raw.losing_count,
    lastSyncedAt: raw.last_synced_at,
  }
}

function buildQuery({ search, categories, rarities, stattrakOnly, sort, page, perPage }) {
  const params = new URLSearchParams()
  categories.forEach((value) => params.append('category[]', value))
  rarities.forEach((value) => params.append('rarity[]', value))
  if (stattrakOnly) params.set('stattrak', 'true')
  if (search) params.set('search', search)
  params.set('sort', sort)
  params.set('page', String(page))
  params.set('per_page', String(perPage))
  return params.toString()
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!response.ok) throw new Error(`Request to ${url} failed: ${response.status}`)
  return response.json()
}

// Public endpoint — no Authorization header, unlike every other dashboard
// hook's bridge-token-authenticated fetch (see architecture-layers.md:
// Api::Public:: has no notion of caller identity at all).
//
// `search` is the only param debounced: it's the one control that fires on
// every keystroke. Every other param (categories/rarities/stattrakOnly/
// sort/page/perPage) refetches immediately on change — `view`/`openDropdown`
// are deliberately not part of this hook's params at all, since neither
// affects what to fetch, only how to render what's already loaded.
export function useItemsCatalog(
  fetcherUrl,
  { search, categories, rarities, stattrakOnly, sort, page, perPage },
) {
  const [debouncedSearch, setDebouncedSearch] = useState(search)
  const isFirstSearch = useRef(true)

  useEffect(() => {
    if (isFirstSearch.current) {
      isFirstSearch.current = false
      setDebouncedSearch(search)
      return undefined
    }

    const timer = setTimeout(() => setDebouncedSearch(search), SEARCH_DEBOUNCE_MS)
    return () => clearTimeout(timer)
  }, [search])

  const [data, setData] = useState(null)
  const [status, setStatus] = useState('loading')
  const [error, setError] = useState(null)

  const categoriesKey = Array.from(categories).sort().join(',')
  const raritiesKey = Array.from(rarities).sort().join(',')

  useEffect(() => {
    let cancelled = false
    setStatus('loading')

    const query = buildQuery({
      search: debouncedSearch,
      categories,
      rarities,
      stattrakOnly,
      sort,
      page,
      perPage,
    })

    fetchJson(`${fetcherUrl}/api/public/items?${query}`)
      .then((raw) => {
        if (cancelled) return
        setData({ meta: mapMeta(raw.meta), items: raw.items.map(mapItem) })
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
    // categories/rarities are represented by categoriesKey/raritiesKey below —
    // the Set objects themselves are new references every render and would
    // otherwise refetch on every unrelated re-render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fetcherUrl, debouncedSearch, categoriesKey, raritiesKey, stattrakOnly, sort, page, perPage])

  return { data, status, error }
}
