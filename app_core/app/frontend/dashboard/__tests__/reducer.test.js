import { describe, test, expect } from 'vitest'
import { dashboardReducer, initialState } from '../reducer'

const item = (overrides = {}) => ({
  marketHashName: 'AK-47 | Redline (Field-Tested)',
  weaponType: 'AK-47',
  itemName: 'Redline',
  condition: 'Field-Tested',
  stattrak: false,
  currentPriceCents: 3845,
  changeCents: -120,
  ...overrides,
})

describe('dashboardReducer', () => {
  test('RANGE_CHANGED only updates range', () => {
    const next = dashboardReducer(initialState, { type: 'RANGE_CHANGED', range: '30d' })
    expect(next.range).toBe('30d')
    expect(next.mode).toBe(initialState.mode)
  })

  test('ITEM_ROW_CLICKED selects an item and switches to item mode', () => {
    const next = dashboardReducer(initialState, { type: 'ITEM_ROW_CLICKED', item: item() })
    expect(next.mode).toBe('item')
    expect(next.selectedItem.marketHashName).toBe('AK-47 | Redline (Field-Tested)')
  })

  test('ITEM_ROW_CLICKED twice on the same item toggles back to portfolio', () => {
    const selected = dashboardReducer(initialState, { type: 'ITEM_ROW_CLICKED', item: item() })
    const deselected = dashboardReducer(selected, { type: 'ITEM_ROW_CLICKED', item: item() })
    expect(deselected.mode).toBe('portfolio')
    expect(deselected.selectedItem).toBeNull()
  })

  test('selecting a different item while one is selected swaps cleanly', () => {
    const first = dashboardReducer(initialState, { type: 'ITEM_ROW_CLICKED', item: item() })
    const second = dashboardReducer(first, { type: 'ITEM_ROW_CLICKED', item: item({ marketHashName: 'AWP | Asiimov (Battle-Scarred)' }) })
    expect(second.mode).toBe('item')
    expect(second.selectedItem.marketHashName).toBe('AWP | Asiimov (Battle-Scarred)')
  })

  test('BACK_TO_PORTFOLIO clears the selection regardless of prior mode', () => {
    const selected = dashboardReducer(initialState, { type: 'ITEM_ROW_CLICKED', item: item() })
    const back = dashboardReducer(selected, { type: 'BACK_TO_PORTFOLIO' })
    expect(back.mode).toBe('portfolio')
    expect(back.selectedItem).toBeNull()
  })

  test('SORT_CHANGED resets page to 0 and closes the dropdown', () => {
    const state = { ...initialState, page: 3, openDropdown: 'sort' }
    const next = dashboardReducer(state, { type: 'SORT_CHANGED', sort: 'price_asc' })
    expect(next.sort).toBe('price_asc')
    expect(next.page).toBe(0)
    expect(next.openDropdown).toBeNull()
  })

  test('WEAPON_FILTER_TOGGLED adds then removes a weapon, resetting page each time', () => {
    const state = { ...initialState, page: 2 }
    const added = dashboardReducer(state, { type: 'WEAPON_FILTER_TOGGLED', value: 'AK-47' })
    expect(added.filters.weapons.has('AK-47')).toBe(true)
    expect(added.page).toBe(0)

    const removed = dashboardReducer({ ...added, page: 5 }, { type: 'WEAPON_FILTER_TOGGLED', value: 'AK-47' })
    expect(removed.filters.weapons.has('AK-47')).toBe(false)
    expect(removed.page).toBe(0)
  })

  test('STATTRAK_FILTER_TOGGLED flips the boolean', () => {
    const on = dashboardReducer(initialState, { type: 'STATTRAK_FILTER_TOGGLED' })
    expect(on.filters.stattrakOnly).toBe(true)
    const off = dashboardReducer(on, { type: 'STATTRAK_FILTER_TOGGLED' })
    expect(off.filters.stattrakOnly).toBe(false)
  })

  test('FILTERS_CLEARED resets all filter fields', () => {
    const dirty = {
      ...initialState,
      page: 4,
      filters: { weapons: new Set(['AK-47']), conditions: new Set(['Factory New']), stattrakOnly: true },
    }
    const next = dashboardReducer(dirty, { type: 'FILTERS_CLEARED' })
    expect(next.filters.weapons.size).toBe(0)
    expect(next.filters.conditions.size).toBe(0)
    expect(next.filters.stattrakOnly).toBe(false)
    expect(next.page).toBe(0)
  })

  test('DROPDOWN_TOGGLED opens then closes the same dropdown', () => {
    const opened = dashboardReducer(initialState, { type: 'DROPDOWN_TOGGLED', dropdown: 'filter' })
    expect(opened.openDropdown).toBe('filter')
    const closed = dashboardReducer(opened, { type: 'DROPDOWN_TOGGLED', dropdown: 'filter' })
    expect(closed.openDropdown).toBeNull()
  })

  test('DROPDOWN_TOGGLED opening a different dropdown replaces the open one', () => {
    const sortOpen = dashboardReducer(initialState, { type: 'DROPDOWN_TOGGLED', dropdown: 'sort' })
    const filterOpen = dashboardReducer(sortOpen, { type: 'DROPDOWN_TOGGLED', dropdown: 'filter' })
    expect(filterOpen.openDropdown).toBe('filter')
  })
})
