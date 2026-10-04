import { describe, test, expect } from 'vitest'
import { applyFilters, applySort, weaponTypesPresent, conditionsPresent, stattrakPresent } from '../utils/filters'

const items = [
  {
    marketHashName: 'AK-47 | Redline (FT)', weaponType: 'AK-47', itemName: 'Redline', condition: 'Field-Tested', stattrak: false,
    currentPriceCents: 4000, changeCents: 300, change24hPercent: 8.11,
  },
  {
    marketHashName: 'AK-47 | Vulcan (MW) ST', weaponType: 'AK-47', itemName: 'Vulcan', condition: 'Minimal Wear', stattrak: true,
    currentPriceCents: 14500, changeCents: -200, change24hPercent: -1.36,
  },
  {
    marketHashName: 'AWP | Asiimov (BS)', weaponType: 'AWP', itemName: 'Asiimov', condition: 'Battle-Scarred', stattrak: false,
    currentPriceCents: 5800, changeCents: 100, change24hPercent: 1.75,
  },
]

function emptyFilters() {
  return { weapons: new Set(), conditions: new Set(), stattrakOnly: false }
}

describe('applyFilters', () => {
  test('no filters returns every item', () => {
    expect(applyFilters(items, emptyFilters())).toHaveLength(3)
  })

  test('weapon filter narrows to matching weapon types', () => {
    const filters = { ...emptyFilters(), weapons: new Set(['AK-47']) }
    const result = applyFilters(items, filters)
    expect(result).toHaveLength(2)
    expect(result.every((i) => i.weaponType === 'AK-47')).toBe(true)
  })

  test('condition filter narrows to matching conditions', () => {
    const filters = { ...emptyFilters(), conditions: new Set(['Battle-Scarred']) }
    expect(applyFilters(items, filters)).toHaveLength(1)
  })

  test('stattrakOnly keeps only StatTrak items', () => {
    const filters = { ...emptyFilters(), stattrakOnly: true }
    const result = applyFilters(items, filters)
    expect(result).toHaveLength(1)
    expect(result[0].marketHashName).toBe('AK-47 | Vulcan (MW) ST')
  })

  test('combining weapon + stattrak filters is AND, not OR', () => {
    const filters = { ...emptyFilters(), weapons: new Set(['AWP']), stattrakOnly: true }
    expect(applyFilters(items, filters)).toHaveLength(0)
  })
})

describe('applySort', () => {
  test('delta_desc orders biggest gainers first', () => {
    const result = applySort(items, 'delta_desc')
    expect(result.map((i) => i.marketHashName)).toEqual([
      'AK-47 | Redline (FT)',
      'AWP | Asiimov (BS)',
      'AK-47 | Vulcan (MW) ST',
    ])
  })

  test('delta_asc orders biggest losers first', () => {
    const result = applySort(items, 'delta_asc')
    expect(result.map((i) => i.marketHashName)).toEqual([
      'AK-47 | Vulcan (MW) ST',
      'AWP | Asiimov (BS)',
      'AK-47 | Redline (FT)',
    ])
  })

  test('price_desc orders most expensive first', () => {
    const result = applySort(items, 'price_desc')
    expect(result.map((i) => i.currentPriceCents)).toEqual([14500, 5800, 4000])
  })

  test('price_asc orders cheapest first', () => {
    const result = applySort(items, 'price_asc')
    expect(result.map((i) => i.currentPriceCents)).toEqual([4000, 5800, 14500])
  })

  test('name_asc orders alphabetically by weapon then item name', () => {
    const result = applySort(items, 'name_asc')
    expect(result.map((i) => i.itemName)).toEqual(['Redline', 'Vulcan', 'Asiimov'])
  })

  test('does not mutate the original array', () => {
    const original = [...items]
    applySort(items, 'price_desc')
    expect(items).toEqual(original)
  })
})

describe('weaponTypesPresent', () => {
  test('empty items returns an empty list', () => {
    expect(weaponTypesPresent([])).toEqual([])
  })

  test('dedupes and alphabetically sorts the weapon types actually present', () => {
    expect(weaponTypesPresent(items)).toEqual(['AK-47', 'AWP'])
  })

  test('excludes items with no weaponType (knives, gloves, stickers, cases) instead of producing a blank entry', () => {
    const withKnife = [...items, { marketHashName: 'Karambit | Doppler', itemName: 'Karambit | Doppler', condition: 'Factory New', stattrak: false }]
    expect(weaponTypesPresent(withKnife)).toEqual(['AK-47', 'AWP'])
  })
})

describe('conditionsPresent', () => {
  test('empty items returns an empty list', () => {
    expect(conditionsPresent([])).toEqual([])
  })

  test('returns only the conditions actually present, in canonical wear order rather than insertion or alphabetical order', () => {
    // Insertion order here is Well-Worn, Factory New, Battle-Scarred — alphabetical
    // would be Battle-Scarred, Factory New, Well-Worn. Canonical CONDITIONS order
    // (Factory New, Minimal Wear, Field-Tested, Well-Worn, Battle-Scarred) gives a
    // third, different ordering — so this fixture only passes an implementation
    // that actually orders by CONDITIONS, not one that sorts/dedupes any other way.
    const present = [
      { marketHashName: 'a', condition: 'Well-Worn' },
      { marketHashName: 'b', condition: 'Factory New' },
      { marketHashName: 'c', condition: 'Battle-Scarred' },
    ]
    expect(conditionsPresent(present)).toEqual(['Factory New', 'Well-Worn', 'Battle-Scarred'])
  })

  test('excludes items with no condition (stickers, cases, agents) instead of producing a blank entry', () => {
    const withSticker = [...items, { marketHashName: 'Sticker | Katowice 2014', itemName: 'Sticker | Katowice 2014', stattrak: false }]
    expect(conditionsPresent(withSticker)).toEqual(['Minimal Wear', 'Field-Tested', 'Battle-Scarred'])
  })
})

describe('stattrakPresent', () => {
  test('empty items returns false', () => {
    expect(stattrakPresent([])).toBe(false)
  })

  test('returns false when no item is StatTrak', () => {
    expect(stattrakPresent(items.filter((i) => !i.stattrak))).toBe(false)
  })

  test('returns true when at least one item is StatTrak', () => {
    expect(stattrakPresent(items)).toBe(true)
  })
})
