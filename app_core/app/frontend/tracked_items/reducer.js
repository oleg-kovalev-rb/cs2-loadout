export const initialState = {
  search: '',
  categories: new Set(),
  rarities: new Set(),
  stattrakOnly: false,
  sort: 'change_24h_desc',
  view: 'ticker', // 'ticker' | 'grid'
  page: 1,
  perPage: 25,
  openDropdown: null, // 'filter' | 'sort' | null
}

function toggleSetMember(set, value) {
  const next = new Set(set)
  if (next.has(value)) next.delete(value)
  else next.add(value)
  return next
}

export function trackedItemsReducer(state, action) {
  switch (action.type) {
    case 'SEARCH_CHANGED':
      return { ...state, search: action.value, page: 1 }

    case 'CATEGORY_TOGGLED':
      return { ...state, categories: toggleSetMember(state.categories, action.value), page: 1 }

    case 'RARITY_TOGGLED':
      return { ...state, rarities: toggleSetMember(state.rarities, action.value), page: 1 }

    case 'STATTRAK_TOGGLED':
      return { ...state, stattrakOnly: !state.stattrakOnly, page: 1 }

    case 'SORT_CHANGED':
      return { ...state, sort: action.sort, page: 1, openDropdown: null }

    case 'VIEW_CHANGED':
      return { ...state, view: action.view }

    case 'PAGE_CHANGED':
      return { ...state, page: action.page }

    case 'PER_PAGE_CHANGED':
      return { ...state, perPage: action.perPage, page: 1 }

    case 'FILTERS_CLEARED':
      return {
        ...state,
        search: initialState.search,
        categories: initialState.categories,
        rarities: initialState.rarities,
        stattrakOnly: initialState.stattrakOnly,
        page: 1,
      }

    case 'DROPDOWN_TOGGLED':
      return { ...state, openDropdown: state.openDropdown === action.dropdown ? null : action.dropdown }

    case 'DROPDOWNS_CLOSED':
      return state.openDropdown === null ? state : { ...state, openDropdown: null }

    default:
      return state
  }
}

export function activeFilterCount(state) {
  return state.categories.size + state.rarities.size + (state.stattrakOnly ? 1 : 0)
}
