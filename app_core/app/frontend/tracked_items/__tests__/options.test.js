import { describe, test, expect } from 'vitest'
import { categoriesPresent, raritiesPresent } from '../utils/options'

describe('categoriesPresent', () => {
  test('returns an empty array for an empty item list', () => {
    expect(categoriesPresent([])).toEqual([])
  })

  test('returns the distinct categories present, sorted, deduplicated', () => {
    const items = [{ category: 'Rifles' }, { category: 'Knives' }, { category: 'Rifles' }]
    expect(categoriesPresent(items)).toEqual(['Knives', 'Rifles'])
  })

  test('drops items with a missing category', () => {
    const items = [{ category: 'Rifles' }, { category: null }, { category: undefined }]
    expect(categoriesPresent(items)).toEqual(['Rifles'])
  })
})

describe('raritiesPresent', () => {
  test('returns an empty array for an empty item list', () => {
    expect(raritiesPresent([])).toEqual([])
  })

  test('returns the distinct rarities present, sorted, deduplicated', () => {
    const items = [{ rarity: 'Covert' }, { rarity: 'Classified' }, { rarity: 'Covert' }]
    expect(raritiesPresent(items)).toEqual(['Classified', 'Covert'])
  })

  test('drops items with a missing rarity', () => {
    const items = [{ rarity: 'Covert' }, { rarity: null }]
    expect(raritiesPresent(items)).toEqual(['Covert'])
  })
})
