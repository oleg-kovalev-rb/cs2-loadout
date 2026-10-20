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
import { TOP_ITEMS_PER_PAGE } from './constants'

export function InventoryDetail({
  fetcherUrl,
  steamId,
  profile,
  demo = false,
  demoToken = null,
  apiBase = '/api/public',
}) {
  const [state, dispatch] = useReducer(detailReducer, initialDetailState)
  const { data, status } = useInventoryDetail(fetcherUrl, steamId, {
    period: state.period,
    sort: state.sort,
    page: state.page,
    perPage: TOP_ITEMS_PER_PAGE,
    demo,
    demoToken,
    apiBase,
  })

  if (status === 'loading') return <InventoryDetailSkeleton />
  if (status === 'not_found') return <InventoryNotFound />
  if (status === 'error') {
    return <p className="dash-loading dash-loading-error">Couldn&rsquo;t load this inventory.</p>
  }

  const priciest = data.priciestItem
  const name = profile?.nickname || data.steamId
  const initial = name.charAt(0).toUpperCase()

  return (
    <main>
      <a className="hero-back" href="/inventories">
        ‹ Inventories
      </a>

      <div className="profile-head">
        {profile?.avatarUrl ? (
          <img className="profile-head-avatar" src={profile.avatarUrl} alt="" />
        ) : (
          <span className="profile-head-avatar" aria-hidden="true">
            {initial}
          </span>
        )}
        <div>
          <div className="profile-head-name">
            <span>{name}</span>
            {demo && <span className="badge badge-demo">Demo</span>}
          </div>
          <p className="profile-head-sub">
            {demo ? 'Demo inventory' : 'Public inventory'} &middot; synced{' '}
            {fmtDateTime(new Date(data.lastSyncedAt).getTime())}
          </p>
        </div>
      </div>

      <div className="detail-grid">
        <PortfolioHeroTile
          portfolio={data.portfolio}
          onPeriodChange={(period) => dispatch({ type: 'PERIOD_CHANGED', period })}
        />

        <StatTile label="Items" value={data.itemsCount.toLocaleString('en-US')} />
        <StatTile label="Avg. item value" value={fmtUSD(centsToUSD(data.avgItemValueCents))} />
        <StatTile
          label="Priciest item"
          value={priciest ? fmtPrice(priciest.currentPriceCents) : '—'}
          note={
            priciest
              ? priciest.weaponType
                ? `${priciest.weaponType} | ${priciest.itemName}`
                : priciest.itemName
              : 'No priced items yet'
          }
        />

        <RarityLegend breakdown={data.rarityBreakdown} />

        <TopItemsList
          topItems={data.topItems}
          sort={state.sort}
          page={state.page}
          openDropdown={state.openDropdown}
          onDropdownToggle={(dropdown) => dispatch({ type: 'DROPDOWN_TOGGLED', dropdown })}
          onDropdownsClosed={() => dispatch({ type: 'DROPDOWNS_CLOSED' })}
          onSortChange={(sort) => dispatch({ type: 'SORT_CHANGED', sort })}
          onPageChange={(page) => dispatch({ type: 'PAGE_CHANGED', page })}
        />
      </div>
    </main>
  )
}
