import { describe, test, expect } from 'vitest'
import { changePercent } from '../utils/change'

describe('changePercent', () => {
  test('computes a positive percentage against the previous price', () => {
    expect(changePercent(1000, 100)).toBeCloseTo(11.11, 2)
  })

  test('computes a negative percentage against the previous price', () => {
    expect(changePercent(1000, -100)).toBeCloseTo(-9.09, 2)
  })

  test('treats a zero change as 0', () => {
    expect(changePercent(1000, 0)).toBe(0)
  })

  test('treats an absent change as 0', () => {
    expect(changePercent(1000, null)).toBe(0)
    expect(changePercent(1000, undefined)).toBe(0)
  })

  test('returns 0 when the current price is absent', () => {
    expect(changePercent(null, 100)).toBe(0)
    expect(changePercent(undefined, 100)).toBe(0)
  })

  test('returns 0 when the previous price would be zero', () => {
    expect(changePercent(1000, 1000)).toBe(0)
  })
})
