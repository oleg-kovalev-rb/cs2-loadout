import { useReducer } from 'react'
import { detailReducer, initialDetailState } from './reducer'
import { useInventoryDetail } from './hooks/useInventoryDetail'
import { PortfolioHeroTile } from './components/PortfolioHeroTile'
import { StatTile } from './components/StatTile'
import { RarityLegend } from './components/RarityLegend'
import { TopItemsList } from './components/TopItemsList'
import { InventoryDetailSkeleton } from './components/InventoryDetailSkeleton'
import { InventoryNotFound } from './components/InventoryNotFound'
import { fmtUSD, fmtPrice, centsToUSD, fmtDateTime } from '../shared/utils/format'

const ITEMS_PER_PAGE = 12

export function InventoryDetail({ fetcherUrl, steamId }) {
  const [state, dispatch] = useReducer(detailReducer, initialDetailState)
  const { data, status } = useInventoryDetail(fetcherUrl, steamId, {
    range: state.range,
    itemsSort: state.itemsSort,
    itemsPage: state.itemsPage,
    itemsPerPage: ITEMS_PER_PAGE,
  })

  if (status === 'loading') return <InventoryDetailSkeleton />
  if (status === 'not_found') return <InventoryNotFound />
  if (status === 'error') {
    return <p className="dash-loading dash-loading-error">Couldn&rsquo;t load this inventory.</p>
  }

  const priciest = data.priciestItem

  return (
    <main>
      <a className="hero-back" href="/inventories">
        ‹ Inventories
      </a>

      <div className="profile-head">
        <span className="profile-head-avatar" aria-hidden="true" />
        <div>
          <div className="profile-head-name">
            <span>{data.steamId}</span>
          </div>
          <p className="profile-head-sub">Public inventory &middot; synced {fmtDateTime(new Date(data.lastSyncedAt).getTime())}</p>
        </div>
      </div>

      <div className="detail-grid">
        <PortfolioHeroTile portfolio={data.portfolio} onRangeChange={(range) => dispatch({ type: 'RANGE_CHANGED', range })} />

        <StatTile label="Items" value={data.itemsCount.toLocaleString('en-US')} />
        <StatTile label="Avg. item value" value={fmtUSD(centsToUSD(data.avgItemValueCents))} />
        <StatTile
          label="Priciest item"
          value={priciest ? fmtPrice(priciest.currentPriceCents) : '—'}
          note={priciest ? (priciest.weaponType ? `${priciest.weaponType} | ${priciest.itemName}` : priciest.itemName) : 'No priced items yet'}
        />

        <RarityLegend breakdown={data.rarityBreakdown} />

        <TopItemsList
          topItems={data.topItems}
          itemsSort={state.itemsSort}
          itemsPage={state.itemsPage}
          openDropdown={state.openDropdown}
          onDropdownToggle={(dropdown) => dispatch({ type: 'DROPDOWN_TOGGLED', dropdown })}
          onDropdownsClosed={() => dispatch({ type: 'DROPDOWNS_CLOSED' })}
          onItemsSortChange={(itemsSort) => dispatch({ type: 'ITEMS_SORT_CHANGED', itemsSort })}
          onItemsPageChange={(itemsPage) => dispatch({ type: 'ITEMS_PAGE_CHANGED', itemsPage })}
        />
      </div>
    </main>
  )
}
