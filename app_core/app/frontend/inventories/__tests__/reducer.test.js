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
    const opened = catalogReducer(initialCatalogState, {
      type: 'DROPDOWN_TOGGLED',
      dropdown: 'sort',
    })
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
  test('PERIOD_CHANGED only updates period', () => {
    const next = detailReducer(initialDetailState, { type: 'PERIOD_CHANGED', period: '30d' })
    expect(next.period).toBe('30d')
    expect(next.sort).toBe(initialDetailState.sort)
  })

  test('SORT_CHANGED updates sort, resets page to 1, and closes the dropdown', () => {
    const state = { ...initialDetailState, page: 4, openDropdown: 'sort' }
    const next = detailReducer(state, { type: 'SORT_CHANGED', sort: 'price_asc' })

    expect(next.sort).toBe('price_asc')
    expect(next.page).toBe(1)
    expect(next.openDropdown).toBeNull()
  })

  test('PAGE_CHANGED only updates page', () => {
    const next = detailReducer(initialDetailState, { type: 'PAGE_CHANGED', page: 3 })
    expect(next.page).toBe(3)
    expect(next.period).toBe(initialDetailState.period)
  })

  test('DROPDOWN_TOGGLED opens then closes the same dropdown', () => {
    const opened = detailReducer(initialDetailState, {
      type: 'DROPDOWN_TOGGLED',
      dropdown: 'sort',
    })
    expect(opened.openDropdown).toBe('sort')
    const closed = detailReducer(opened, { type: 'DROPDOWN_TOGGLED', dropdown: 'sort' })
    expect(closed.openDropdown).toBeNull()
  })

  test('DROPDOWNS_CLOSED on an already-closed state returns the same reference', () => {
    const next = detailReducer(initialDetailState, { type: 'DROPDOWNS_CLOSED' })
    expect(next).toBe(initialDetailState)
  })
})
