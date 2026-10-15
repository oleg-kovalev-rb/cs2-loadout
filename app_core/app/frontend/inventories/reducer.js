export const initialCatalogState = {
  sort: 'value_desc',
  page: 1,
  openDropdown: null, // 'sort' | null
}

export function catalogReducer(state, action) {
  switch (action.type) {
    case 'SORT_CHANGED':
      return { ...state, sort: action.sort, page: 1, openDropdown: null }

    case 'PAGE_CHANGED':
      return { ...state, page: action.page }

    case 'DROPDOWN_TOGGLED':
      return {
        ...state,
        openDropdown: state.openDropdown === action.dropdown ? null : action.dropdown,
      }

    case 'DROPDOWNS_CLOSED':
      return state.openDropdown === null ? state : { ...state, openDropdown: null }

    default:
      return state
  }
}

export const initialDetailState = {
  range: '7d',
  itemsSort: 'price_desc',
  itemsPage: 1,
  openDropdown: null, // 'itemsSort' | null
}

export function detailReducer(state, action) {
  switch (action.type) {
    case 'RANGE_CHANGED':
      return { ...state, range: action.range }

    case 'ITEMS_SORT_CHANGED':
      return { ...state, itemsSort: action.itemsSort, itemsPage: 1, openDropdown: null }

    case 'ITEMS_PAGE_CHANGED':
      return { ...state, itemsPage: action.itemsPage }

    case 'DROPDOWN_TOGGLED':
      return {
        ...state,
        openDropdown: state.openDropdown === action.dropdown ? null : action.dropdown,
      }

    case 'DROPDOWNS_CLOSED':
      return state.openDropdown === null ? state : { ...state, openDropdown: null }

    default:
      return state
  }
}
