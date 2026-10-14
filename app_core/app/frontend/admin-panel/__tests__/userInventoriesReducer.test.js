import { describe, test, expect } from 'vitest'
import { userInventoriesReducer, initialState } from '../pages/userInventoriesReducer'

describe('userInventoriesReducer', () => {
  test('PAGE_CHANGED sets the page and clears selection', () => {
    const state = { ...initialState, selectedIds: new Set([1]) }

    const next = userInventoriesReducer(state, { type: 'PAGE_CHANGED', page: 2 })
    expect(next.page).toBe(2)
    expect(next.selectedIds.size).toBe(0)
  })

  test('PER_PAGE_CHANGED resets to page 1', () => {
    const state = { ...initialState, page: 4 }

    const next = userInventoriesReducer(state, { type: 'PER_PAGE_CHANGED', perPage: 100 })
    expect(next.perPage).toBe(100)
    expect(next.page).toBe(1)
  })

  test('ROW_TOGGLED adds then removes a steam_id', () => {
    let state = userInventoriesReducer(initialState, { type: 'ROW_TOGGLED', steamId: 'a' })
    expect(state.selectedIds.has('a')).toBe(true)

    state = userInventoriesReducer(state, { type: 'ROW_TOGGLED', steamId: 'a' })
    expect(state.selectedIds.has('a')).toBe(false)
  })

  test('ALL_TOGGLED selects/clears every given steam_id', () => {
    let state = userInventoriesReducer(initialState, { type: 'ALL_TOGGLED', checked: true, steamIds: [ 'a', 'b' ] })
    expect([ ...state.selectedIds ]).toEqual([ 'a', 'b' ])

    state = userInventoriesReducer(state, { type: 'ALL_TOGGLED', checked: false, steamIds: [ 'a', 'b' ] })
    expect(state.selectedIds.size).toBe(0)
  })

  test('SELECTION_CLEARED empties the selection', () => {
    const state = { ...initialState, selectedIds: new Set([ 'a' ]) }
    expect(userInventoriesReducer(state, { type: 'SELECTION_CLEARED' }).selectedIds.size).toBe(0)
  })

  test('ROW_EXPAND_TOGGLED expands then collapses independently per steam_id', () => {
    let state = userInventoriesReducer(initialState, { type: 'ROW_EXPAND_TOGGLED', steamId: 'a' })
    expect(state.expandedSteamIds.has('a')).toBe(true)

    state = userInventoriesReducer(state, { type: 'ROW_EXPAND_TOGGLED', steamId: 'b' })
    expect(state.expandedSteamIds.has('a')).toBe(true)
    expect(state.expandedSteamIds.has('b')).toBe(true)

    state = userInventoriesReducer(state, { type: 'ROW_EXPAND_TOGGLED', steamId: 'a' })
    expect(state.expandedSteamIds.has('a')).toBe(false)
    expect(state.expandedSteamIds.has('b')).toBe(true)
  })
})
