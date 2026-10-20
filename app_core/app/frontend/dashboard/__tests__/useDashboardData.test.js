import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useDashboardData } from '../hooks/useDashboardData'

const INVENTORY_BODY = {
  items_count: 1,
  items: [
    {
      market_hash_name: 'AK-47 | Redline (Field-Tested)',
      price_unavailable: true,
      metadata: {
        weapon_type: 'AK-47',
        item_name: 'Redline',
        condition: 'Field-Tested',
        stattrak: false,
        marketable: true,
        icon_url: 'https://community.akamai.steamstatic.com/economy/image/abc123',
      },
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
  test('fetches only the skeleton, with no price fields, and maps items', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(INVENTORY_BODY))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/v1/inventories/me',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Bearer token-123' }),
      }),
    )
    expect(result.current.data.items[0]).toMatchObject({
      marketHashName: 'AK-47 | Redline (Field-Tested)',
      weaponType: 'AK-47',
      itemName: 'Redline',
      condition: 'Field-Tested',
      stattrak: false,
      marketable: true,
      priceUnavailable: true,
      iconUrl: 'https://community.akamai.steamstatic.com/economy/image/abc123',
      currentPriceCents: null,
      change24hCents: 0,
      change24hPercent: 0,
      trendPoints: [],
    })
  })

  test('surfaces an error state when the inventory call fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, false)),
    )

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })

  test('handles an empty inventory', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse({ items_count: 0, items: [] }))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(result.current.data.items).toEqual([])
  })
})

describe('useDashboardData in demo mode', () => {
  test('uses the provided api base and demo token', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse({ items_count: 0, items: [] }))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      useDashboardData('http://fetcher.test', 'demo-token', '/api/demo'),
    )

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/demo/inventories/me',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Bearer demo-token' }),
      }),
    )
  })
})
