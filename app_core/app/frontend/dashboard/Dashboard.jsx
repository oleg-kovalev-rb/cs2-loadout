import { useMemo, useReducer } from 'react'
import { dashboardReducer, initialState } from './reducer'
import { useDashboardData } from './hooks/useDashboardData'
import { useItemPrices } from './hooks/useItemPrices'
import { useItemTrend } from './hooks/useItemTrend'
import { usePortfolioHistory } from './hooks/usePortfolioHistory'
import { useItemHistory } from './hooks/useItemHistory'
import { DashboardSkeleton } from './components/DashboardSkeleton'
import { PortfolioTile } from './components/PortfolioTile'
import { ItemsTile } from './components/ItemsTile'
import { MarketVolumeTile } from './components/MarketVolumeTile'
import { marketVolume } from './utils/marketVolume'

export function Dashboard({ fetcherUrl, bridgeToken }) {
  const { data, status, error } = useDashboardData(fetcherUrl, bridgeToken)
  const [state, dispatch] = useReducer(dashboardReducer, initialState)

  // The full skeleton name list — stable across re-renders as long as the
  // skeleton itself hasn't changed. Gates useItemPrices/useItemTrend so
  // they only fire once the skeleton has resolved (and therefore
  // UserInventoryCache is guaranteed to have a row for this steam_id).
  const names = useMemo(() => (data ? data.items.map((item) => item.marketHashName) : []), [data])

  const { pricesByName } = useItemPrices(fetcherUrl, bridgeToken, names)
  const { trendByName, status: trendStatus } = useItemTrend(fetcherUrl, bridgeToken, names)
  const portfolioHistory = usePortfolioHistory(fetcherUrl, bridgeToken, state.portfolioRange)
  const itemHistory = useItemHistory(fetcherUrl, bridgeToken, state.selectedItem?.marketHashName ?? null, state.itemRange)

  const items = useMemo(() => {
    if (!data) return []
    return data.items.map((item) => ({
      ...item,
      ...(pricesByName[item.marketHashName] || {}),
      trendPoints: trendByName[item.marketHashName] || [],
    }))
  }, [data, pricesByName, trendByName])

  if (status === 'loading') {
    return <DashboardSkeleton />
  }

  if (status === 'error') {
    return <p className="dash-loading dash-loading-error">Couldn&rsquo;t load the dashboard: {error?.message}</p>
  }

  const selectedItem = state.selectedItem
    ? items.find((item) => item.marketHashName === state.selectedItem.marketHashName) || state.selectedItem
    : null

  return (
    <main className="dashboard">
      <PortfolioTile
        portfolioSeries={portfolioHistory.series}
        itemHistorySeries={itemHistory.series}
        itemHistoryStatus={itemHistory.status}
        range={state.mode === 'item' ? state.itemRange : state.portfolioRange}
        mode={state.mode}
        selectedItem={selectedItem}
        onRangeChange={(range) =>
          dispatch({ type: state.mode === 'item' ? 'ITEM_RANGE_CHANGED' : 'PORTFOLIO_RANGE_CHANGED', range })
        }
        onBack={() => dispatch({ type: 'BACK_TO_PORTFOLIO' })}
      />

      <ItemsTile
        items={items}
        filters={state.filters}
        sort={state.sort}
        page={state.page}
        openDropdown={state.openDropdown}
        selectedItem={selectedItem}
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

      <MarketVolumeTile marketVolume={marketVolume(items)} historyStatus={trendStatus} />
    </main>
  )
}
