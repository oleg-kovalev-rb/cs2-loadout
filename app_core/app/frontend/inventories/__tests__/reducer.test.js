import { describe, test, expect } from 'vitest'
import { catalogReducer, initialCatalogState, detailReducer, initialDetailState } from '../reducer'

describe('catalogReducer', () => {
  test('SORT_CHANGED updates sort, resets page to 1, and closes the dropdown', () => {
    const state = { ...initialCatalogState, page: 3, openDropdown: 'sort' }
    const next = catalogReducer(state, { type: 'SORT_CHANGED', sort: 'items_desc' })

    expect(next.sort).toBe('items_desc')
    expect(next.page).toBe(1)
    expect(next.openDropdown).toBeNull()
  })

  test('PAGE_CHANGED only updates page', () => {
    const next = catalogReducer(initialCatalogState, { type: 'PAGE_CHANGED', page: 2 })
    expect(next.page).toBe(2)
    expect(next.sort).toBe(initialCatalogState.sort)
  })

  test('DROPDOWN_TOGGLED opens then closes the same dropdown', () => {
    const opened = catalogReducer(initialCatalogState, { type: 'DROPDOWN_TOGGLED', dropdown: 'sort' })
    expect(opened.openDropdown).toBe('sort')
    const closed = catalogReducer(opened, { type: 'DROPDOWN_TOGGLED', dropdown: 'sort' })
    expect(closed.openDropdown).toBeNull()
  })

  test('DROPDOWNS_CLOSED clears an open dropdown', () => {
    const opened = { ...initialCatalogState, openDropdown: 'sort' }
    const next = catalogReducer(opened, { type: 'DROPDOWNS_CLOSED' })
    expect(next.openDropdown).toBeNull()
  })

  test('DROPDOWNS_CLOSED on an already-closed state returns the same reference', () => {
    const next = catalogReducer(initialCatalogState, { type: 'DROPDOWNS_CLOSED' })
    expect(next).toBe(initialCatalogState)
  })
})

describe('detailReducer', () => {
  test('RANGE_CHANGED only updates range', () => {
    const next = detailReducer(initialDetailState, { type: 'RANGE_CHANGED', range: '30d' })
    expect(next.range).toBe('30d')
    expect(next.itemsSort).toBe(initialDetailState.itemsSort)
  })

  test('ITEMS_SORT_CHANGED updates sort, resets itemsPage to 1, and closes the dropdown', () => {
    const state = { ...initialDetailState, itemsPage: 4, openDropdown: 'itemsSort' }
    const next = detailReducer(state, { type: 'ITEMS_SORT_CHANGED', itemsSort: 'price_asc' })

    expect(next.itemsSort).toBe('price_asc')
    expect(next.itemsPage).toBe(1)
    expect(next.openDropdown).toBeNull()
  })

  test('ITEMS_PAGE_CHANGED only updates itemsPage', () => {
    const next = detailReducer(initialDetailState, { type: 'ITEMS_PAGE_CHANGED', itemsPage: 3 })
    expect(next.itemsPage).toBe(3)
    expect(next.range).toBe(initialDetailState.range)
  })

  test('DROPDOWN_TOGGLED opens then closes the same dropdown', () => {
    const opened = detailReducer(initialDetailState, { type: 'DROPDOWN_TOGGLED', dropdown: 'itemsSort' })
    expect(opened.openDropdown).toBe('itemsSort')
    const closed = detailReducer(opened, { type: 'DROPDOWN_TOGGLED', dropdown: 'itemsSort' })
    expect(closed.openDropdown).toBeNull()
  })

  test('DROPDOWNS_CLOSED on an already-closed state returns the same reference', () => {
    const next = detailReducer(initialDetailState, { type: 'DROPDOWNS_CLOSED' })
    expect(next).toBe(initialDetailState)
  })
})
