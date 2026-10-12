import { describe, test, expect } from 'vitest'
import { RANGE_MS, generateAxisLabels } from '../chartConfig'

describe('RANGE_MS', () => {
  test("has no entry for 'all' — it has no fixed duration to count back from", () => {
    expect(RANGE_MS.all).toBeUndefined()
  })
})

describe('generateAxisLabels', () => {
  test('for a fixed-duration range, computes relative-offset labels counting down to "today"', () => {
    expect(generateAxisLabels('7d', 5)).toEqual(['7d ago', '5d ago', '4d ago', '2d ago', 'today'])
  })

  test('for \'all\', only the trailing tick says "today" — every earlier tick is blank, not a fabricated offset', () => {
    expect(generateAxisLabels('all', 5)).toEqual(['', '', '', '', 'today'])
  })
})
