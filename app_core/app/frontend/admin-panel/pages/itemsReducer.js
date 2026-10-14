export const initialState = {
  page: 1,
  perPage: 25,
  selectedIds: new Set(),
  isCreatePanelOpen: false,
  openRowMenuId: null,
}

function toggleSetMember(set, value) {
  const next = new Set(set)
  if (next.has(value)) next.delete(value)
  else next.add(value)
  return next
}

export function itemsReducer(state, action) {
  switch (action.type) {
    case 'PAGE_CHANGED':
      return { ...state, page: action.page, selectedIds: new Set() }

    case 'PER_PAGE_CHANGED':
      return { ...state, perPage: action.perPage, page: 1, selectedIds: new Set() }

    case 'ROW_TOGGLED':
      return { ...state, selectedIds: toggleSetMember(state.selectedIds, action.id) }

    case 'ALL_TOGGLED':
      return { ...state, selectedIds: action.checked ? new Set(action.ids) : new Set() }

    case 'SELECTION_CLEARED':
      return { ...state, selectedIds: new Set() }

    case 'CREATE_PANEL_TOGGLED':
      return { ...state, isCreatePanelOpen: !state.isCreatePanelOpen }

    case 'CREATE_PANEL_CLOSED':
      return { ...state, isCreatePanelOpen: false }

    case 'ROW_MENU_TOGGLED':
      return { ...state, openRowMenuId: state.openRowMenuId === action.id ? null : action.id }

    case 'ROW_MENU_CLOSED':
      return { ...state, openRowMenuId: null }

    case 'ALL_MENUS_CLOSED':
      return { ...state, openRowMenuId: null }

    default:
      return state
  }
}
