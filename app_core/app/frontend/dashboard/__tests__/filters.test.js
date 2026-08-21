import { describe, test, expect } from 'vitest'
import { applyFilters, applySort } from '../utils/filters'

const items = [
  { marketHashName: 'AK-47 | Redline (FT)', weaponType: 'AK-47', itemName: 'Redline', condition: 'Field-Tested', stattrak: false, currentPriceCents: 4000, changeCents: 300 },
  { marketHashName: 'AK-47 | Vulcan (MW) ST', weaponType: 'AK-47', itemName: 'Vulcan', condition: 'Minimal Wear', stattrak: true, currentPriceCents: 14500, changeCents: -200 },
  { marketHashName: 'AWP | Asiimov (BS)', weaponType: 'AWP', itemName: 'Asiimov', condition: 'Battle-Scarred', stattrak: false, currentPriceCents: 5800, changeCents: 100 },
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
    expect(result.map((i) => i.changeCents)).toEqual([300, 100, -200])
  })

  test('delta_asc orders biggest losers first', () => {
    const result = applySort(items, 'delta_asc')
    expect(result.map((i) => i.changeCents)).toEqual([-200, 100, 300])
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
