import { describe, test, expect } from 'vitest'
import { itemsReducer, initialState } from '../pages/itemsReducer'

describe('itemsReducer', () => {
  test('PAGE_CHANGED sets the page and clears selection', () => {
    const state = { ...initialState, page: 1, selectedIds: new Set([1, 2]) }

    const next = itemsReducer(state, { type: 'PAGE_CHANGED', page: 3 })

    expect(next.page).toBe(3)
    expect(next.selectedIds.size).toBe(0)
  })

  test('ROW_TOGGLED adds then removes an id', () => {
    let state = itemsReducer(initialState, { type: 'ROW_TOGGLED', id: 5 })
    expect(state.selectedIds.has(5)).toBe(true)

    state = itemsReducer(state, { type: 'ROW_TOGGLED', id: 5 })
    expect(state.selectedIds.has(5)).toBe(false)
  })

  test('ALL_TOGGLED selects every given id when checked, clears when unchecked', () => {
    let state = itemsReducer(initialState, { type: 'ALL_TOGGLED', checked: true, ids: [1, 2, 3] })
    expect([...state.selectedIds]).toEqual([1, 2, 3])

    state = itemsReducer(state, { type: 'ALL_TOGGLED', checked: false, ids: [1, 2, 3] })
    expect(state.selectedIds.size).toBe(0)
  })

  test('SELECTION_CLEARED empties the selection', () => {
    const state = { ...initialState, selectedIds: new Set([1]) }

    expect(itemsReducer(state, { type: 'SELECTION_CLEARED' }).selectedIds.size).toBe(0)
  })

  test('CREATE_PANEL_TOGGLED flips the open flag', () => {
    const opened = itemsReducer(initialState, { type: 'CREATE_PANEL_TOGGLED' })
    expect(opened.isCreatePanelOpen).toBe(true)

    const closed = itemsReducer(opened, { type: 'CREATE_PANEL_TOGGLED' })
    expect(closed.isCreatePanelOpen).toBe(false)
  })

  test('CREATE_PANEL_CLOSED always closes it', () => {
    const state = { ...initialState, isCreatePanelOpen: true }

    expect(itemsReducer(state, { type: 'CREATE_PANEL_CLOSED' }).isCreatePanelOpen).toBe(false)
  })

  test('ROW_MENU_TOGGLED opens a closed menu and closes an open one', () => {
    const opened = itemsReducer(initialState, { type: 'ROW_MENU_TOGGLED', id: 7 })
    expect(opened.openRowMenuId).toBe(7)

    const closed = itemsReducer(opened, { type: 'ROW_MENU_TOGGLED', id: 7 })
    expect(closed.openRowMenuId).toBeNull()

    const switched = itemsReducer(opened, { type: 'ROW_MENU_TOGGLED', id: 9 })
    expect(switched.openRowMenuId).toBe(9)
  })

  test('ROW_MENU_CLOSED clears any open menu', () => {
    const state = { ...initialState, openRowMenuId: 7 }

    expect(itemsReducer(state, { type: 'ROW_MENU_CLOSED' }).openRowMenuId).toBeNull()
  })

  test('PER_PAGE_CHANGED resets to page 1 and clears selection', () => {
    const state = { ...initialState, page: 4, perPage: 25, selectedIds: new Set([1]) }

    const next = itemsReducer(state, { type: 'PER_PAGE_CHANGED', perPage: 100 })

    expect(next.perPage).toBe(100)
    expect(next.page).toBe(1)
    expect(next.selectedIds.size).toBe(0)
  })

  test('ALL_MENUS_CLOSED clears the open row menu', () => {
    const state = { ...initialState, openRowMenuId: 3 }

    const next = itemsReducer(state, { type: 'ALL_MENUS_CLOSED' })
    expect(next.openRowMenuId).toBeNull()
  })
})
