// Filter-chip option lists, derived from whichever page of the catalog is
// currently loaded — the same "present in what we actually have" pattern
// dashboard/utils/filters.js already uses for weaponTypesPresent/
// conditionsPresent, not a hardcoded universe (category/rarity are open,
// Steam-sourced string sets with no enumerated list anywhere in this
// codebase — see public-api-controllers.md's "open string-set array
// params" rule for why the backend itself never validates against one).
export function categoriesPresent(items) {
  return [...new Set(items.map((item) => item.category))].filter(Boolean).sort()
}

export function raritiesPresent(items) {
  return [...new Set(items.map((item) => item.rarity))].filter(Boolean).sort()
}
