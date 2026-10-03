import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { usePortfolioHistory } from '../hooks/usePortfolioHistory'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('usePortfolioHistory', () => {
  test('fetches inventory_values for the given period and maps points to {at, value}', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => jsonResponse([{ date: '2026-09-01', total_value_cents: 145000 }]))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => usePortfolioHistory('http://fetcher.test', 'token-123', '30d'))

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/v1/inventory_values?period=30d',
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer token-123' }) })
    )
    expect(result.current.series).toEqual([{ at: new Date('2026-09-01').getTime(), value: 145000 }])
  })

  test('re-fetches when the period changes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook(({ period }) => usePortfolioHistory('http://fetcher.test', 'token-123', period), {
      initialProps: { period: '30d' },
    })

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    rerender({ period: '7d' })

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    expect(fetchMock).toHaveBeenLastCalledWith('http://fetcher.test/api/v1/inventory_values?period=7d', expect.anything())
  })

  test('surfaces an error status when the fetch fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementationOnce(() => jsonResponse({}, false)))

    const { result } = renderHook(() => usePortfolioHistory('http://fetcher.test', 'token-123', '30d'))

    await waitFor(() => expect(result.current.status).toBe('error'))
  })
})
