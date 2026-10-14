import { renderHook, waitFor, act } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useItemsCatalog } from '../hooks/useItemsCatalog'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

const CATALOG_BODY = {
  meta: {
    page: 1,
    per_page: 25,
    total_count: 1284,
    total_pages: 52,
    gaining_count: 612,
    losing_count: 401,
    last_synced_at: '2026-10-12T10:00:00Z',
  },
  items: [
    {
      market_hash_name: 'AK-47 | Redline (Field-Tested)',
      metadata: {
        weapon_type: 'AK-47',
        item_name: 'Redline',
        category: 'Rifles',
        condition: 'Field-Tested',
        stattrak: false,
        icon_url: 'https://example.com/icon.png',
        rarity: 'Classified',
      },
      current_price_cents: 4218,
      change_24h_cents: 130,
      change_24h_percent: 3.18,
      trend_7d: [{ at: '2026-10-10T00:00:00Z', price_cents: 4000 }],
    },
  ],
}

function baseParams(overrides = {}) {
  return {
    search: '',
    categories: new Set(),
    rarities: new Set(),
    stattrakOnly: false,
    sort: 'change_24h_desc',
    page: 1,
    perPage: 25,
    ...overrides,
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('useItemsCatalog', () => {
  test('fetches immediately on mount with no Authorization header and maps the response', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(CATALOG_BODY))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemsCatalog('http://fetcher.test', baseParams()))

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url, options] = fetchMock.mock.calls[0]
    expect(url).toMatch(/^http:\/\/fetcher\.test\/api\/public\/items\?/)
    expect(options.headers.Authorization).toBeUndefined()

    expect(result.current.data.meta).toEqual({
      page: 1,
      perPage: 25,
      totalCount: 1284,
      totalPages: 52,
      gainingCount: 612,
      losingCount: 401,
      lastSyncedAt: '2026-10-12T10:00:00Z',
    })
    expect(result.current.data.items[0]).toMatchObject({
      marketHashName: 'AK-47 | Redline (Field-Tested)',
      weaponType: 'AK-47',
      itemName: 'Redline',
      category: 'Rifles',
      condition: 'Field-Tested',
      stattrak: false,
      iconUrl: 'https://example.com/icon.png',
      rarity: 'Classified',
      currentPriceCents: 4218,
      changeCents: 130,
      change24hPercent: 3.18,
      trendPoints: [{ at: '2026-10-10T00:00:00Z', priceCents: 4000 }],
    })
  })

  test('builds the query string per param: category[]/rarity[] repeated, stattrak opt-in only, search omitted when blank', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(CATALOG_BODY))
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() =>
      useItemsCatalog(
        'http://fetcher.test',
        baseParams({
          categories: new Set(['Rifles', 'Knives']),
          rarities: new Set(['Covert']),
          stattrakOnly: true,
          sort: 'price_desc',
          page: 3,
          perPage: 50,
        })
      )
    )

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    const [url] = fetchMock.mock.calls[0]
    const params = new URL(url).searchParams
    expect(params.getAll('category[]')).toEqual(['Rifles', 'Knives'])
    expect(params.getAll('rarity[]')).toEqual(['Covert'])
    expect(params.get('stattrak')).toBe('true')
    expect(params.get('sort')).toBe('price_desc')
    expect(params.get('page')).toBe('3')
    expect(params.get('per_page')).toBe('50')
    expect(params.has('search')).toBe(false)
  })

  test('omits stattrak entirely when false (opt-in only, not a tri-state filter)', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(CATALOG_BODY))
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() => useItemsCatalog('http://fetcher.test', baseParams({ stattrakOnly: false })))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    const [url] = fetchMock.mock.calls[0]
    expect(new URL(url).searchParams.has('stattrak')).toBe(false)
  })

  test('debounces search: rapid changes within 300ms produce exactly one extra fetch, using the latest value', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(CATALOG_BODY))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook((props) => useItemsCatalog('http://fetcher.test', props), {
      initialProps: baseParams(),
    })

    await act(async () => { await vi.advanceTimersByTimeAsync(0) })
    expect(fetchMock).toHaveBeenCalledTimes(1)

    rerender(baseParams({ search: 'red' }))
    await act(async () => { await vi.advanceTimersByTimeAsync(100) })
    rerender(baseParams({ search: 'redl' }))
    await act(async () => { await vi.advanceTimersByTimeAsync(100) })
    rerender(baseParams({ search: 'redline' }))

    // still within the debounce window — no new fetch yet
    await act(async () => { await vi.advanceTimersByTimeAsync(100) })
    expect(fetchMock).toHaveBeenCalledTimes(1)

    // debounce settles 300ms after the last change
    await act(async () => { await vi.advanceTimersByTimeAsync(300) })
    expect(fetchMock).toHaveBeenCalledTimes(2)

    const [lastUrl] = fetchMock.mock.calls[1]
    expect(new URL(lastUrl).searchParams.get('search')).toBe('redline')
  })

  test('a non-search param change refetches immediately, without waiting on the debounce timer', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(CATALOG_BODY))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook((props) => useItemsCatalog('http://fetcher.test', props), {
      initialProps: baseParams({ sort: 'change_24h_desc' }),
    })

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    rerender(baseParams({ sort: 'price_asc' }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    const [url] = fetchMock.mock.calls[1]
    expect(new URL(url).searchParams.get('sort')).toBe('price_asc')
  })

  test('a superseded in-flight request does not clobber the newer one landing after it', async () => {
    let resolveFirst
    const firstPromise = new Promise((resolve) => { resolveFirst = resolve })

    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => firstPromise)
      .mockImplementationOnce(() => jsonResponse({ ...CATALOG_BODY, meta: { ...CATALOG_BODY.meta, page: 2 } }))
    vi.stubGlobal('fetch', fetchMock)

    const { result, rerender } = renderHook((props) => useItemsCatalog('http://fetcher.test', props), {
      initialProps: baseParams({ page: 1 }),
    })

    rerender(baseParams({ page: 2 }))
    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(result.current.data.meta.page).toBe(2)

    // the slow first request resolves after the second already landed — must not overwrite it
    await act(async () => {
      resolveFirst(await jsonResponse({ ...CATALOG_BODY, meta: { ...CATALOG_BODY.meta, page: 1 } }))
    })
    expect(result.current.data.meta.page).toBe(2)
  })

  test('surfaces an error state when the request fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementationOnce(() => jsonResponse({}, false)))

    const { result } = renderHook(() => useItemsCatalog('http://fetcher.test', baseParams()))

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })
})
