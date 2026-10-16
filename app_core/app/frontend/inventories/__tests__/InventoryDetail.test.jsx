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
      range: '7d',
      history: [
        { at: '2026-10-05T15:30:45Z', total_value_cents: 487500 },
        { at: '2026-10-12T15:30:45Z', total_value_cents: 500000 },
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
      'http://fetcher.test/api/public/inventories/76561198000000001?range=7d&items_sort=price_desc&items_page=1&items_per_page=12',
      expect.anything(),
    )
    const [, options] = fetchMock.mock.calls[0]
    expect(options.headers?.Authorization).toBeUndefined()

    expect(screen.getByText('$5,000.00')).toBeInTheDocument() // total_value_cents
    expect(screen.getByText('127')).toBeInTheDocument() // items_count
    expect(screen.getByText(/Crimson Web/)).toBeInTheDocument() // priciest item note
    expect(container.querySelector('.hero-delta')).toHaveClass('is-up')
  })

  test('a zero change renders the total value with no delta badge', async () => {
    const payload = detailPayload({
      portfolio: {
        total_value_cents: 500000,
        change_cents: 0,
        change_percent: 0,
        range: '7d',
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

  test('changing the range re-fetches with the new range', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: '24h' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenLastCalledWith(
        expect.stringContaining('range=24h'),
        expect.anything(),
      ),
    )
  })

  test('changing the items sort re-fetches and resets to items_page=1', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(detailPayload()))
    vi.stubGlobal('fetch', fetchMock)
    const user = userEvent.setup()

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: /sort:/i }))
    await user.click(screen.getByRole('button', { name: 'Name' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenLastCalledWith(
        expect.stringContaining('items_sort=name_asc&items_page=1'),
        expect.anything(),
      ),
    )
  })

  test('priciest_item: null renders a graceful "no priced items" note instead of crashing', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockImplementationOnce(() => jsonResponse(detailPayload({ priciest_item: null }))),
    )

    render(<InventoryDetail fetcherUrl="http://fetcher.test" steamId="76561198000000001" />)

    await waitFor(() => expect(screen.getByText(/no priced items yet/i)).toBeInTheDocument())
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
