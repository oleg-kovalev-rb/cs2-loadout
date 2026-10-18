import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { UserInventoriesPage } from '../pages/UserInventoriesPage'

const FETCHER_URL = 'https://fetcher.test'
const BRIDGE_TOKEN = 'token-123'

function inventoryFixture(overrides = {}) {
  return {
    steam_id: '76561198012345678',
    items_count: 3,
    total_value_cents: 120430,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-10-11T06:00:00Z',
    ...overrides,
  }
}

function listResponse(user_inventories, meta = {}) {
  return {
    meta: { total_count: user_inventories.length, total_pages: 1, ...meta },
    user_inventories,
  }
}

function jsonResponse(body, ok = true, status = ok ? 200 : 422) {
  return Promise.resolve({ ok, status, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('UserInventoriesPage', () => {
  test('loads and renders the list, showing an em dash when total_value_cents is null', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockReturnValue(
          jsonResponse(
            listResponse([
              inventoryFixture(),
              inventoryFixture({ steam_id: '2', total_value_cents: null }),
            ]),
          ),
        ),
    )

    render(<UserInventoriesPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())
    expect(screen.getByText('$1,204.30')).toBeInTheDocument()
    expect(screen.getByText('—')).toBeInTheDocument()
  })

  test('renders a real $0.00 distinctly from a null (never-synced) value', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockReturnValue(jsonResponse(listResponse([inventoryFixture({ total_value_cents: 0 })]))),
    )

    render(<UserInventoriesPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())
    expect(screen.getByText('$0.00')).toBeInTheDocument()
    expect(screen.queryByText('—')).not.toBeInTheDocument()
  })

  test('expanding a row fetches the detail and shows items, truncating past 2', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn((url) => {
      if (url.includes('/user_inventories/76561198012345678') && !url.includes('bulk')) {
        return jsonResponse({
          user_inventory: {
            ...inventoryFixture(),
            items: [
              {
                market_hash_name: 'AK-47 | Redline (Field-Tested)',
                added_at: '2025-03-15T00:00:00Z',
              },
              { market_hash_name: 'M4A4 | Howl (Minimal Wear)', added_at: '2025-01-03T00:00:00Z' },
              {
                market_hash_name: 'AWP | Dragon Lore (Factory New)',
                added_at: '2025-01-01T00:00:00Z',
              },
            ],
          },
        })
      }
      return jsonResponse(listResponse([inventoryFixture()]))
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<UserInventoriesPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: /Show items for 76561198012345678/ }))

    await waitFor(() =>
      expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument(),
    )
    expect(screen.getByText('M4A4 | Howl (Minimal Wear)')).toBeInTheDocument()
    expect(screen.queryByText('AWP | Dragon Lore (Factory New)')).not.toBeInTheDocument()
    expect(screen.getByText('…and 1 more')).toBeInTheDocument()
  })

  test('selecting rows enables the bulk cache button, which fires immediately with no submenu', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn((url) => {
      if (url.endsWith('/bulk_warm_cache'))
        return jsonResponse({ warmed_steam_ids: ['76561198012345678'], message: 'ok' })
      return jsonResponse(listResponse([inventoryFixture()]))
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<UserInventoriesPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())

    const rowCheckbox = screen
      .getAllByRole('checkbox')
      .find((el) => el.className.includes('row-check'))
    await user.click(rowCheckbox)

    const cacheButton = screen.getByRole('button', { name: 'Warm cache' })
    expect(cacheButton).toBeEnabled()
    await user.click(cacheButton)

    await waitFor(() => {
      const call = fetchMock.mock.calls.find(([url]) => url.endsWith('/bulk_warm_cache'))
      expect(call).toBeTruthy()
      expect(JSON.parse(call[1].body)).toEqual({ steam_ids: ['76561198012345678'] })
    })
  })

  test('sync now calls the member action', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn((url) => {
      if (url.endsWith('/sync')) return jsonResponse({ message: 'Inventory synced' })
      return jsonResponse(listResponse([inventoryFixture()]))
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<UserInventoriesPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Sync inventory now' }))

    await waitFor(() =>
      expect(
        fetchMock.mock.calls.some(
          ([url]) => url === `${FETCHER_URL}/api/admin/user_inventories/76561198012345678/sync`,
        ),
      ).toBe(true),
    )
  })

  test('deleting calls DELETE and refetches', async () => {
    const user = userEvent.setup()
    let listCallCount = 0
    const fetchMock = vi.fn((url, options) => {
      if (options?.method === 'DELETE') return jsonResponse({ message: 'Deleted' })
      listCallCount += 1
      return jsonResponse(listResponse([inventoryFixture()]))
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<UserInventoriesPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Delete 76561198012345678' }))

    await waitFor(() => expect(listCallCount).toBe(2))
    const deleteCall = fetchMock.mock.calls.find(([, options]) => options?.method === 'DELETE')
    expect(deleteCall[0]).toBe(`${FETCHER_URL}/api/admin/user_inventories/76561198012345678`)
  })
})
