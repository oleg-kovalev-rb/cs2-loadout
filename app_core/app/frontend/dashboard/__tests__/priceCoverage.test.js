import { describe, test, expect } from 'vitest'
import { priceableNames } from '../utils/priceCoverage'

function item(overrides = {}) {
  return { marketHashName: 'item', marketable: true, priceUnavailable: false, ...overrides }
}

describe('priceableNames', () => {
  test('is empty for a missing or empty item list', () => {
    expect(priceableNames(undefined)).toEqual([])
    expect(priceableNames([])).toEqual([])
  })

  test('includes marketable, available items', () => {
    expect(
      priceableNames([
        item({ marketHashName: 'A' }),
        item({ marketHashName: 'B', currentPriceCents: 100 }),
      ]),
    ).toEqual(['A', 'B'])
  })

  test('excludes non-marketable items', () => {
    expect(
      priceableNames([
        item({ marketHashName: 'A' }),
        item({ marketHashName: 'B', marketable: false }),
      ]),
    ).toEqual(['A'])
  })

  test('excludes price_unavailable items even when they are marketable', () => {
    expect(
      priceableNames([
        item({ marketHashName: 'A' }),
        item({ marketHashName: 'B', priceUnavailable: true }),
      ]),
    ).toEqual(['A'])
  })
})
