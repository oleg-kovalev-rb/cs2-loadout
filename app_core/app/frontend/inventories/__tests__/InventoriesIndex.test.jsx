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
        rarity_breakdown: [
          { tier: 'gold', count: 1, percent: 1.0 },
          { tier: 'covert', count: 1, percent: 1.0 },
          { tier: 'classified', count: 1, percent: 1.0 },
          { tier: 'restricted', count: 1, percent: 1.0 },
          { tier: 'mil_spec', count: 1, percent: 1.0 },
          { tier: 'industrial', count: 1, percent: 1.0 },
          { tier: 'consumer', count: 94, percent: 94.0 },
        ],
        last_synced_at: '2026-10-12T15:30:45Z',
      },
      {
        steam_id: '76561198000000002',
        total_value_cents: 100000,
        change_24h_cents: -500,
        change_24h_percent: -0.5,
        items_count: 40,
        rarity_breakdown: [
          { tier: 'gold', count: 0, percent: 0.0 },
          { tier: 'covert', count: 0, percent: 0.0 },
          { tier: 'classified', count: 0, percent: 0.0 },
          { tier: 'restricted', count: 0, percent: 0.0 },
          { tier: 'mil_spec', count: 0, percent: 0.0 },
          { tier: 'industrial', count: 0, percent: 0.0 },
          { tier: 'consumer', count: 40, percent: 100.0 },
        ],
        last_synced_at: '2026-10-12T14:00:00Z',
      },
    ],
    ...overrides,
  }
}

// The island now makes two calls: the app_fetcher catalog (absolute URL)
// and the app_core profile enrichment (relative URL). Dispatch by URL.
function mockFetch({ pageBody = page(), profilesBody = { profiles: {} } } = {}) {
  return vi.fn().mockImplementation((url) => {
    if (String(url).startsWith('/inventories/profiles')) return jsonResponse(profilesBody)
    return jsonResponse(pageBody)
  })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('InventoriesIndex', () => {
  test('loads the catalog with no auth header and renders a card per inventory', async () => {
    const fetchMock = mockFetch()
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

  test('enriches cards with the app_core profile map for the page steam_ids', async () => {
    const fetchMock = mockFetch({
      profilesBody: {
        profiles: { '76561198000000001': { nickname: 'Ada', avatar_url: 'https://x/a.png' } },
      },
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)

    await waitFor(() => expect(screen.getByText('Ada')).toBeInTheDocument())

    expect(fetchMock).toHaveBeenCalledWith(
      '/inventories/profiles?steam_ids[]=76561198000000001&steam_ids[]=76561198000000002',
      expect.anything(),
    )
    // The second inventory has no profile, so it keeps its steam_id.
    expect(screen.getByText('76561198000000002')).toBeInTheDocument()
  })

  test('changing sort re-fetches with the new sort and resets to page 1', async () => {
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    await user.click(screen.getByRole('button', { name: /sort:/i }))
    await user.click(screen.getByRole('button', { name: 'Items, high to low' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        'http://fetcher.test/api/public/inventories?page=1&per_page=24&sort=items_desc',
        expect.anything(),
      ),
    )
  })

  test('paginates with the 1-based API page without translation', async () => {
    const fetchMock = vi.fn().mockImplementation((url) => {
      if (String(url).startsWith('/inventories/profiles')) {
        return jsonResponse({ profiles: {} })
      }
      const pageNumber = Number(new URL(url).searchParams.get('page'))
      return jsonResponse(
        page({
          meta: { page: pageNumber, per_page: 24, total_count: 48, total_pages: 2 },
        }),
      )
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    expect(screen.getByText('1 / 2')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Next page' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('page=2'), expect.anything()),
    )
    expect(screen.getByText('2 / 2')).toBeInTheDocument()
  })

  test('an empty catalog renders the empty state instead of a card grid', async () => {
    vi.stubGlobal(
      'fetch',
      mockFetch({
        pageBody: page({
          inventories: [],
          meta: { page: 1, per_page: 24, total_count: 0, total_pages: 0 },
        }),
      }),
    )

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)

    await waitFor(() => expect(screen.getByText(/no public inventories/i)).toBeInTheDocument())
    expect(screen.queryAllByRole('link')).toHaveLength(0)
  })

  test('the search field is present but disabled', async () => {
    vi.stubGlobal('fetch', mockFetch())

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    expect(screen.getByPlaceholderText(/coming soon/i)).toBeDisabled()
  })
})

describe('InventoriesIndex in demo mode', () => {
  const demoSummary = {
    steam_id: 'demo',
    total_value_cents: 250000,
    change_24h_cents: 5000,
    change_24h_percent: 2.0,
    items_count: 20,
    rarity_breakdown: [{ tier: 'covert', count: 20, percent: 100.0 }],
    last_synced_at: '2026-10-20T15:30:45Z',
  }

  test('renders the demo card first and keeps the public list unauthenticated', async () => {
    const fetchMock = vi.fn().mockImplementation((url) => {
      if (String(url).startsWith('/inventories/profiles')) return jsonResponse({ profiles: {} })
      if (String(url).includes('/api/demo/inventory_summary')) return jsonResponse(demoSummary)
      return jsonResponse(page())
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" demo demoToken="demo-token" />)

    await waitFor(() => expect(screen.getByText('My account')).toBeInTheDocument())
    await waitFor(() => expect(screen.getByText('#2')).toBeInTheDocument())

    const demoCall = fetchMock.mock.calls.find(([url]) =>
      String(url).includes('/api/demo/inventory_summary'),
    )
    const publicCall = fetchMock.mock.calls.find(([url]) =>
      String(url).includes('/api/public/inventories'),
    )
    const demoCard = screen.getByRole('link', { name: /My account/ })

    expect(demoCall?.[1].headers.Authorization).toBe('Bearer demo-token')
    expect(publicCall?.[1].headers?.Authorization).toBeUndefined()
    expect(demoCard).toHaveAttribute('href', '/demo/inventory')
    expect(demoCard).toHaveClass('inv-card-demo')
    expect(screen.getAllByRole('link')[0]).toBe(demoCard)
    expect(screen.getAllByText('Demo').length).toBeGreaterThan(0)
    expect(screen.getByText('#1')).toBeInTheDocument()
    expect(screen.getByText('#2')).toBeInTheDocument()
  })

  test('does not fetch the demo summary when demo mode is off', async () => {
    const fetchMock = mockFetch()
    vi.stubGlobal('fetch', fetchMock)

    render(<InventoriesIndex fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(2))

    expect(
      fetchMock.mock.calls.some(([url]) => String(url).includes('/api/demo/inventory_summary')),
    ).toBe(false)
  })
})
