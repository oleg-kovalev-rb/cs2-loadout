import { describe, test, expect } from 'vitest'
import { inventoryValueLogsReducer, initialState } from '../pages/inventoryValueLogsReducer'

describe('inventoryValueLogsReducer', () => {
  test('PAGE_CHANGED sets the page', () => {
    expect(inventoryValueLogsReducer(initialState, { type: 'PAGE_CHANGED', page: 3 }).page).toBe(3)
  })

  test('PER_PAGE_CHANGED sets perPage and resets to page 1', () => {
    const state = { ...initialState, page: 5 }

    const next = inventoryValueLogsReducer(state, { type: 'PER_PAGE_CHANGED', perPage: 100 })
    expect(next.perPage).toBe(100)
    expect(next.page).toBe(1)
  })
})
