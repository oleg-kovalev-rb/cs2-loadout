import { describe, test, expect } from 'vitest'
import { RARITY_TIERS, rarityTier } from '../utils/rarity'

describe('RARITY_TIERS', () => {
  test('lists all 7 tiers in gold-to-consumer order', () => {
    expect(RARITY_TIERS.map((tier) => tier.key)).toEqual([
      'gold',
      'covert',
      'classified',
      'restricted',
      'mil_spec',
      'industrial',
      'consumer',
    ])
  })

  test('maps the mil_spec API key to the --rarity-milspec CSS var (no underscore)', () => {
    const milSpec = RARITY_TIERS.find((tier) => tier.key === 'mil_spec')
    expect(milSpec.cssVar).toBe('--rarity-milspec')
  })
})

describe('rarityTier', () => {
  test('finds a tier by its API key', () => {
    expect(rarityTier('covert').label).toBe('Covert')
  })

  test('returns null for an unknown key', () => {
    expect(rarityTier('nope')).toBeNull()
  })
})
