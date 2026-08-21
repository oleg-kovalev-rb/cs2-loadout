// Fixed vocabulary and display order — shown in full regardless of which
// conditions are actually present in the current inventory.
export const CONDITIONS = ['Factory New', 'Minimal Wear', 'Field-Tested', 'Well-Worn', 'Battle-Scarred']

export function applyFilters(items, filters) {
  return items.filter((item) => {
    if (filters.weapons.size > 0 && !filters.weapons.has(item.weaponType)) return false
    if (filters.conditions.size > 0 && !filters.conditions.has(item.condition)) return false
    if (filters.stattrakOnly && !item.stattrak) return false
    return true
  })
}

// The list displays each item's 24h change as a *percentage* (matching how
// differently-priced items are actually comparable), so sort by that same
// percentage rather than raw cents — otherwise a $5 move on a $50 item and a
// $5 move on a $5,000 item would tie for sort order despite showing very
// different percentages.
export function changePct(item) {
  const startCents = item.currentPriceCents - item.changeCents
  return startCents === 0 ? 0 : item.changeCents / startCents
}

export const SORTERS = {
  delta_desc: (a, b) => changePct(b) - changePct(a),
  delta_asc: (a, b) => changePct(a) - changePct(b),
  price_desc: (a, b) => b.currentPriceCents - a.currentPriceCents,
  price_asc: (a, b) => a.currentPriceCents - b.currentPriceCents,
  name_asc: (a, b) => `${a.weaponType} ${a.itemName}`.localeCompare(`${b.weaponType} ${b.itemName}`),
}

export const SORT_LABELS = {
  delta_desc: '24H Δ ↓',
  delta_asc: '24H Δ ↑',
  price_desc: 'Price ↓',
  price_asc: 'Price ↑',
  name_asc: 'Name A–Z',
}

export function applySort(items, sortKey) {
  return [...items].sort(SORTERS[sortKey])
}
