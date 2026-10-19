import { render, screen, waitFor } from '@testing-library/react'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { Dashboard } from '../Dashboard'

const INVENTORY_BODY = {
  items_count: 1,
  items: [
    {
      market_hash_name: 'AK-47 | Redline (Field-Tested)',
      metadata: {
        weapon_type: 'AK-47',
        item_name: 'Redline',
        condition: 'Field-Tested',
        stattrak: false,
        marketable: true,
        icon_url: null,
      },
    },
  ],
}

function jsonResponse(body, ok = true) {
  return Promise.resolve({ ok, status: ok ? 200 : 500, json: () => Promise.resolve(body) })
}

function stubFetch(dynamicsResponse) {
  const fetchMock = vi.fn((url) => {
    if (url.endsWith('/api/v1/inventories/me')) return jsonResponse(INVENTORY_BODY)
    if (url.endsWith('/api/v1/item_prices/dynamics')) return dynamicsResponse()
    if (url.endsWith('/api/v1/item_prices/trend')) return jsonResponse({})
    if (url.includes('/api/v1/inventory_values')) return jsonResponse([])
    return jsonResponse({})
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('Dashboard', () => {
  test('shows a non-blocking notice when current prices fail to load', async () => {
    stubFetch(() => jsonResponse({}, false))
    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)

    await waitFor(() =>
      expect(screen.getByRole('alert')).toHaveTextContent(/couldn.t load current prices/i),
    )
    expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument()
  })

  test('does not show the notice when prices load successfully', async () => {
    stubFetch(() =>
      jsonResponse({
        prices: {
          'AK-47 | Redline (Field-Tested)': {
            current_price_cents: 3845,
            change_24h_cents: 0,
            change_24h_percent: 0,
          },
        },
        pending_count: 0,
      }),
    )
    render(<Dashboard fetcherUrl="http://fetcher.test" bridgeToken="token-123" />)

    await waitFor(() => expect(screen.getByText('$38.45')).toBeInTheDocument())
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})
