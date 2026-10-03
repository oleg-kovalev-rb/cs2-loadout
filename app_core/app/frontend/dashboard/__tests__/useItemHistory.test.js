import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useItemHistory } from '../hooks/useItemHistory'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useItemHistory', () => {
  test('does not fetch when marketHashName is null', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() => useItemHistory('http://fetcher.test', 'token-123', null, '30d'))

    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('fetches on demand, URL-encoding the market_hash_name, and shows a pending state while in flight', async () => {
    const at = '2026-09-01T00:00:00Z'
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse([{ at, price_cents: 3845, volume: 12 }]))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemHistory('http://fetcher.test', 'token-123', 'AK-47 | Redline (Field-Tested)', '30d'))

    expect(result.current.status).toBe('pending')

    await waitFor(() => expect(result.current.status).toBe('ready'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/v1/item_prices/AK-47%20%7C%20Redline%20(Field-Tested)/history?period=30d',
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer token-123' }) })
    )
    expect(result.current.series).toEqual([{ at: new Date(at).getTime(), value: 3845 }])
  })

  test('re-fetches when the period changes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse([]))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook(
      ({ period }) => useItemHistory('http://fetcher.test', 'token-123', 'AK-47 | Redline (Field-Tested)', period),
      { initialProps: { period: '30d' } }
    )

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    rerender({ period: '7d' })

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
  })

  test('surfaces an error status when the fetch fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementationOnce(() => jsonResponse({}, false)))

    const { result } = renderHook(() => useItemHistory('http://fetcher.test', 'token-123', 'AK-47 | Redline (Field-Tested)', '30d'))

    await waitFor(() => expect(result.current.status).toBe('error'))
  })
})
