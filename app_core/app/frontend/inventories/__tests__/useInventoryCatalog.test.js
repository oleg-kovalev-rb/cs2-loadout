import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useInventoryCatalog } from '../hooks/useInventoryCatalog'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

const rawInventory = {
  steam_id: '76561198000000001',
  total_value_cents: 500000,
  change_24h_cents: 12500,
  change_24h_percent: 2.5,
  items_count: 127,
  rarity_mix_percent: {
    gold: 0.8,
    covert: 5.5,
    classified: 8.3,
    restricted: 15.2,
    mil_spec: 22.1,
    industrial: 28.4,
    consumer: 19.7,
  },
  last_synced_at: '2026-10-12T15:30:45Z',
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useInventoryCatalog', () => {
  test('fetches the catalog with no auth header, mapping snake_case fields to camelCase', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() =>
      jsonResponse({
        meta: { page: 1, per_page: 24, total_count: 1, total_pages: 1 },
        inventories: [rawInventory],
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      useInventoryCatalog('http://fetcher.test', { page: 1, sort: 'value_desc' }),
    )

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/public/inventories?page=1&per_page=24&sort=value_desc',
      expect.anything(),
    )
    const [, options] = fetchMock.mock.calls[0]
    expect(options.headers?.Authorization).toBeUndefined()
    expect(result.current.inventories).toEqual([
      {
        steamId: '76561198000000001',
        totalValueCents: 500000,
        change24hCents: 12500,
        change24hPercent: 2.5,
        itemsCount: 127,
        rarityMixPercent: rawInventory.rarity_mix_percent,
        lastSyncedAt: '2026-10-12T15:30:45Z',
      },
    ])
    expect(result.current.meta).toEqual({ page: 1, per_page: 24, total_count: 1, total_pages: 1 })
  })

  test('re-fetches when page or sort changes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse({ meta: {}, inventories: [] }))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook(
      ({ page, sort }) => useInventoryCatalog('http://fetcher.test', { page, sort }),
      {
        initialProps: { page: 1, sort: 'value_desc' },
      },
    )

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    rerender({ page: 2, sort: 'value_desc' })
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))

    rerender({ page: 2, sort: 'items_desc' })
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(3))
    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://fetcher.test/api/public/inventories?page=2&per_page=24&sort=items_desc',
      expect.anything(),
    )
  })

  test('surfaces an error status when the fetch fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, false)),
    )

    const { result } = renderHook(() =>
      useInventoryCatalog('http://fetcher.test', { page: 1, sort: 'value_desc' }),
    )

    await waitFor(() => expect(result.current.status).toBe('error'))
  })
})
