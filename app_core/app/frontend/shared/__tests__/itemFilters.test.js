import { describe, test, expect } from 'vitest'
import { stattrakPresent } from '../utils/itemFilters'

describe('stattrakPresent', () => {
  test('empty items returns false', () => {
    expect(stattrakPresent([])).toBe(false)
  })

  test('returns false when no item is StatTrak', () => {
    expect(stattrakPresent([{ stattrak: false }, { stattrak: false }])).toBe(false)
  })

  test('returns true when at least one item is StatTrak', () => {
    expect(stattrakPresent([{ stattrak: false }, { stattrak: true }])).toBe(true)
  })
})
