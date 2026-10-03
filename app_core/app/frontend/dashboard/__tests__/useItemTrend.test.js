import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useItemTrend } from '../hooks/useItemTrend'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

const NAMES = ['AK-47 | Redline (Field-Tested)']

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useItemTrend', () => {
  test('does not fetch until names is populated', () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() => useItemTrend('http://fetcher.test', 'token-123', []))

    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('fetches trend with no params and maps points per item', async () => {
    const at = new Date().toISOString()
    const fetchMock = vi.fn().mockImplementationOnce(() =>
      jsonResponse({ [NAMES[0]]: [{ at, price_cents: 3845, volume: 12 }] })
    )
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useItemTrend('http://fetcher.test', 'token-123', NAMES))

    await waitFor(() => expect(result.current.status).toBe('ready'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/v1/item_prices/trend',
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer token-123' }) })
    )
    expect(result.current.trendByName[NAMES[0]]).toEqual([{ at, priceCents: 3845, volume: 12 }])
  })

  test('surfaces an error status when the fetch fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementationOnce(() => jsonResponse({}, false)))

    const { result } = renderHook(() => useItemTrend('http://fetcher.test', 'token-123', NAMES))

    await waitFor(() => expect(result.current.status).toBe('error'))
  })
})
