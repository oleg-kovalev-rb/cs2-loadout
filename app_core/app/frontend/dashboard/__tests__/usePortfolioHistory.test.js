import { renderHook, waitFor, act } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { usePortfolioHistory } from '../hooks/usePortfolioHistory'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

function payload(overrides = {}) {
  return {
    current: {
      total_value_cents: 150000,
      items_count: 10,
      pricable_items_count: 10,
      priced_items_count: 10,
      complete: true,
      oldest_price_at: '2026-10-18T09:00:00Z',
    },
    history: [
      {
        at: '2026-09-01T00:00:00Z',
        total_value_cents: 145000,
        complete: true,
        priced_items_count: 10,
        pricable_items_count: 10,
      },
      {
        at: '2026-10-18T12:00:00Z',
        total_value_cents: 150000,
        complete: true,
        priced_items_count: 10,
        pricable_items_count: 10,
      },
    ],
    change: {
      cents: 5000,
      percent: 3.45,
      basis_at: '2026-09-01T00:00:00Z',
      partial: false,
      available: true,
    },
    ...overrides,
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('usePortfolioHistory', () => {
  test('maps the current snapshot, history, and change', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(payload()))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      usePortfolioHistory('http://fetcher.test', 'token-123', '30d'),
    )

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/v1/inventory_values?period=30d',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Bearer token-123' }),
      }),
    )
    expect(result.current.current).toEqual({
      totalValueCents: 150000,
      itemsCount: 10,
      pricableItemsCount: 10,
      pricedItemsCount: 10,
      complete: true,
      oldestPriceAt: new Date('2026-10-18T09:00:00Z').getTime(),
    })
    expect(result.current.series).toEqual([
      {
        at: new Date('2026-09-01T00:00:00Z').getTime(),
        value: 145000,
        complete: true,
        pricedItemsCount: 10,
        pricableItemsCount: 10,
      },
      {
        at: new Date('2026-10-18T12:00:00Z').getTime(),
        value: 150000,
        complete: true,
        pricedItemsCount: 10,
        pricableItemsCount: 10,
      },
    ])
    expect(result.current.change).toEqual({
      cents: 5000,
      percent: 3.45,
      basisAt: new Date('2026-09-01T00:00:00Z').getTime(),
      partial: false,
      available: true,
    })
  })

  test('re-fetches when the period changes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(payload()))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook(
      ({ period }) => usePortfolioHistory('http://fetcher.test', 'token-123', period),
      { initialProps: { period: '30d' } },
    )

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    rerender({ period: '7d' })

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    expect(fetchMock).toHaveBeenLastCalledWith(
      'http://fetcher.test/api/v1/inventory_values?period=7d',
      expect.anything(),
    )
  })

  test('retries while the valuation is incomplete and stops once it is complete', async () => {
    vi.useFakeTimers()
    const incomplete = payload({
      current: { ...payload().current, complete: false, priced_items_count: 5 },
      change: { ...payload().change, available: false, partial: true },
    })
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse(incomplete))
      .mockImplementationOnce(() => jsonResponse(payload()))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      usePortfolioHistory('http://fetcher.test', 'token-123', '30d'),
    )

    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(result.current.current.complete).toBe(false)

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(result.current.current.complete).toBe(true)

    await act(async () => {
      await vi.advanceTimersByTimeAsync(120000)
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  test('retries while the skeleton inventory sync has not created UserInventory yet, then settles', async () => {
    vi.useFakeTimers()
    const empty = payload({
      current: null,
      history: [],
      change: {
        cents: 0,
        percent: 0,
        basis_at: null,
        partial: false,
        available: false,
      },
    })
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse(empty))
      .mockImplementationOnce(() => jsonResponse(payload()))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      usePortfolioHistory('http://fetcher.test', 'token-123', '30d'),
    )

    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(result.current.current).toBeNull()

    await act(async () => {
      await vi.advanceTimersByTimeAsync(3000)
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(result.current.current.complete).toBe(true)
  })

  test('surfaces an error status when the fetch fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, false)),
    )

    const { result } = renderHook(() =>
      usePortfolioHistory('http://fetcher.test', 'token-123', '30d'),
    )

    await waitFor(() => expect(result.current.status).toBe('error'))
  })
})
