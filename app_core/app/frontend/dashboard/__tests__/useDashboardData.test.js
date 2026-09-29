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

function deferred() {
  let resolve
  const promise = new Promise((res) => {
    resolve = res
  })
  return { promise, resolve }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useDashboardData', () => {
  test('renders items with current prices as soon as the inventory call resolves, before history resolves', async () => {
    const history = deferred()
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse(INVENTORY_BODY))
      .mockImplementationOnce(() => history.promise)
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(result.current.historyStatus).toBe('pending')
    expect(result.current.data.items[0]).toMatchObject({
      marketHashName: 'AK-47 | Redline (Field-Tested)',
      currentPriceCents: 3845,
      priceHistory: [],
    })
    expect(result.current.data.portfolio.currentValueCents).toBe(3845)

    history.resolve(await jsonResponse(HISTORY_BODY))

    await waitFor(() => expect(result.current.historyStatus).toBe('ready'))
    expect(result.current.data.items[0].priceHistory).toHaveLength(1)
    expect(result.current.data.marketVolume.countLast24h).toBe(12)
  })

  test('keeps items visible when the price-history call fails', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse(INVENTORY_BODY))
      .mockImplementationOnce(() => jsonResponse({}, false))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.historyStatus).toBe('error'))
    expect(result.current.status).toBe('success')
    expect(result.current.data.items[0].currentPriceCents).toBe(3845)
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

  test('skips the price-history call entirely when the inventory is empty', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse({ items_count: 0, items: [] }))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDashboardData('http://fetcher.test', 'token-123'))

    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(result.current.historyStatus).toBe('ready')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(result.current.data.items).toEqual([])
  })
})
