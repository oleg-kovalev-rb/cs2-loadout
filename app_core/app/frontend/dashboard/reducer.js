export const PAGE_SIZE = 8

export const initialState = {
  mode: 'portfolio', // 'portfolio' | 'item'
  portfolioRange: '7d', // '7d' | '30d' | '1y' | 'all'
  itemRange: '7d', // '24h' | '7d' | '30d' | '1y' | 'all'
  selectedItem: null,
  sort: 'delta_desc',
  filters: { weapons: new Set(), conditions: new Set(), stattrakOnly: false },
  page: 0,
  openDropdown: null, // 'sort' | 'filter' | null
}

function toggleSetMember(set, value) {
  const next = new Set(set)
  if (next.has(value)) next.delete(value)
  else next.add(value)
  return next
}

export function dashboardReducer(state, action) {
  switch (action.type) {
    case 'PORTFOLIO_RANGE_CHANGED':
      return { ...state, portfolioRange: action.range }

    case 'ITEM_RANGE_CHANGED':
      return { ...state, itemRange: action.range }

    case 'ITEM_ROW_CLICKED': {
      const alreadySelected = state.selectedItem?.marketHashName === action.item.marketHashName
      return alreadySelected
        ? { ...state, mode: 'portfolio', selectedItem: null }
        : { ...state, mode: 'item', selectedItem: action.item }
    }

    case 'BACK_TO_PORTFOLIO':
      return { ...state, mode: 'portfolio', selectedItem: null }

    case 'SORT_CHANGED':
      return { ...state, sort: action.sort, page: 0, openDropdown: null }

    case 'WEAPON_FILTER_TOGGLED':
      return { ...state, filters: { ...state.filters, weapons: toggleSetMember(state.filters.weapons, action.value) }, page: 0 }

    case 'CONDITION_FILTER_TOGGLED':
      return { ...state, filters: { ...state.filters, conditions: toggleSetMember(state.filters.conditions, action.value) }, page: 0 }

    case 'STATTRAK_FILTER_TOGGLED':
      return { ...state, filters: { ...state.filters, stattrakOnly: !state.filters.stattrakOnly }, page: 0 }

    case 'FILTERS_CLEARED':
      return { ...state, filters: initialState.filters, page: 0 }

    case 'PAGE_CHANGED':
      return { ...state, page: action.page }

    case 'DROPDOWN_TOGGLED':
      return { ...state, openDropdown: state.openDropdown === action.dropdown ? null : action.dropdown }

    case 'DROPDOWNS_CLOSED':
      return state.openDropdown === null ? state : { ...state, openDropdown: null }

    default:
      return state
  }
}

export function activeFilterCount(filters) {
  return filters.weapons.size + filters.conditions.size + (filters.stattrakOnly ? 1 : 0)
}
