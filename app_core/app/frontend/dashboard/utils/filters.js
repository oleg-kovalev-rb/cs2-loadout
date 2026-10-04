// Canonical wear-order vocabulary, used both to filter and to order
// whichever of these are actually present in a given inventory (see
// conditionsPresent) — not shown in full regardless of inventory contents.
export const CONDITIONS = ['Factory New', 'Minimal Wear', 'Field-Tested', 'Well-Worn', 'Battle-Scarred']

export function applyFilters(items, filters) {
  return items.filter((item) => {
    if (filters.weapons.size > 0 && !filters.weapons.has(item.weaponType)) return false
    if (filters.conditions.size > 0 && !filters.conditions.has(item.condition)) return false
    if (filters.stattrakOnly && !item.stattrak) return false
    return true
  })
}

export function weaponTypesPresent(items) {
  return [...new Set(items.map((item) => item.weaponType))].filter(Boolean).sort()
}

export function conditionsPresent(items) {
  const present = new Set(items.map((item) => item.condition))
  return CONDITIONS.filter((condition) => present.has(condition))
}

export function stattrakPresent(items) {
  return items.some((item) => item.stattrak)
}

export function changePct(item) {
  return item.change24hPercent || 0
}

export const SORTERS = {
  delta_desc: (a, b) => changePct(b) - changePct(a),
  delta_asc: (a, b) => changePct(a) - changePct(b),
  price_desc: (a, b) => b.currentPriceCents - a.currentPriceCents,
  price_asc: (a, b) => a.currentPriceCents - b.currentPriceCents,
  name_asc: (a, b) => `${a.weaponType} ${a.itemName}`.localeCompare(`${b.weaponType} ${b.itemName}`),
}

export const SORT_LABELS = {
  delta_desc: '24h Δ ↓',
  delta_asc: '24h Δ ↑',
  price_desc: 'Price ↓',
  price_asc: 'Price ↑',
  name_asc: 'Name A–Z',
}

export function applySort(items, sortKey) {
  return [...items].sort(SORTERS[sortKey])
}
