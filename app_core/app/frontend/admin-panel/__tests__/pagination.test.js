import { describe, test, expect } from 'vitest'
import { buildPageNumbers } from '../utils/pagination'

describe('buildPageNumbers', () => {
  test('returns every page when there are few of them', () => {
    expect(buildPageNumbers(1, 3)).toEqual([1, 2, 3])
  })

  test('returns a single page for a one-page result', () => {
    expect(buildPageNumbers(1, 1)).toEqual([1])
  })

  test('truncates with an ellipsis before the last page when far from it', () => {
    expect(buildPageNumbers(1, 390)).toEqual([1, 2, 3, '…', 390])
  })

  test('truncates with an ellipsis near the middle', () => {
    expect(buildPageNumbers(200, 390)).toEqual([1, '…', 200, '…', 390])
  })

  test('truncates with an ellipsis near the end', () => {
    expect(buildPageNumbers(390, 390)).toEqual([1, '…', 388, 389, 390])
  })
})
