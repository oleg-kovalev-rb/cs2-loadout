import { renderHook, waitFor, act } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useItemPrices } from '../hooks/useItemPrices'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

const NAMES = ['AK-47 | Redline (Field-Tested)', 'AWP | Asiimov (Battle-Scarred)']

afterEach(() => {
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('useItemPrices', () => {
  test('does not fetch until names is populated', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() => useItemPrices('http://fetcher.test', 'token-123', []))

    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('fetches dynamics with no params and merges the response', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() =>
      jsonResponse({
        prices: {
          [NAMES[0]]: {
            current_price_cents: 3845,
            change_24h_cents: 120,
            change_24h_percent: 3.22,
            price_updated_at: '2026-10-18T09:00:00Z',
          },
        },
        pending_count: 0,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/v1/item_prices/dynamics',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Bearer token-123' }),
      }),
    )
    expect(result.current.pricesByName[NAMES[0]]).toEqual({
      currentPriceCents: 3845,
      change24hCents: 120,
      change24hPercent: 3.22,
      priceUpdatedAt: new Date('2026-10-18T09:00:00Z').getTime(),
    })
  })

  test('stops after the first fetch when nothing is pending, even if some owned names have no price', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn().mockImplementationOnce(() =>
      jsonResponse({
        prices: {
          [NAMES[0]]: { current_price_cents: 100, change_24h_cents: 0, change_24h_percent: 0 },
        },
        pending_count: 0,
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))

    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(result.current.status).toBe('success')
    expect(Object.keys(result.current.pricesByName)).toEqual([NAMES[0]])

    // NAMES[1] has no price, but the backend says it isn't pending (e.g. a
    // non-marketable or price_unavailable item) — no retries.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(120000)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('retries on the bounded schedule while prices are pending, and stops once none are', async () => {
    vi.useFakeTimers()
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() =>
        jsonResponse({
          prices: {
            [NAMES[0]]: { current_price_cents: 100, change_24h_cents: 0, change_24h_percent: 0 },
          },
          pending_count: 1,
        }),
      )
      .mockImplementationOnce(() =>
        jsonResponse({
          prices: {
            [NAMES[0]]: { current_price_cents: 100, change_24h_cents: 0, change_24h_percent: 0 },
            [NAMES[1]]: { current_price_cents: 200, change_24h_cents: 0, change_24h_percent: 0 },
          },
          pending_count: 0,
        }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))

    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(Object.keys(result.current.pricesByName)).toEqual([NAMES[0]])

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })

    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(Object.keys(result.current.pricesByName)).toHaveLength(2)

    // Nothing pending now — no further retries scheduled.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(120000)
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  test('stops retrying after 5 attempts even if prices are still pending', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn(() => jsonResponse({ prices: {}, pending_count: 1 }))
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))

    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)

    for (const delay of [3000, 6000, 12000, 24000, 45000]) {
      await act(async () => {
        await vi.advanceTimersByTimeAsync(delay)
      })
    }
    expect(fetchMock).toHaveBeenCalledTimes(6)

    await act(async () => {
      await vi.advanceTimersByTimeAsync(120000)
    })
    expect(fetchMock).toHaveBeenCalledTimes(6)
  })

  test('surfaces an error when the first fetch fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, false)),
    )

    const { result } = renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })

  test('keeps the loaded prices and success status when a retry fails', async () => {
    vi.useFakeTimers()
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() =>
        jsonResponse({
          prices: {
            [NAMES[0]]: { current_price_cents: 100, change_24h_cents: 0, change_24h_percent: 0 },
          },
          pending_count: 1,
        }),
      )
      .mockRejectedValueOnce(new Error('network down'))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))

    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(result.current.status).toBe('success')

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })

    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(result.current.status).toBe('success')
    expect(result.current.pricesByName[NAMES[0]]).toEqual({
      currentPriceCents: 100,
      change24hCents: 0,
      change24hPercent: 0,
      priceUpdatedAt: null,
    })
  })

  test('clears pending timers on unmount', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn(() => jsonResponse({ prices: {}, pending_count: 1 }))
    vi.stubGlobal('fetch', fetchMock)

    const { unmount } = renderHook(() => useItemPrices('http://fetcher.test', 'token-123', NAMES))
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)

    unmount()
    await act(async () => {
      await vi.advanceTimersByTimeAsync(120000)
    })

    expect(fetchMock).toHaveBeenCalledTimes(1)
  })
})
