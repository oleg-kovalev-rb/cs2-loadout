import { describe, test, expect } from 'vitest'
import { fmtPrice, fmtDateTime } from '../utils/format'

describe('fmtPrice', () => {
  test('renders a dash for zero (not tradable)', () => {
    expect(fmtPrice(0)).toBe('—')
  })

  test('renders a dash for null (no price yet)', () => {
    expect(fmtPrice(null)).toBe('—')
  })

  test('renders a dash for undefined (no price yet)', () => {
    expect(fmtPrice(undefined)).toBe('—')
  })

  test('renders a formatted USD price for a real value', () => {
    expect(fmtPrice(3845)).toBe('$38.45')
  })
})

describe('fmtDateTime', () => {
  test('renders a short month/day + hour:minute for an epoch-ms timestamp', () => {
    const epochMs = new Date('2026-03-05T15:45:00').getTime()
    expect(fmtDateTime(epochMs)).toBe('Mar 5, 3:45 PM')
  })
})
