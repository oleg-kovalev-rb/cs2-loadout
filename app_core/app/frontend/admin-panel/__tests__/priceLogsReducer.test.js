import { describe, test, expect } from 'vitest'
import { priceLogsReducer, initialState } from '../pages/priceLogsReducer'

describe('priceLogsReducer', () => {
  test('PAGE_CHANGED sets the page', () => {
    expect(priceLogsReducer(initialState, { type: 'PAGE_CHANGED', page: 3 }).page).toBe(3)
  })

  test('PER_PAGE_CHANGED sets perPage and resets to page 1', () => {
    const state = { ...initialState, page: 5 }

    const next = priceLogsReducer(state, { type: 'PER_PAGE_CHANGED', perPage: 50 })
    expect(next.perPage).toBe(50)
    expect(next.page).toBe(1)
  })
})
