import { describe, test, expect } from 'vitest'
import { portfolioSeries } from '../utils/portfolioSeries'

function hoursAgo(hours) {
  return new Date(Date.now() - hours * 60 * 60 * 1000).toISOString()
}

function itemWithHistory(currentPriceCents, points) {
  return { currentPriceCents, priceHistory: points }
}

describe('portfolioSeries', () => {
  test('sums current price across items', () => {
    const items = [itemWithHistory(1000, []), itemWithHistory(2500, [])]
    expect(portfolioSeries(items).currentValueCents).toBe(3500)
  })

  test('carries a price forward into hours where the item has no fresh point', () => {
    const items = [itemWithHistory(1000, [{ at: hoursAgo(3), priceCents: 1000 }])]

    const series = portfolioSeries(items).series['24h']
    expect(series.length).toBeGreaterThanOrEqual(3)
    expect(series.every((bucket) => bucket.value === 1000)).toBe(true)
    expect(series[0].at).toBeLessThan(series[series.length - 1].at)
  })

  test('items that report at different times only combine once both have data', () => {
    const items = [
      itemWithHistory(100, [{ at: hoursAgo(3), priceCents: 100 }]),
      itemWithHistory(200, [{ at: hoursAgo(1), priceCents: 200 }]),
    ]

    const series = portfolioSeries(items).series['24h']
    expect(series[0].value).toBe(100)
    expect(series[series.length - 1].value).toBe(300)
  })

  test('an item with no history at all is excluded until it reports', () => {
    const items = [itemWithHistory(500, [{ at: hoursAgo(2), priceCents: 500 }]), itemWithHistory(null, [])]

    const series = portfolioSeries(items).series['24h']
    expect(series.every((bucket) => bucket.value === 500)).toBe(true)
  })

  test('carries a price forward even from before the window, if that is the best known value', () => {
    const items = [itemWithHistory(1000, [{ at: hoursAgo(40 * 24), priceCents: 500 }])]
    const series = portfolioSeries(items).series['30d']

    expect(series.length).toBeGreaterThan(0)
    expect(series.every((bucket) => bucket.value === 500)).toBe(true)
  })

  test('produces no buckets when no item has ever reported at all', () => {
    const items = [itemWithHistory(null, [])]
    expect(portfolioSeries(items).series['30d']).toEqual([])
  })

  test('empty items produces zero value and empty series for every range', () => {
    const result = portfolioSeries([])
    expect(result.currentValueCents).toBe(0)
    expect(result.series).toEqual({ '24h': [], '7d': [], '30d': [] })
  })
})
