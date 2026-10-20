import { describe, test, expect, vi, afterEach } from 'vitest'
import { fetchJson } from '../utils/fetchJson'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('fetchJson', () => {
  test('returns the parsed body on success', async () => {
    const body = { data: 'value' }
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: () => Promise.resolve(body),
    })
    vi.stubGlobal('fetch', fetchMock)
    const options = { headers: { Accept: 'application/json' } }

    await expect(fetchJson('/api/items', options)).resolves.toEqual(body)
    expect(fetchMock).toHaveBeenCalledWith('/api/items', options)
  })

  test('uses the response body message for an HTTP error', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 422,
        json: () => Promise.resolve({ message: 'Unsupported sort: bogus' }),
      }),
    )

    await expect(fetchJson('/api/items')).rejects.toThrow('Unsupported sort: bogus')
  })

  test('falls back to the status when the error body has no message', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 500,
        json: () => Promise.reject(new Error('invalid json')),
      }),
    )

    await expect(fetchJson('/api/items')).rejects.toThrow('Request to /api/items failed: 500')
  })
})
