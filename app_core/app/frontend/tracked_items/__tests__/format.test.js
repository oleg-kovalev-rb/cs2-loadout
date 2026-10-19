import { describe, test, expect } from 'vitest'
import { rarityColor } from '../utils/format'

describe('rarityColor', () => {
  test.each([
    ['Consumer Grade', '#b0c3d9'],
    ['Industrial Grade', '#5e98d9'],
    ['Mil-Spec Grade', '#4b69ff'],
    ['Restricted', '#8847ff'],
    ['Classified', '#d32ce6'],
    ['Covert', '#eb4b4b'],
    ['Extraordinary', '#e4ae39'],
    ['Contraband', '#e4ae39'],
  ])('maps %s to %s', (rarity, color) => {
    expect(rarityColor(rarity)).toBe(color)
  })

  test('falls back to a neutral color for an unrecognized rarity', () => {
    expect(rarityColor('High Grade')).toBe('#8791ab')
  })

  test('falls back to the same neutral color for a missing rarity', () => {
    expect(rarityColor(undefined)).toBe('#8791ab')
  })
})
