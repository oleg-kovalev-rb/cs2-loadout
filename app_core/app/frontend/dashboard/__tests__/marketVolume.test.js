import { describe, test, expect } from 'vitest'
import { marketVolume } from '../utils/marketVolume'

describe('marketVolume', () => {
  test('sums volume across items into hourly buckets', () => {
    const now = Date.now()
    const items = [
      { priceHistory: [{ at: new Date(now - 60 * 60 * 1000).toISOString(), volume: 50 }] },
      { priceHistory: [{ at: new Date(now - 60 * 60 * 1000).toISOString(), volume: 30 }] },
    ]

    expect(marketVolume(items).sparkline).toEqual([80])
  })

  test('countLast24h is the most recent bucket total', () => {
    const now = Date.now()
    const items = [
      {
        priceHistory: [
          { at: new Date(now - 10 * 60 * 60 * 1000).toISOString(), volume: 20 },
          { at: new Date(now - 1 * 60 * 60 * 1000).toISOString(), volume: 99 },
        ],
      },
    ]

    expect(marketVolume(items).countLast24h).toBe(99)
  })

  test('drops points older than the 15-hour window', () => {
    const now = Date.now()
    const items = [{ priceHistory: [{ at: new Date(now - 20 * 60 * 60 * 1000).toISOString(), volume: 999 }] }]

    const result = marketVolume(items)
    expect(result.sparkline).toEqual([])
    expect(result.countLast24h).toBe(0)
  })
})
