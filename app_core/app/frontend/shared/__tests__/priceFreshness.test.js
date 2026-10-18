import { describe, test, expect } from 'vitest'
import { STALE_PRICE_AFTER_MS, isPriceStale, priceAgeLabel } from '../utils/priceFreshness'

const NOW = new Date('2026-10-18T12:00:00Z').getTime()

describe('isPriceStale', () => {
  test('treats a missing timestamp as not stale', () => {
    expect(isPriceStale(null, NOW)).toBe(false)
    expect(isPriceStale(undefined, NOW)).toBe(false)
  })

  test('is not stale at exactly 24 hours', () => {
    expect(isPriceStale(NOW - STALE_PRICE_AFTER_MS, NOW)).toBe(false)
  })

  test('is stale once the price is older than 24 hours', () => {
    expect(isPriceStale(NOW - STALE_PRICE_AFTER_MS - 1, NOW)).toBe(true)
  })
})

describe('priceAgeLabel', () => {
  test('returns null for a missing timestamp', () => {
    expect(priceAgeLabel(null, NOW)).toBeNull()
  })

  test('labels sub-day ages in hours', () => {
    expect(priceAgeLabel(NOW - 2 * 60 * 60 * 1000, NOW)).toBe('2h ago')
  })

  test('labels multi-day ages in days', () => {
    expect(priceAgeLabel(NOW - 2 * 24 * 60 * 60 * 1000, NOW)).toBe('2d ago')
  })
})
