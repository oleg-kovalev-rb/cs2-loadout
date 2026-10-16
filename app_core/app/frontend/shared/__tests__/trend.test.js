import { describe, test, expect } from 'vitest'
import { trendDirection } from '../utils/trend'

describe('trendDirection', () => {
  test('classifies a positive change as up', () => {
    expect(trendDirection(2.5)).toBe('up')
    expect(trendDirection(0.01)).toBe('up')
  })

  test('classifies a negative change as down', () => {
    expect(trendDirection(-1.2)).toBe('down')
    expect(trendDirection(-0.01)).toBe('down')
  })

  test('classifies a zero change as flat, not up', () => {
    expect(trendDirection(0)).toBe('flat')
    expect(trendDirection(-0)).toBe('flat')
  })

  test('classifies a missing change as flat', () => {
    expect(trendDirection(null)).toBe('flat')
    expect(trendDirection(undefined)).toBe('flat')
    expect(trendDirection(NaN)).toBe('flat')
  })
})
