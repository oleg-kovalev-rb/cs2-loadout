import { describe, test, expect } from 'vitest'
import { isFullyPriced, pricedTotalCents } from '../utils/valuation'

function item(overrides = {}) {
  return { marketable: true, currentPriceCents: null, ...overrides }
}

describe('isFullyPriced', () => {
  test('an empty (or not-yet-loaded) inventory is treated as fully priced', () => {
    expect(isFullyPriced([])).toBe(true)
    expect(isFullyPriced(undefined)).toBe(true)
  })

  test('is true when every marketable item has a price', () => {
    expect(
      isFullyPriced([item({ currentPriceCents: 100 }), item({ currentPriceCents: 200 })]),
    ).toBe(true)
  })

  test('is false when a marketable item still has no price', () => {
    expect(
      isFullyPriced([item({ currentPriceCents: 100 }), item({ currentPriceCents: null })]),
    ).toBe(false)
  })

  test('ignores unpriced non-marketable items (they never get a price)', () => {
    expect(
      isFullyPriced([
        item({ marketable: false, currentPriceCents: null }),
        item({ marketable: true, currentPriceCents: 100 }),
      ]),
    ).toBe(true)
  })
})

describe('pricedTotalCents', () => {
  test('is 0 for an empty (or not-yet-loaded) inventory', () => {
    expect(pricedTotalCents([])).toBe(0)
    expect(pricedTotalCents(undefined)).toBe(0)
  })

  test('sums only the items that have a price', () => {
    expect(
      pricedTotalCents([
        item({ currentPriceCents: 100 }),
        item({ currentPriceCents: null }),
        item({ marketable: false, currentPriceCents: null }),
        item({ currentPriceCents: 250 }),
      ]),
    ).toBe(350)
  })
})
