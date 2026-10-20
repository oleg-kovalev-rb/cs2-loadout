import { describe, test, expect } from 'vitest'
import { toggleSetMember } from '../utils/sets'

describe('toggleSetMember', () => {
  test('returns a new set with the value added when absent', () => {
    const original = new Set(['a'])

    const next = toggleSetMember(original, 'b')

    expect(next).toEqual(new Set(['a', 'b']))
    expect(original).toEqual(new Set(['a']))
  })

  test('returns a new set with the value removed when present', () => {
    const original = new Set(['a', 'b'])

    const next = toggleSetMember(original, 'a')

    expect(next).toEqual(new Set(['b']))
    expect(original).toEqual(new Set(['a', 'b']))
  })
})
