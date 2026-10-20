import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { InventoryDetail } from '../InventoryDetail'

function jsonResponse(body, status = 200) {
  return Promise.resolve({ ok: status < 300, status, json: () => Promise.resolve(body) })
}

function detailPayload(overrides = {}) {
  return {
    steam_id: '76561198000000001',
    last_synced_at: '2026-10-12T15:30:45Z',
    portfolio: {
      total_value_cents: 500000,
      change_cents: 12500,
      change_percent: 2.5,
      change_basis_at: '2026-10-05T15:30:45Z',
      change_partial: false,
      change_available: true,
      complete: true,
      priced_items_count: 127,
      pricable_items_count: 127,
      oldest_price_at: '2026-10-12T15:30:45Z',
      period: '7d',
      history: [
        { at: '2026-10-05T15:30:45Z', total_value_cents: 487500, complete: true },
        { at: '2026-10-12T15:30:45Z', total_value_cents: 500000, complete: true },
      ],
    },
    items_count: 127,
    avg_item_value_cents: 3937,
    priciest_item: {
      market_hash_name: '★ Karambit | Crimson Web',
      metadata: {
        weapon_type: 'Knives',
        item_name: 'Crimson Web',
        category: 'Knives',
        condition: 'Factory New',
        stattrak: false,
        icon_url: null,
        rarity: 'Covert',
      },
      current_price_cents: 250000,
    },
    rarity_breakdown: [
      { tier: 'gold', count: 1, percent: 0.8 },
      { tier: 'covert', count: 7, percent: 5.5 },
    ],
    top_items: {
      meta: { page: 1, per_page: 12, total_count: 1, total_pages: 1 },
      entries: [
        {
          market_hash_name: 'AK-47 | Redline',
          metadata: {
            weapon_type: 'AK-47',
            item_name: 'Redline',
            category: 'Rifles',
            condition: 'Field-Tested',
            stattrak: false,
            icon_url: null,
            rarity: 'Classified',
          },
          current_price_cents: 4218,
          change_24h_cents: 130,
          change_24h_percent: 3.18,
          trend_7d: [],
        },
      ],
    },
    ...overrides,
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('InventoryDetail', () => {
  test('loads the detail payload with no auth header and renders the hero/stats/rarity/items', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)

    const { container } = render(
      <InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />,
    )

    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    expect(fetchMock).toHaveBeenCalledWith(
      'http://fetcher.test/api/public/inventories/76561198000000001?period=7d&sort=price_desc&page=1&per_page=12',
      expect.anything(),
    )
    const [, options] = fetchMock.mock.calls[0]
    expect(options.headers?.Authorization).toBeUndefined()

    expect(screen.getByText('$5,000.00')).toBeInTheDocument() // total_value_cents
    expect(screen.getByText('127')).toBeInTheDocument() // items_count
    expect(screen.getByText(/Crimson Web/)).toBeInTheDocument() // priciest item note
    expect(container.querySelector('.hero-delta')).toHaveClass('is-up')
  })

  test('an incomplete valuation shows the partial badge and no delta', async () => {
    const payload = detailPayload({
      portfolio: {
        ...detailPayload().portfolio,
        complete: false,
        priced_items_count: 100,
        pricable_items_count: 127,
        change_partial: true,
      },
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(payload)),
    )

    const { container } = render(
      <InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />,
    )

    await waitFor(() => expect(screen.getByText('100/127 priced')).toBeInTheDocument())
    expect(container.querySelector('.hero-delta')).not.toBeInTheDocument()
  })

  test('a partial-history change on a complete valuation hides the delta', async () => {
    const payload = detailPayload({
      portfolio: {
        ...detailPayload().portfolio,
        change_partial: true,
      },
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(payload)),
    )

    const { container } = render(
      <InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />,
    )

    await waitFor(() => expect(screen.getByText('Partial history')).toBeInTheDocument())
    expect(container.querySelector('.hero-delta')).not.toBeInTheDocument()
  })

  test('a zero change renders the total value with no delta badge', async () => {
    const payload = detailPayload({
      portfolio: {
        total_value_cents: 500000,
        change_cents: 0,
        change_percent: 0,
        period: '7d',
        history: [{ at: '2026-10-12T15:30:45Z', total_value_cents: 500000 }],
      },
    })
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(payload)),
    )

    const { container } = render(
      <InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />,
    )

    await waitFor(() => expect(screen.getByText('$5,000.00')).toBeInTheDocument())
    expect(container.querySelector('.hero-delta')).not.toBeInTheDocument()
  })

  test('changing the period re-fetches with the new period', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: '30d' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenLastCalledWith(
        expect.stringContaining('period=30d'),
        expect.anything(),
      ),
    )
  })

  test('changing the items sort re-fetches and resets to page=1', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: /sort:/i }))
    await user.click(screen.getByRole('button', { name: 'Name' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenLastCalledWith(
        expect.stringContaining('sort=name_asc&page=1'),
        expect.anything(),
      ),
    )
  })

  test('paginating the top items uses the 1-based items page directly', async () => {
    const fetchMock = vi.fn().mockImplementation((url) => {
      const pageNumber = Number(new URL(url).searchParams.get('page'))
      return jsonResponse(
        detailPayload({
          top_items: {
            ...detailPayload().top_items,
            meta: { page: pageNumber, per_page: 12, total_count: 24, total_pages: 2 },
          },
        }),
      )
    })
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    expect(screen.getByText('1 / 2')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Next page' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenLastCalledWith(
        expect.stringContaining('page=2'),
        expect.anything(),
      ),
    )
    expect(screen.getByText('2 / 2')).toBeInTheDocument()
  })

  test('priciest_item: null renders a graceful "no priced items" note instead of crashing', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload({ priciest_item: null }))),
    )

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)

    await waitFor(() => expect(screen.getByText(/no priced items yet/i)).toBeInTheDocument())
  })

  test('falls back to steam_id in the profile header when no profile is passed', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload())),
    )

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)

    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())
    expect(screen.getByText('76561198000000001')).toBeInTheDocument()
  })

  test('renders the enriched nickname/avatar in the profile header when a profile is passed', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload())),
    )

    const { container } = render(
      <InventoryDetail
        fetcherUrl="http://fetcher.test"
        steamId="76561198000000001"
        profile={{ nickname: 'Ada', avatarUrl: 'https://x/a.png' }}
      />,
    )

    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    expect(screen.getByText('Ada')).toBeInTheDocument()
    expect(container.querySelector('img.profile-head-avatar')).toHaveAttribute(
      'src',
      'https://x/a.png',
    )
  })

  test('a 404 renders the not-tracked state with a link back to the list', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse({ message: 'Inventory not found' }, 404)),
    )

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="unknown" />)

    await waitFor(() => expect(screen.getByText(/isn.t tracked/i)).toBeInTheDocument())
    expect(screen.getByRole('link', { name: /back to inventories/i })).toHaveAttribute(
      'href',
      '/inventories',
    )
  })
})

describe('InventoryDetail in demo mode', () => {
  test('renders the demo label and badge', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementation(() => jsonResponse(detailPayload())),
    )

    render(
      <InventoryDetail
        fetcherUrl="http://fetcher.test"
        steamId="demo"
        profile={{ nickname: 'My account' }}
        demo
        demoToken="demo-token"
        apiBase="/api/demo"
      />,
    )

    await waitFor(() => expect(screen.getByText(/Demo inventory/)).toBeInTheDocument())
    expect(screen.getByText('Demo')).toHaveClass('badge-demo')
    expect(screen.getByText('My account')).toBeInTheDocument()
  })
})
