import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach, beforeEach } from 'vitest'
import { ItemsPage } from '../pages/ItemsPage'

const FETCHER_URL = 'https://fetcher.test'
const BRIDGE_TOKEN = 'token-123'

function itemFixture(overrides = {}) {
  return {
    id: 1,
    market_hash_name: 'AK-47 | Redline (Field-Tested)',
    metadata: {
      weapon_type: 'AK-47',
      item_name: 'Redline',
      condition: 'Field-Tested',
      stattrak: false,
      icon_url: null,
      marketable: true,
      tradable: true,
      rarity: 'Classified',
      category: 'Rifle',
    },
    current_price_cents: 1245,
    change_24h_cents: 25,
    created_at: '2026-10-01T00:00:00Z',
    updated_at: '2026-10-01T00:00:00Z',
    ...overrides,
  }
}

function listResponse(items, meta = {}) {
  return {
    meta: { total_count: items.length, total_pages: 1, ...meta },
    items,
  }
}

function jsonResponse(body, ok = true, status = ok ? 200 : 422) {
  return Promise.resolve({ ok, status, json: () => Promise.resolve(body) })
}

function mockFetchSequence(handler) {
  const fetchMock = vi.fn(handler)
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('ItemsPage', () => {
  test('loads and renders the item list with price and 24h change', async () => {
    mockFetchSequence(() => jsonResponse(listResponse([ itemFixture() ])))

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())
    expect(screen.getByText('$12.45')).toBeInTheDocument()
    expect(screen.getByText('Rifle')).toBeInTheDocument()
  })

  test('renders the StatTrak tag only when the item is StatTrak', async () => {
    mockFetchSequence(() =>
      jsonResponse(listResponse([ itemFixture({ metadata: { ...itemFixture().metadata, stattrak: true } }) ]))
    )

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getByText('ST™')).toBeInTheDocument())
  })

  test('renders a placeholder swatch when icon_url is absent, a real image when present', async () => {
    mockFetchSequence(() =>
      jsonResponse(
        listResponse([
          itemFixture({ id: 1, metadata: { ...itemFixture().metadata, icon_url: null } }),
          itemFixture({ id: 2, metadata: { ...itemFixture().metadata, icon_url: 'https://example.test/icon.png' } }),
        ])
      )
    )

    const { container } = render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)

    await waitFor(() => expect(screen.getAllByRole('row')).toHaveLength(3)) // header + 2 rows

    const images = container.querySelectorAll('img.swatch')
    const placeholders = container.querySelectorAll('span.swatch')
    expect(images).toHaveLength(1)
    expect(images[0]).toHaveAttribute('src', 'https://example.test/icon.png')
    expect(placeholders).toHaveLength(1)
  })

  test('selecting rows enables the bulk toolbar and shows the count', async () => {
    const user = userEvent.setup()
    mockFetchSequence(() => jsonResponse(listResponse([ itemFixture({ id: 1 }), itemFixture({ id: 2 }) ])))

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getAllByRole('checkbox').length).toBeGreaterThan(0))

    const rowCheckboxes = screen.getAllByRole('checkbox').filter((el) => el.className.includes('row-check'))
    await user.click(rowCheckboxes[0])

    expect(screen.getByText('Выбрано: 1')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Пересоздать кэш' })).toBeEnabled()
  })

  test('creating an item posts market_hash_name and refetches the list', async () => {
    const user = userEvent.setup()
    let listCallCount = 0
    const fetchMock = mockFetchSequence((url, options) => {
      if (options?.method === 'POST' && url.endsWith('/api/admin/items')) {
        return jsonResponse({ item: itemFixture({ id: 2, market_hash_name: 'AWP | Asiimov (Field-Tested)' }) }, true, 201)
      }
      listCallCount += 1
      return jsonResponse(listCallCount === 1 ? listResponse([ itemFixture() ]) : listResponse([ itemFixture(), itemFixture({ id: 2 }) ]))
    })

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: '+ Новый Item' }))
    await user.type(screen.getByPlaceholderText(/AK-47/), 'AWP | Asiimov (Field-Tested)')
    await user.click(screen.getByRole('button', { name: 'Добавить' }))

    await waitFor(() => expect(listCallCount).toBe(2))
    const postCall = fetchMock.mock.calls.find(([, options]) => options?.method === 'POST')
    expect(JSON.parse(postCall[1].body)).toEqual({ item: { market_hash_name: 'AWP | Asiimov (Field-Tested)' } })
  })

  test('deleting a row calls DELETE and refetches', async () => {
    const user = userEvent.setup()
    let listCallCount = 0
    const fetchMock = mockFetchSequence((url, options) => {
      if (options?.method === 'DELETE') return jsonResponse({ message: 'Deleted' })
      listCallCount += 1
      return jsonResponse(listResponse([ itemFixture() ]))
    })

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: '⋯' }))
    await user.click(screen.getByText('Удалить'))

    await waitFor(() => expect(listCallCount).toBe(2))
    const deleteCall = fetchMock.mock.calls.find(([, options]) => options?.method === 'DELETE')
    expect(deleteCall[0]).toBe(`${FETCHER_URL}/api/admin/items/1`)
  })

  test('refresh_price now calls the member action', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetchSequence((url, options) => {
      if (url.endsWith('/refresh_price')) return jsonResponse({ message: 'Price refresh enqueued' }, true, 202)
      return jsonResponse(listResponse([ itemFixture() ]))
    })

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: '⋯' }))
    await user.click(screen.getByText('Обновить цену сейчас'))

    await waitFor(() =>
      expect(fetchMock.mock.calls.some(([url]) => url === `${FETCHER_URL}/api/admin/items/1/refresh_price`)).toBe(true)
    )
  })

  test('warm_catalog_cache button calls the collection action', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetchSequence((url) => {
      if (url.endsWith('/warm_catalog_cache')) return jsonResponse({ message: 'Catalog cache warmed' })
      return jsonResponse(listResponse([ itemFixture() ]))
    })

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())

    await user.click(screen.getByRole('button', { name: 'Пересоздать кэш каталога' }))

    await waitFor(() =>
      expect(fetchMock.mock.calls.some(([url]) => url === `${FETCHER_URL}/api/admin/items/warm_catalog_cache`)).toBe(true)
    )
  })

  test('bulk warm cache sends the selected ids', async () => {
    const user = userEvent.setup()
    const fetchMock = mockFetchSequence((url) => {
      if (url.endsWith('/bulk_warm_cache')) return jsonResponse({ warmed_item_ids: [ 1 ], message: 'ok' })
      return jsonResponse(listResponse([ itemFixture() ]))
    })

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())

    const rowCheckbox = screen.getAllByRole('checkbox').find((el) => el.className.includes('row-check'))
    await user.click(rowCheckbox)
    await user.click(screen.getByRole('button', { name: 'Пересоздать кэш' }))

    await waitFor(() => {
      const call = fetchMock.mock.calls.find(([url]) => url.endsWith('/bulk_warm_cache'))
      expect(call).toBeTruthy()
      expect(JSON.parse(call[1].body)).toEqual({ item_ids: [ 1 ] })
    })
  })

  test('pagination change triggers a new fetch with the new page', async () => {
    const fetchMock = mockFetchSequence(() => jsonResponse(listResponse([ itemFixture() ], { total_count: 60, total_pages: 3 })))

    render(<ItemsPage fetcherUrl={FETCHER_URL} bridgeToken={BRIDGE_TOKEN} />)
    await waitFor(() => expect(screen.getByText('AK-47 | Redline (Field-Tested)')).toBeInTheDocument())

    const user = userEvent.setup()
    await user.click(screen.getByRole('button', { name: '2' }))

    await waitFor(() => {
      const call = fetchMock.mock.calls.find(([url]) => url.includes('page=2'))
      expect(call).toBeTruthy()
    })
  })
})
