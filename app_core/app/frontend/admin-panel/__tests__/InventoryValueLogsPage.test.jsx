import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { InventoryValueLogsPage } from '../pages/InventoryValueLogsPage'

const FETCHER_URL = 'https://fetcher.test'
const BRIDGE_TOKEN = 'token-123'

function logFixture(overrides = {}) {
  return {
    id: 1,
    steam_id: '76561198012345678',
    log_date: '2026-10-11',
    total_value_cents: 110000,
    ...overrides,
  }
}

function listResponse(inventory_value_logs, meta = {}) {
  return {
    meta: { total_count: inventory_value_logs.length, total_pages: 1, ...meta },
    inventory_value_logs,
  }
}

function jsonResponse(body, ok = true, status = ok ? 200 : 422) {
  return Promise.resolve({ ok, status, json: () => Promise.resolve(body) })
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('InventoryValueLogsPage', () => {
  test('loads and renders the list', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse(listResponse([logFixture()]))))

    render(<InventoryValueLogsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())
    expect(screen.getByText('$1,100.00')).toBeInTheDocument()
  })

  test('deleting a row calls DELETE on the flat route and refetches', async () => {
    const user = userEvent.setup()
    let listCallCount = 0
    const fetchMock = vi.fn((url, options) => {
      if (options?.method === 'DELETE') return jsonResponse({ message: 'Deleted' })
      listCallCount += 1
      return jsonResponse(listResponse([logFixture()]))
    })
    vi.stubGlobal('fetch', fetchMock)

    render(<InventoryValueLogsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Delete record 1' }))

    await waitFor(() => expect(listCallCount).toBe(2))
    const deleteCall = fetchMock.mock.calls.find(([, options]) => options?.method === 'DELETE')
    expect(deleteCall[0]).toBe(
      `${FETCHER_URL}/api/admin/user_inventories/76561198012345678/inventory_value_logs/1`,
    )
  })

  test('has no create button and no checkboxes', async () => {
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(jsonResponse(listResponse([logFixture()]))))

    render(<InventoryValueLogsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('76561198012345678')).toBeInTheDocument())

    expect(screen.queryByRole('button', { name: /New/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument()
  })
})
