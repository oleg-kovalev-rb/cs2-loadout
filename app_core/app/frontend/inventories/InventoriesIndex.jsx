import { useReducer } from 'react'
import { catalogReducer, initialCatalogState } from './reducer'
import { useInventoryCatalog } from './hooks/useInventoryCatalog'
import { InventoriesToolbar } from './components/InventoriesToolbar'
import { InventoryGrid } from './components/InventoryGrid'
import { Pagination } from '../shared/components/Pagination'

const PER_PAGE = 24

export function InventoriesIndex({ fetcherUrl }) {
  const [state, dispatch] = useReducer(catalogReducer, initialCatalogState)
  const { inventories, meta, status } = useInventoryCatalog(fetcherUrl, {
    page: state.page,
    sort: state.sort,
  })

  if (status === 'loading') {
    return <p className="dash-loading">Loading inventories…</p>
  }

  if (status === 'error') {
    return <p className="dash-loading dash-loading-error">Couldn&rsquo;t load inventories.</p>
  }

  const totalPages = meta?.total_pages ?? 1
  const totalCount = meta?.total_count ?? 0

  return (
    <main>
      <div className="page-head">
        <div>
          <h1 className="page-title">Inventories</h1>
          <p className="page-sub">
            <strong>{totalCount}</strong> public CS2 inventories tracked &middot; browse what
            players are holding
          </p>
        </div>
      </div>

      <InventoriesToolbar
        sort={state.sort}
        openDropdown={state.openDropdown}
        onDropdownToggle={(dropdown) => dispatch({ type: 'DROPDOWN_TOGGLED', dropdown })}
        onDropdownsClosed={() => dispatch({ type: 'DROPDOWNS_CLOSED' })}
        onSortChange={(sort) => dispatch({ type: 'SORT_CHANGED', sort })}
      />

      <InventoryGrid inventories={inventories} meta={meta} />

      <Pagination
        page={state.page - 1}
        totalPages={totalPages}
        totalCount={totalCount}
        pageSize={PER_PAGE}
        onPrev={() => dispatch({ type: 'PAGE_CHANGED', page: state.page - 1 })}
        onNext={() => dispatch({ type: 'PAGE_CHANGED', page: state.page + 1 })}
      />
    </main>
  )
}
