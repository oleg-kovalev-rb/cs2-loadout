import { describe, test, expect } from 'vitest'
import { trackedItemsReducer, initialState } from '../reducer'

describe('trackedItemsReducer', () => {
  test('initial state', () => {
    expect(initialState.search).toBe('')
    expect(initialState.categories.size).toBe(0)
    expect(initialState.rarities.size).toBe(0)
    expect(initialState.stattrakOnly).toBe(false)
    expect(initialState.sort).toBe('change_24h_desc')
    expect(initialState.view).toBe('ticker')
    expect(initialState.page).toBe(1)
    expect(initialState.perPage).toBe(25)
    expect(initialState.openDropdown).toBeNull()
  })

  test('SEARCH_CHANGED updates search and resets page to 1', () => {
    const state = { ...initialState, page: 4 }
    const next = trackedItemsReducer(state, { type: 'SEARCH_CHANGED', value: 'redline' })
    expect(next.search).toBe('redline')
    expect(next.page).toBe(1)
  })

  test('CATEGORY_TOGGLED adds then removes a category, resetting page each time', () => {
    const state = { ...initialState, page: 2 }
    const added = trackedItemsReducer(state, { type: 'CATEGORY_TOGGLED', value: 'Rifles' })
    expect(added.categories.has('Rifles')).toBe(true)
    expect(added.page).toBe(1)

    const removed = trackedItemsReducer({ ...added, page: 5 }, { type: 'CATEGORY_TOGGLED', value: 'Rifles' })
    expect(removed.categories.has('Rifles')).toBe(false)
    expect(removed.page).toBe(1)
  })

  test('RARITY_TOGGLED adds then removes a rarity, resetting page each time', () => {
    const state = { ...initialState, page: 3 }
    const added = trackedItemsReducer(state, { type: 'RARITY_TOGGLED', value: 'Covert' })
    expect(added.rarities.has('Covert')).toBe(true)
    expect(added.page).toBe(1)

    const removed = trackedItemsReducer({ ...added, page: 5 }, { type: 'RARITY_TOGGLED', value: 'Covert' })
    expect(removed.rarities.has('Covert')).toBe(false)
    expect(removed.page).toBe(1)
  })

  test('STATTRAK_TOGGLED flips the boolean and resets page', () => {
    const state = { ...initialState, page: 2 }
    const on = trackedItemsReducer(state, { type: 'STATTRAK_TOGGLED' })
    expect(on.stattrakOnly).toBe(true)
    expect(on.page).toBe(1)

    const off = trackedItemsReducer({ ...on, page: 3 }, { type: 'STATTRAK_TOGGLED' })
    expect(off.stattrakOnly).toBe(false)
    expect(off.page).toBe(1)
  })

  test('SORT_CHANGED updates sort, resets page, and closes the dropdown', () => {
    const state = { ...initialState, page: 3, openDropdown: 'sort' }
    const next = trackedItemsReducer(state, { type: 'SORT_CHANGED', sort: 'price_asc' })
    expect(next.sort).toBe('price_asc')
    expect(next.page).toBe(1)
    expect(next.openDropdown).toBeNull()
  })

  test('VIEW_CHANGED updates view only, without touching page or any filter', () => {
    const state = { ...initialState, page: 4, search: 'howl' }
    const next = trackedItemsReducer(state, { type: 'VIEW_CHANGED', view: 'grid' })
    expect(next.view).toBe('grid')
    expect(next.page).toBe(4)
    expect(next.search).toBe('howl')
  })

  test('PAGE_CHANGED sets the page directly', () => {
    const next = trackedItemsReducer(initialState, { type: 'PAGE_CHANGED', page: 7 })
    expect(next.page).toBe(7)
  })

  test('PER_PAGE_CHANGED updates perPage and resets page to 1', () => {
    const state = { ...initialState, page: 5, perPage: 25 }
    const next = trackedItemsReducer(state, { type: 'PER_PAGE_CHANGED', perPage: 50 })
    expect(next.perPage).toBe(50)
    expect(next.page).toBe(1)
  })

  test('FILTERS_CLEARED resets search/categories/rarities/stattrakOnly and page', () => {
    const dirty = {
      ...initialState,
      page: 4,
      search: 'asiimov',
      categories: new Set(['Rifles']),
      rarities: new Set(['Covert']),
      stattrakOnly: true,
    }
    const next = trackedItemsReducer(dirty, { type: 'FILTERS_CLEARED' })
    expect(next.search).toBe('')
    expect(next.categories.size).toBe(0)
    expect(next.rarities.size).toBe(0)
    expect(next.stattrakOnly).toBe(false)
    expect(next.page).toBe(1)
  })

  test('FILTERS_CLEARED does not touch sort or view', () => {
    const dirty = { ...initialState, sort: 'price_desc', view: 'grid' }
    const next = trackedItemsReducer(dirty, { type: 'FILTERS_CLEARED' })
    expect(next.sort).toBe('price_desc')
    expect(next.view).toBe('grid')
  })

  test('DROPDOWN_TOGGLED opens then closes the same dropdown', () => {
    const opened = trackedItemsReducer(initialState, { type: 'DROPDOWN_TOGGLED', dropdown: 'filter' })
    expect(opened.openDropdown).toBe('filter')
    const closed = trackedItemsReducer(opened, { type: 'DROPDOWN_TOGGLED', dropdown: 'filter' })
    expect(closed.openDropdown).toBeNull()
  })

  test('DROPDOWN_TOGGLED opening a different dropdown replaces the open one', () => {
    const sortOpen = trackedItemsReducer(initialState, { type: 'DROPDOWN_TOGGLED', dropdown: 'sort' })
    const filterOpen = trackedItemsReducer(sortOpen, { type: 'DROPDOWN_TOGGLED', dropdown: 'filter' })
    expect(filterOpen.openDropdown).toBe('filter')
  })

  test('DROPDOWNS_CLOSED closes whatever is open', () => {
    const opened = trackedItemsReducer(initialState, { type: 'DROPDOWN_TOGGLED', dropdown: 'sort' })
    const closed = trackedItemsReducer(opened, { type: 'DROPDOWNS_CLOSED' })
    expect(closed.openDropdown).toBeNull()
  })
})
