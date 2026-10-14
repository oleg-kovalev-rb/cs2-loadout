import { describe, test, expect, vi, afterEach } from 'vitest'
import { adminGet, adminSend } from '../adminApi'

function jsonResponse(body, ok = true, status = ok ? 200 : 422) {
  return Promise.resolve({ ok, status, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('adminGet', () => {
  test('sends a Bearer-authenticated GET and returns the parsed JSON body', async () => {
    const fetchMock = vi.fn().mockReturnValue(jsonResponse({ items: [], meta: { page: 1 } }))
    vi.stubGlobal('fetch', fetchMock)

    const result = await adminGet('https://fetcher.test', 'token-123', '/api/admin/items')

    expect(result).toEqual({ items: [], meta: { page: 1 } })
    expect(fetchMock).toHaveBeenCalledWith(
      'https://fetcher.test/api/admin/items',
      expect.objectContaining({ headers: expect.objectContaining({ Authorization: 'Bearer token-123' }) })
    )
  })

  test('throws with the server message on a non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse({ message: 'Unauthorized' }, false, 401)))

    await expect(adminGet('https://fetcher.test', 'bad-token', '/api/admin/items')).rejects.toThrow('Unauthorized')
  })
})

describe('adminSend', () => {
  test('sends a JSON body with the given method', async () => {
    const fetchMock = vi.fn().mockReturnValue(jsonResponse({ item: { id: 1 } }, true, 201))
    vi.stubGlobal('fetch', fetchMock)

    const result = await adminSend('https://fetcher.test', 'token-123', 'POST', '/api/admin/items', {
      item: { market_hash_name: 'AWP | Asiimov' },
    })

    expect(result).toEqual({ item: { id: 1 } })
    const [url, options] = fetchMock.mock.calls[0]
    expect(url).toBe('https://fetcher.test/api/admin/items')
    expect(options.method).toBe('POST')
    expect(JSON.parse(options.body)).toEqual({ item: { market_hash_name: 'AWP | Asiimov' } })
  })

  test('sends no body when none is given', async () => {
    const fetchMock = vi.fn().mockReturnValue(jsonResponse({ message: 'Deleted' }))
    vi.stubGlobal('fetch', fetchMock)

    await adminSend('https://fetcher.test', 'token-123', 'DELETE', '/api/admin/items/1')

    const [, options] = fetchMock.mock.calls[0]
    expect(options.body).toBeUndefined()
  })

  test('throws with the server message on a non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse({ message: 'Validation failed' }, false, 422)))

    await expect(
      adminSend('https://fetcher.test', 'token-123', 'POST', '/api/admin/items', { market_hash_name: '' })
    ).rejects.toThrow('Validation failed')
  })
})
