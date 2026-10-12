import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { Dashboard } from '../Dashboard'

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

const ITEM_NAME = 'AK-47 | Redline (Field-Tested)'

const INVENTORY_BODY = {
  items_count: 1,
  items: [
    {
      market_hash_name: ITEM_NAME,
      metadata: { weapon_type: 'AK-47', item_name: 'Redline', condition: 'Field-Tested', stattrak: false },
    },
  ],
}

const DYNAMICS_BODY = {
  [ITEM_NAME]: { current_price_cents: 4000, change_24h_cents: 300, change_24h_percent: 8.11 },
}

const TREND_BODY = {
  [ITEM_NAME]: [{ at: '2026-10-01T00:00:00Z', price_cents: 3800, volume: 5 }],
}

// Dashboard.jsx wires five concurrent/near-concurrent fetches (skeleton,
// dynamics, trend, portfolio history, and — once an item is selected —
// item history). The mock routes by request URL instead of resolving a
// fixed sequence, per react-dashboard.md's "Multi-source orchestration
// tests" pattern.
function fetchMockRoutingBy(overrides = {}) {
  return vi.fn((url) => {
    if (url.includes('/inventories/me')) return overrides.inventory ?? jsonResponse(INVENTORY_BODY)
    if (url.includes('/item_prices/dynamics')) return overrides.dynamics ?? jsonResponse(DYNAMICS_BODY)
    if (url.includes('/item_prices/trend')) return overrides.trend ?? jsonResponse(TREND_BODY)
    if (url.includes('/inventory_values')) return overrides.portfolio ?? jsonResponse([])
    if (url.includes('/history')) return overrides.history ?? jsonResponse([])
    return jsonResponse({})
  })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('Dashboard', () => {
  test('renders the skeleton while the inventory call is pending', async () => {
    const fetchMock = vi.fn((url) => (url.includes('/inventories/me') ? new Promise(() => {}) : jsonResponse({})))
    vi.stubGlobal('fetch', fetchMock)

    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)

    expect(screen.getByLabelText('Loading dashboard')).toBeInTheDocument()

    // usePortfolioHistory fires on mount regardless of the (never-resolving)
    // skeleton fetch — let its already-resolved response settle before the
    // test ends, so the resulting state update stays inside act().
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('/inventory_values'), expect.anything()))
  })

  test('renders an error message when the inventory call fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn((url) => (url.includes('/inventories/me') ? jsonResponse({}, false) : jsonResponse({})))
    )

    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)

    await waitFor(() => expect(screen.getByText(/Couldn.t load the dashboard/)).toBeInTheDocument())
    expect(screen.getByText(/failed: 500/)).toBeInTheDocument()
  })

  test('merges dynamics and trend data onto the rendered item once both resolve', async () => {
    vi.stubGlobal('fetch', fetchMockRoutingBy())

    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)

    await screen.findByText(/Redline/)
    await waitFor(() => expect(screen.getByText('$40.00')).toBeInTheDocument())
    expect(screen.getByText(/8\.1%/)).toBeInTheDocument()

    const sparklinePath = document.querySelector('.row-spark path')
    expect(sparklinePath.getAttribute('d')).toMatch(/^M/)
  })

  test('keeps the hero tile in sync with a selected item once its price arrives after selection', async () => {
    const user = userEvent.setup()
    let resolveDynamics
    vi.stubGlobal(
      'fetch',
      fetchMockRoutingBy({
        dynamics: new Promise((resolve) => {
          resolveDynamics = () => resolve({ ok: true, status: 200, json: () => Promise.resolve(DYNAMICS_BODY) })
        }),
      })
    )

    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)

    const row = await screen.findByRole('button', { name: /Redline/ })
    await user.click(row)

    expect(screen.getByRole('heading', { name: /AK-47 \| Redline/ })).toBeInTheDocument()
    expect(document.querySelector('.hero-value')).toHaveTextContent('—')

    resolveDynamics()
    await waitFor(() => expect(document.querySelector('.hero-value')).toHaveTextContent('$40.00'))
  })

  test('changing the range in portfolio mode refetches portfolio history with the new period', async () => {
    const user = userEvent.setup()
    const fetchMock = fetchMockRoutingBy()
    vi.stubGlobal('fetch', fetchMock)

    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)
    await screen.findByText(/Redline/)

    await user.click(screen.getByRole('button', { name: '30d' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        expect.stringMatching(/\/api\/v1\/inventory_values\?period=30d$/),
        expect.anything()
      )
    )
  })

  test('changing the range in item mode refetches item history with the new period', async () => {
    const user = userEvent.setup()
    const fetchMock = fetchMockRoutingBy()
    vi.stubGlobal('fetch', fetchMock)

    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)
    const row = await screen.findByRole('button', { name: /Redline/ })
    await user.click(row)

    await user.click(screen.getByRole('button', { name: '30d' }))

    await waitFor(() =>
      expect(fetchMock).toHaveBeenCalledWith(
        expect.stringMatching(/\/api\/v1\/item_prices\/.+\/history\?period=30d$/),
        expect.anything()
      )
    )
  })
})
