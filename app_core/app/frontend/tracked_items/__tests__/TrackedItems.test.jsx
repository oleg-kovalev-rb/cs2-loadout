import { render, screen, fireEvent, within, waitFor, act } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { TrackedItems } from '../TrackedItems'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

function catalogBody(overrides = {}) {
  return {
    meta: {
      page: 1,
      per_page: 25,
      total_count: 2,
      total_pages: 1,
      gaining_count: 1,
      losing_count: 1,
      last_synced_at: '2026-10-12T10:00:00Z',
      ...overrides.meta,
    },
    items: overrides.items || [
      {
        market_hash_name: 'AK-47 | Redline (Field-Tested)',
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
        trend_7d: [{ at: '2026-10-10T00:00:00Z', price_cents: 4000 }],
      },
      {
        market_hash_name: 'AWP | Dragon Lore (Factory New)',
        metadata: {
          weapon_type: 'AWP',
          item_name: 'Dragon Lore',
          category: 'Rifles',
          condition: 'Factory New',
          stattrak: false,
          icon_url: null,
          rarity: 'Covert',
        },
        current_price_cents: 682050,
        change_24h_cents: -1100,
        change_24h_percent: -1.1,
        trend_7d: [],
      },
    ],
  }
}

afterEach(() => {
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('TrackedItems', () => {
  test('renders the stat strip and ticker rows from the fetched catalog', async () => {
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(catalogBody()))
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)

    expect(await screen.findByText('AK-47 | Redline', { exact: false })).toBeInTheDocument()
    expect(screen.getByText('AWP | Dragon Lore', { exact: false })).toBeInTheDocument()
    expect(screen.getByText('2')).toBeInTheDocument()
  })

  test('an item with no current price renders a placeholder and no delta badge', async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      jsonResponse(
        catalogBody({
          items: [
            {
              market_hash_name: 'Glock-18 | Fade (Factory New)',
              metadata: {
                weapon_type: 'Glock-18',
                item_name: 'Fade',
                category: 'Pistols',
                condition: 'Factory New',
                stattrak: false,
                icon_url: null,
                rarity: 'Classified',
              },
              current_price_cents: null,
              change_24h_cents: 0,
              change_24h_percent: 0,
              trend_7d: [],
            },
          ],
        }),
      ),
    )
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)

    const row = await screen.findByText('Glock-18 | Fade', { exact: false })
    const rowEl = row.closest('.ticker-row')
    expect(within(rowEl).getByText('—')).toBeInTheDocument()
    expect(within(rowEl).queryByText(/▲|▼/)).not.toBeInTheDocument()
  })

  test('toggling a category chip filters and resets to page 1', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(catalogBody()))
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    await user.click(screen.getByRole('button', { name: /filters/i }))
    await user.click(screen.getByRole('button', { name: 'Rifles' }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    const [url] = fetchMock.mock.calls[1]
    const params = new URL(url).searchParams
    expect(params.getAll('category[]')).toEqual(['Rifles'])
    expect(params.get('page')).toBe('1')
  })

  test('changing sort refetches with the new sort param', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(catalogBody()))
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    await user.click(screen.getByRole('button', { name: /sort:/i }))
    await user.click(screen.getByRole('button', { name: 'Price: low to high' }))

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    const [url] = fetchMock.mock.calls[1]
    expect(new URL(url).searchParams.get('sort')).toBe('price_asc')
  })

  test('switching Ticker to Grid re-renders without an extra fetch', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(catalogBody()))
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))
    expect(document.querySelector('.ticker-wrap')).not.toBeNull()

    await user.click(screen.getByRole('button', { name: 'Grid' }))

    expect(document.querySelector('.grid-view')).not.toBeNull()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  test('changing per-page resets to page 1 and requests the new size', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(catalogBody()))
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    await user.selectOptions(screen.getByLabelText(/per page/i), '50')

    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    const [url] = fetchMock.mock.calls[1]
    const params = new URL(url).searchParams
    expect(params.get('per_page')).toBe('50')
    expect(params.get('page')).toBe('1')
  })

  test('typing in search debounces before refetching with the latest value', async () => {
    vi.useFakeTimers()
    const fetchMock = vi.fn().mockImplementation(() => jsonResponse(catalogBody()))
    vi.stubGlobal('fetch', fetchMock)

    render(<TrackedItems fetcherUrl="http://fetcher.test" />)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(0)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)

    const input = screen.getByPlaceholderText(/search by weapon/i)
    fireEvent.change(input, { target: { value: 'red' } })
    await act(async () => {
      await vi.advanceTimersByTimeAsync(100)
    })
    fireEvent.change(input, { target: { value: 'redline' } })

    await act(async () => {
      await vi.advanceTimersByTimeAsync(100)
    })
    expect(fetchMock).toHaveBeenCalledTimes(1)

    await act(async () => {
      await vi.advanceTimersByTimeAsync(300)
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    const [url] = fetchMock.mock.calls[1]
    expect(new URL(url).searchParams.get('search')).toBe('redline')
  })
})
