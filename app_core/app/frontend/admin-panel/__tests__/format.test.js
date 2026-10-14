import { describe, test, expect } from 'vitest'
import { fmtPrice, fmtDateTime, fmtDate } from '../utils/format'

describe('fmtPrice', () => {
  test('formats cents as a dollar string', () => {
    expect(fmtPrice(1245)).toBe('$12.45')
  })

  test('renders an em dash for null/zero', () => {
    expect(fmtPrice(null)).toBe('—')
    expect(fmtPrice(0)).toBe('—')
  })
})

describe('fmtDateTime', () => {
  test('formats an ISO timestamp as DD.MM.YYYY HH:MM', () => {
    expect(fmtDateTime('2026-10-11T14:02:00Z')).toMatch(/^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$/)
  })

  test('renders an em dash for a nullish value', () => {
    expect(fmtDateTime(null)).toBe('—')
  })
})

describe('fmtDate', () => {
  test('formats an ISO date as DD.MM.YYYY', () => {
    expect(fmtDate('2026-10-11')).toMatch(/^\d{2}\.\d{2}\.\d{4}$/)
  })

  test('renders an em dash for a nullish value', () => {
    expect(fmtDate(null)).toBe('—')
  })
})
