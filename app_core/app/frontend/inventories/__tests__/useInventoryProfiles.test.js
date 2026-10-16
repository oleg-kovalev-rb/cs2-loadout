import { renderHook, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useInventoryProfiles } from '../hooks/useInventoryProfiles'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useInventoryProfiles', () => {
  test('fetches the profile map for the given steam_ids', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() =>
        jsonResponse({ profiles: { 1: { nickname: 'Ada', avatar_url: 'x' } } }),
      )
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useInventoryProfiles(['1', '2']))

    await waitFor(() => expect(result.current).toEqual({ 1: { nickname: 'Ada', avatarUrl: 'x' } }))
    expect(fetchMock).toHaveBeenCalledWith(
      '/inventories/profiles?steam_ids[]=1&steam_ids[]=2',
      expect.anything(),
    )
  })

  test('does not fetch for an empty id list', async () => {
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useInventoryProfiles([]))

    await waitFor(() => expect(result.current).toEqual({}))
    expect(fetchMock).not.toHaveBeenCalled()
  })

  test('degrades to an empty map when the request fails', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse({}, false))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useInventoryProfiles(['1']))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    expect(result.current).toEqual({})
  })

  test('re-fetches when the id list changes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse({ profiles: {} }))
    vi.stubGlobal('fetch', fetchMock)

    const { rerender } = renderHook(({ ids }) => useInventoryProfiles(ids), {
      initialProps: { ids: ['1'] },
    })

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    rerender({ ids: ['1', '2'] })
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
  })
})
