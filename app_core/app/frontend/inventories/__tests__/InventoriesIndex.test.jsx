import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { InventoriesIndex } from '../InventoriesIndex'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

function page(overrides = {}) {
  return {
    meta: { page: 1, per_page: 24, total_count: 2, total_pages: 1 },
    inventories: [
      {
        steam_id: '76561198000000001',
        total_value_cents: 500000,
        change_24h_cents: 12500,
        change_24h_percent: 2.5,
        items_count: 127,
        rarity_mix_percent: {
          gold: 1,
          covert: 1,
          classified: 1,
          restricted: 1,
          mil_spec: 1,
          industrial: 1,
          consumer: 94,
        },
        last_synced_at: '2026-10-12T15:30:45Z',
      },
      {
        steam_id: '76561198000000002',
        total_value_cents: 100000,
        change_24h_cents: -500,
        change_24h_percent: -0.5,
        items_count: 40,
        rarity_mix_percent: {
          gold: 0,
          covert: 0,
          classified: 0,
          restricted: 0,
          mil_spec: 0,
          industrial: 0,
          consumer: 100,
        },
        last_synced_at: '2026-10-12T14:00:00Z',
      },
    ],
    ...overrides,
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('InventoriesIndex', () => {
  test('loads the catalog with no auth header and renders a card per inventory', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(page()))
    vi.stubGlobal('fetch', fetchMock)

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)

    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/public/inventories?page=1&per_page=24&sort=value_desc',
      expect.anything(),
    )
    const [, options] = fetchMock.mock.calls[0]
    expect(options.headers?.Authorization).toBeUndefined()

    expect(screen.getByText('#1')).toBeInTheDocument()
    expect(screen.getByText('#2')).toBeInTheDocument()
  })

  test('changing sort re-fetches with the new sort and resets to page 1', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(page()))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    await user.click(screen.getByRole('button', { name: /sort:/i }))
    await user.click(screen.getByRole('button', { name: 'Item count' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenLastCalledWith(
        'http://fetcher.test/api/public/inventories?page=1&per_page=24&sort=items_desc',
        expect.anything(),
      ),
    )
  })

  test('an empty catalog renders the empty state instead of a card grid', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() =>
        jsonResponse(
          page({
            inventories: [],
            meta: { page: 1, per_page: 24, total_count: 0, total_pages: 0 },
          }),
        ),
      ),
    )

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)

    await waitFor(() => expect(screen.getByText(/no public inventories/i)).toBeInTheDocument())
    expect(screen.queryAllByRole('link')).toHaveLength(0)
  })

  test('the search field is present but disabled', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(page())),
    )

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    expect(screen.getByPlaceholderText(/coming soon/i)).toBeDisabled()
  })
})
