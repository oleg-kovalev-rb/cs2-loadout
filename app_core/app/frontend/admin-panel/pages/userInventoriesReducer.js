import { toggleSetMember } from '../../shared/utils/sets'

export const initialState = {
  page: 1,
  perPage: 25,
  selectedIds: new Set(),
  expandedSteamIds: new Set(),
}

export function userInventoriesReducer(state, action) {
  switch (action.type) {
    case 'PAGE_CHANGED':
      return { ...state, page: action.page, selectedIds: new Set() }

    case 'PER_PAGE_CHANGED':
      return { ...state, perPage: action.perPage, page: 1, selectedIds: new Set() }

    case 'ROW_TOGGLED':
      return { ...state, selectedIds: toggleSetMember(state.selectedIds, action.steamId) }

    case 'ALL_TOGGLED':
      return { ...state, selectedIds: action.checked ? new Set(action.steamIds) : new Set() }

    case 'SELECTION_CLEARED':
      return { ...state, selectedIds: new Set() }

    case 'ROW_EXPAND_TOGGLED':
      return { ...state, expandedSteamIds: toggleSetMember(state.expandedSteamIds, action.steamId) }

    default:
      return state
  }
}
