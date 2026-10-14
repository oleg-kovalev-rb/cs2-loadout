export const initialState = {
  page: 1,
  perPage: 25,
}

export function inventoryValueLogsReducer(state, action) {
  switch (action.type) {
    case 'PAGE_CHANGED':
      return { ...state, page: action.page }

    case 'PER_PAGE_CHANGED':
      return { ...state, perPage: action.perPage, page: 1 }

    default:
      return state
  }
}
