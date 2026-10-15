import { useMemo, useReducer } from 'react'
import { trackedItemsReducer, initialState } from './reducer'
import { useItemsCatalog } from './hooks/useItemsCatalog'
import { categoriesPresent, raritiesPresent } from './utils/options'
import { stattrakPresent } from '../dashboard/utils/filters'
import { CatalogSkeleton } from './components/CatalogSkeleton'
import { StatStrip } from './components/StatStrip'
import { CatalogToolbar } from './components/CatalogToolbar'
import { TickerView } from './components/TickerView'
import { GridView } from './components/GridView'
import { CatalogPagination } from './components/CatalogPagination'

export function TrackedItems({ fetcherUrl }) {
  const [state, dispatch] = useReducer(trackedItemsReducer, initialState)

  const { data, status, error } = useItemsCatalog(fetcherUrl, {
    search: state.search,
    categories: state.categories,
    rarities: state.rarities,
    stattrakOnly: state.stattrakOnly,
    sort: state.sort,
    page: state.page,
    perPage: state.perPage,
  })

  const items = data ? data.items : []

  const { availableCategories, availableRarities, showStattrak } = useMemo(
    () => ({
      availableCategories: categoriesPresent(items),
      availableRarities: raritiesPresent(items),
      showStattrak: stattrakPresent(items),
    }),
    [items],
  )

  if (status === 'loading' && !data) {
    return <CatalogSkeleton />
  }

  if (status === 'error' && !data) {
    return (
      <p className="dash-loading dash-loading-error">
        Couldn&rsquo;t load tracked items: {error?.message}
      </p>
    )
  }

  return (
    <main className="catalog">
      <StatStrip
        totalCount={data.meta.totalCount}
        gainingCount={data.meta.gainingCount}
        losingCount={data.meta.losingCount}
      />

      <CatalogToolbar
        search={state.search}
        onSearchChange={(value) => dispatch({ type: 'SEARCH_CHANGED', value })}
        openDropdown={state.openDropdown}
        onDropdownToggle={(dropdown) => dispatch({ type: 'DROPDOWN_TOGGLED', dropdown })}
        onDropdownsClosed={() => dispatch({ type: 'DROPDOWNS_CLOSED' })}
        categories={state.categories}
        rarities={state.rarities}
        stattrakOnly={state.stattrakOnly}
        availableCategories={availableCategories}
        availableRarities={availableRarities}
        showStattrak={showStattrak}
        onCategoryToggle={(value) => dispatch({ type: 'CATEGORY_TOGGLED', value })}
        onRarityToggle={(value) => dispatch({ type: 'RARITY_TOGGLED', value })}
        onStattrakToggle={() => dispatch({ type: 'STATTRAK_TOGGLED' })}
        onFiltersClear={() => dispatch({ type: 'FILTERS_CLEARED' })}
        sort={state.sort}
        onSortChange={(sort) => dispatch({ type: 'SORT_CHANGED', sort })}
        view={state.view}
        onViewChange={(view) => dispatch({ type: 'VIEW_CHANGED', view })}
      />

      {state.view === 'ticker' ? <TickerView items={items} /> : <GridView items={items} />}

      <CatalogPagination
        page={data.meta.page}
        totalPages={data.meta.totalPages}
        totalCount={data.meta.totalCount}
        perPage={data.meta.perPage}
        onPrev={() => dispatch({ type: 'PAGE_CHANGED', page: state.page - 1 })}
        onNext={() => dispatch({ type: 'PAGE_CHANGED', page: state.page + 1 })}
        onPerPageChange={(perPage) => dispatch({ type: 'PER_PAGE_CHANGED', perPage })}
      />
    </main>
  )
}
