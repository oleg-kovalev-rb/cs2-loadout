import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useInventoryDetail } from '../hooks/useInventoryDetail'

function jsonResponse(body, status = 200) {
  return Promise.resolve({ ok: status < 300, status, json: () => Promise.resolve(body) })
}

function detailPayload(overrides = {}) {
  return {
    steam_id: '76561198000000001',
    last_synced_at: '2026-10-12T15:30:45Z',
    portfolio: {
      total_value_cents: 500000,
      change_cents: 12500,
      change_percent: 2.5,
      change_basis_at: '2026-10-05T15:30:45Z',
      change_partial: false,
      change_available: true,
      complete: true,
      priced_items_count: 127,
      pricable_items_count: 127,
      oldest_price_at: '2026-10-12T15:30:45Z',
      period: '7d',
      history: [
        {
          at: '2026-10-05T15:30:45Z',
          total_value_cents: 487500,
          complete: true,
          priced_items_count: 127,
          pricable_items_count: 127,
        },
        {
          at: '2026-10-12T15:30:45Z',
          total_value_cents: 500000,
          complete: true,
          priced_items_count: 127,
          pricable_items_count: 127,
        },
      ],
    },
    items_count: 127,
    avg_item_value_cents: 3937,
    priciest_item: {
      market_hash_name: '★ Karambit | Crimson Web',
      metadata: {
        weapon_type: 'Knives',
        item_name: 'Crimson Web',
        category: 'Knives',
        condition: 'Factory New',
        stattrak: false,
        icon_url: null,
        rarity: 'Covert',
      },
      current_price_cents: 250000,
      price_updated_at: '2026-10-12T15:30:45Z',
    },
    rarity_breakdown: [{ tier: 'gold', count: 1, percent: 0.8 }],
    top_items: {
      meta: { page: 1, per_page: 12, total_count: 1, total_pages: 1 },
      entries: [
        {
          market_hash_name: 'AK-47 | Redline',
          metadata: {
            weapon_type: 'AK-47',
            item_name: 'Redline',
            category: 'Rifles',
            condition: 'Field-Tested',
            stattrak: false,
            icon_url: 'https://x/icon.png',
            rarity: 'Classified',
          },
          current_price_cents: 4218,
          change_24h_cents: 130,
          change_24h_percent: 3.18,
          price_updated_at: '2026-10-12T15:30:45Z',
          trend_7d: [{ at: '2026-10-11T00:00:00Z', price_cents: 4088 }],
        },
      ],
    },
    ...overrides,
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useInventoryDetail', () => {
  test('fetches the detail payload with no auth header and maps snake_case to camelCase', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      useInventoryDetail('http://fetcher.test', '76561198000000001', {
        period: '7d',
        sort: 'price_desc',
        page: 1,
        perPage: 12,
      }),
    )

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/public/inventories/76561198000000001?period=7d&sort=price_desc&page=1&per_page=12',
      expect.anything(),
    )
    const [, options] = fetchMock.mock.calls[0]
    expect(options.headers?.Authorization).toBeUndefined()

    const { data } = result.current
    expect(data.steamId).toBe('76561198000000001')
    expect(data.portfolio).toMatchObject({
      totalValueCents: 500000,
      changeCents: 12500,
      changePercent: 2.5,
      complete: true,
      pricedItemsCount: 127,
      pricableItemsCount: 127,
      changePartial: false,
      changeAvailable: true,
      changeBasisAt: new Date('2026-10-05T15:30:45Z').getTime(),
      oldestPriceAt: new Date('2026-10-12T15:30:45Z').getTime(),
    })
    expect(data.portfolio.history).toEqual([
      {
        at: new Date('2026-10-05T15:30:45Z').getTime(),
        value: 487500,
        complete: true,
        pricedItemsCount: 127,
        pricableItemsCount: 127,
      },
      {
        at: new Date('2026-10-12T15:30:45Z').getTime(),
        value: 500000,
        complete: true,
        pricedItemsCount: 127,
        pricableItemsCount: 127,
      },
    ])
    expect(data.priciestItem).toEqual({
      marketHashName: '★ Karambit | Crimson Web',
      weaponType: 'Knives',
      itemName: 'Crimson Web',
      condition: 'Factory New',
      stattrak: false,
      iconUrl: null,
      currentPriceCents: 250000,
      change24hCents: 0,
      change24hPercent: 0,
      priceUpdatedAt: new Date('2026-10-12T15:30:45Z').getTime(),
      trendPoints: [],
    })
    expect(data.topItems.entries[0]).toEqual({
      marketHashName: 'AK-47 | Redline',
      weaponType: 'AK-47',
      itemName: 'Redline',
      condition: 'Field-Tested',
      stattrak: false,
      iconUrl: 'https://x/icon.png',
      currentPriceCents: 4218,
      change24hCents: 130,
      change24hPercent: 3.18,
      priceUpdatedAt: new Date('2026-10-12T15:30:45Z').getTime(),
      trendPoints: [{ at: new Date('2026-10-11T00:00:00Z').getTime(), priceCents: 4088 }],
    })
  })

  test('priciest_item: null maps to priciestItem: null', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload({ priciest_item: null }))),
    )

    const { result } = renderHook(() =>
      useInventoryDetail('http://fetcher.test', '76561198000000001', {
        period: '7d',
        sort: 'price_desc',
        page: 1,
        perPage: 12,
      }),
    )

    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(result.current.data.priciestItem).toBeNull()
  })

  test('re-fetches when period, sort, or page changes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook(
      ({ period }) =>
        useInventoryDetail('http://fetcher.test', '76561198000000001', {
          period,
          sort: 'price_desc',
          page: 1,
          perPage: 12,
        }),
      { initialProps: { period: '7d' } },
    )

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    rerender({ period: '30d' })
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    expect(fetchMock).toHaveBeenLastCalledWith(
      expect.stringContaining('period=30d'),
      expect.anything(),
    )
  })

  test('a 404 response maps to a distinct not_found status, not the generic error status', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({ message: 'Inventory not found' }, 404)),
    )

    const { result } = renderHook(() =>
      useInventoryDetail('http://fetcher.test', 'unknown', {
        period: '7d',
        sort: 'price_desc',
        page: 1,
        perPage: 12,
      }),
    )

    await waitFor(() => expect(result.current.status).toBe('not_found'))
  })

  test('a generic failure surfaces the error status', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, 500)),
    )

    const { result } = renderHook(() =>
      useInventoryDetail('http://fetcher.test', '76561198000000001', {
        period: '7d',
        sort: 'price_desc',
        page: 1,
        perPage: 12,
      }),
    )

    await waitFor(() => expect(result.current.status).toBe('error'))
  })
})

describe('useInventoryDetail in demo mode', () => {
  test('uses the demo endpoint and bearer token', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      useInventoryDetail('http://fetcher.test', 'demo', {
        period: '7d',
        sort: 'price_desc',
        page: 1,
        perPage: 12,
        demo: true,
        demoToken: 'demo-token',
        apiBase: '/api/demo',
      }),
    )

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/demo/inventory_detail?period=7d&sort=price_desc&page=1&per_page=12',
      expect.anything(),
    )
    const [, options] = fetchMock.mock.calls[0]
    expect(options.headers.Authorization).toBe('Bearer demo-token')
  })
})
