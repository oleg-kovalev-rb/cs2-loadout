import { describe, test, expect } from 'vitest'
import { hasPartialPoints, partialPointLabel } from '../utils/chartPoints'

describe('hasPartialPoints', () => {
  test('is false for a missing, empty, or fully-complete series', () => {
    expect(hasPartialPoints(undefined)).toBe(false)
    expect(hasPartialPoints([])).toBe(false)
    expect(hasPartialPoints([{ complete: true }, { complete: true }])).toBe(false)
  })

  test('is true when any point is incomplete', () => {
    expect(hasPartialPoints([{ complete: true }, { complete: false }])).toBe(true)
  })
})

describe('partialPointLabel', () => {
  test('includes the priced/pricable counts when the point has them', () => {
    expect(partialPointLabel({ pricedItemsCount: 100, pricableItemsCount: 127 })).toBe(
      'Partial estimate · 100/127 priced',
    )
  })

  test('falls back to the generic label without counts', () => {
    expect(partialPointLabel({})).toBe('Partial estimate')
    expect(partialPointLabel({ pricedItemsCount: 100 })).toBe('Partial estimate')
  })
})
