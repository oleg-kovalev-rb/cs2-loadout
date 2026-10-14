import { renderHook, waitFor, act } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { useAdminList } from '../hooks/useAdminList'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('useAdminList', () => {
  test('starts loading, then resolves with the parsed body and meta', async () => {
    const body = { meta: { page: 1, per_page: 25, total_count: 2, total_pages: 1 }, items: [ { id: 1 }, { id: 2 } ] }
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse(body)))

    const { result } = renderHook(() => useAdminList('https://fetcher.test', 'token', '/api/admin/items', { page: 1, perPage: 25 }))

    expect(result.current.status).toBe('loading')

    await waitFor(() => expect(result.current.status).toBe('success'))

    expect(result.current.data).toEqual(body)
    expect(result.current.meta).toEqual(body.meta)
  })

  test('passes page/per_page as query params', async () => {
    const fetchMock = vi.fn().mockReturnValue(jsonResponse({ meta: {}, items: [] }))
    vi.stubGlobal('fetch', fetchMock)

    renderHook(() => useAdminList('https://fetcher.test', 'token', '/api/admin/items', { page: 3, perPage: 50 }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalled())
    const [url] = fetchMock.mock.calls[0]
    expect(url).toBe('https://fetcher.test/api/admin/items?page=3&per_page=50')
  })

  test('transitions to error status on a failed request', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse({ message: 'Unauthorized' }, false)))

    const { result } = renderHook(() => useAdminList('https://fetcher.test', 'token', '/api/admin/items', { page: 1, perPage: 25 }))

    await waitFor(() => expect(result.current.status).toBe('error'))
    expect(result.current.error).toBeInstanceOf(Error)
  })

  test('refetch triggers a new request', async () => {
    const fetchMock = vi.fn().mockReturnValue(jsonResponse({ meta: {}, items: [] }))
    vi.stubGlobal('fetch', fetchMock)

    const { result } = renderHook(() => useAdminList('https://fetcher.test', 'token', '/api/admin/items', { page: 1, perPage: 25 }))

    await waitFor(() => expect(result.current.status).toBe('success'))
    expect(fetchMock).toHaveBeenCalledTimes(1)

    act(() => result.current.refetch())

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
  })
})
