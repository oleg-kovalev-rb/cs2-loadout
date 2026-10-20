import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useDemoInventory } from '../hooks/useDemoInventory'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

const SUMMARY = {
  steam_id: 'demo',
  total_value_cents: 500000,
  change_24h_cents: 12500,
  change_24h_percent: 2.5,
  items_count: 20,
  rarity_breakdown: [{ tier: 'covert', count: 20, percent: 100.0 }],
  last_synced_at: '2026-10-20T15:30:45Z',
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useDemoInventory', () => {
  test('fetches the demo summary with the demo bearer token', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(SUMMARY))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useDemoInventory('http://fetcher.test', true, 'demo-token'))

    await waitFor(() => expect(result.current?.steamId).toBe('demo'))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/demo/inventory_summary',
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: 'Bearer demo-token' }),
      }),
    )
  })

  test('does nothing when demo mode is off', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() =>
      useDemoInventory('http://fetcher.test', false, 'demo-token'),
    )

    expect(result.current).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('degrades to no card when the demo summary fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({}, false)),
    )

    const { result } = renderHook(() => useDemoInventory('http://fetcher.test', true, 'demo-token'))

    await waitFor(() => expect(result.current).toBeNull())
  })
})
