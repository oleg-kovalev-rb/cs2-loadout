import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { PriceLogsPage } from '../pages/PriceLogsPage'

const FETCHER_URL = 'https://fetcher.test'
const BRIDGE_TOKEN = 'token-123'

function logFixture(overrides = {}) {
  return {
    id: 1,
    item_id: 7,
    market_hash_name: 'AK-47 | Redline',
    lowest_price_cents: 1208,
    median_price_cents: 1245,
    volume: 19,
    created_at: '2026-10-11T03:00:00Z',
    ...overrides,
  }
}

function listResponse(price_logs, meta = {}) {
  return { meta: { total_count: price_logs.length, total_pages: 1, ...meta }, price_logs }
}

function jsonResponse(body, ok = true, status = ok ? 200 : 422) {
  return Promise.resolve({ ok, status, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('PriceLogsPage', () => {
  test('loads and renders the list with formatted prices', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse(listResponse([logFixture()]))))

    render(<PriceLogsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())
    expect(screen.getByText('$12.08')).toBeInTheDocument()
    expect(screen.getByText('$12.45')).toBeInTheDocument()
    expect(screen.getByText('19')).toBeInTheDocument()
  })

  test('deleting a row calls DELETE on the nested route and refetches', async () => {
    const user = userEvent.setup()
    let listCallCount = 0
    const fetchMock = vi.fn((url, options) => {
      if (options?.method === 'DELETE') return jsonResponse({ message: 'Deleted' })
      listCallCount += 1
      return jsonResponse(listResponse([logFixture()]))
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<PriceLogsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Delete record 1' }))

    await waitFor(() => expect(listCallCount).toBe(2))
    const deleteCall = fetchMock.mock.calls.find(([, options]) => options?.method === 'DELETE')
    expect(deleteCall[0]).toBe(`${FETCHER_URL}/api/admin/items/7/price_logs/1`)
  })

  test('has no create button and no bulk toolbar', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse(listResponse([logFixture()]))))

    render(<PriceLogsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline')).toBeInTheDocument())

    expect(screen.queryByRole('button', { name: /New/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
  })
})
