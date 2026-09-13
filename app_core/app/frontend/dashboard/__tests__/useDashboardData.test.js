import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useDashboardData } from '../hooks/useDashboardData'

const INVENTORY_BODY = {
  items_count: 1,
  items: [
    {
      market_hash_name: 'AK-47 | Redline (Field-Tested)',
      metadata: { weapon_type: 'AK-47', item_name: 'Redline', condition: 'Field-Tested', stattrak: false },
      current_price_cents: 3845,
      change_24h_cents: 120,
    },
  ],
}

const HISTORY_BODY = {
  items: [
    {
      market_hash_name: 'AK-47 | Redline (Field-Tested)',
      points: [{ at: new Date().toISOString(), price_cents: 3845, volume: 12 }],
    },
  ],
}

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useDashboardData', () => {
  test('merges inventory and price history, sending the bridge token on both calls', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse(INVENTORY_BODY))
      .mockImplementationOnce(() => jsonResponse(HISTORY_BODY))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(result.current.data.itemsCount).toBe(1)
    expect(result.current.data.items[0]).toMatchObject({
      marketHashName: 'AK-47 | Redline (Field-Tested)',
      weaponType: 'AK-47',
      currentPriceCents: 3845,
      changeCents: 120,
    })
    expect(result.current.data.portfolio.currentValueCents).toBe(3845)
    expect(result.current.data.marketVolume.countLast24h).toBe(12)

    const [inventoryCall, historyCall] = fetchMock.mock.calls
    expect(inventoryCall[0]).toBe('http://fetcher.test/api/v1/inventories/me')
    expect(inventoryCall[1].headers.Authorization).toBe('Bearer token-123')
    expect(historyCall[0]).toBe('http://fetcher.test/api/v1/price_histories')
    expect(historyCall[1].headers.Authorization).toBe('Bearer token-123')
  })

  test('surfaces an error state when the inventory call fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, false))
    )

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })

  test('surfaces an error state when the price-history call fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockImplementationOnce(() => jsonResponse(INVENTORY_BODY))
        .mockImplementationOnce(() => jsonResponse({}, false))
    )

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('error'))
  })

  test('skips the price-history call entirely when the inventory is empty', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse({ items_count: 0, items: [] }))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(result.current.data.items).toEqual([])
  })
})
