import { useReducer } from 'react'
import { dashboardReducer, initialState } from './reducer'
import { useDashboardData } from './hooks/useDashboardData'
import { PortfolioTile } from './components/PortfolioTile'
import { ItemsTile } from './components/ItemsTile'
import { MarketVolumeTile } from './components/MarketVolumeTile'

export function Dashboard({ fetcherUrl, bridgeToken }) {
  const { data, status, error } = useDashboardData(fetcherUrl, bridgeToken)
  const [state, dispatch] = useReducer(dashboardReducer, initialState)

  if (status === 'loading') {
    return <p className="dash-loading">Loading dashboard…</p>
  }

  if (status === 'error') {
    return <p className="dash-loading dash-loading-error">Couldn&rsquo;t load the dashboard: {error?.message}</p>
  }

  return (
    <main className="dashboard">
      <PortfolioTile
        portfolio={data.portfolio}
        range={state.range}
        mode={state.mode}
        selectedItem={state.selectedItem}
        onRangeChange={(range) => dispatch({ type: 'RANGE_CHANGED', range })}
        onBack={() => dispatch({ type: 'BACK_TO_PORTFOLIO' })}
      />

      <ItemsTile
        items={data.items}
        filters={state.filters}
        sort={state.sort}
        page={state.page}
        openDropdown={state.openDropdown}
        selectedItem={state.selectedItem}
        onSelectItem={(item) => dispatch({ type: 'ITEM_ROW_CLICKED', item })}
        onSortChange={(sort) => dispatch({ type: 'SORT_CHANGED', sort })}
        onWeaponToggle={(value) => dispatch({ type: 'WEAPON_FILTER_TOGGLED', value })}
        onConditionToggle={(value) => dispatch({ type: 'CONDITION_FILTER_TOGGLED', value })}
        onStattrakToggle={() => dispatch({ type: 'STATTRAK_FILTER_TOGGLED' })}
        onFiltersClear={() => dispatch({ type: 'FILTERS_CLEARED' })}
        onDropdownToggle={(dropdown) => dispatch({ type: 'DROPDOWN_TOGGLED', dropdown })}
        onDropdownsClosed={() => dispatch({ type: 'DROPDOWNS_CLOSED' })}
        onPageChange={(page) => dispatch({ type: 'PAGE_CHANGED', page })}
      />

      <MarketVolumeTile marketVolume={data.marketVolume} />
    </main>
  )
}
