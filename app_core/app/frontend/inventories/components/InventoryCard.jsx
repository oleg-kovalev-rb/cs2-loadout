import { fmtUSD, centsToUSD, fmtDateTime } from '../../shared/utils/format'
import { trendDirection } from '../../shared/utils/trend'
import { RarityMixBar } from './RarityMixBar'
import { rarityPercentages } from '../utils/rarity'

// The nickname/avatar come from app_core's own enrichment endpoint (see
// agent/styleguides/core/architecture-layers.md's app_core-owned
// enrichment carve-out). app_fetcher's public inventories response
// deliberately carries neither, so `profile` is optional and the card
// falls back to steam_id + a letter-circle avatar.
export function InventoryCard({ inventory, rank, profile }) {
  const direction = trendDirection(inventory.change24hPercent)
  const name = profile?.nickname || inventory.steamId
  const initial = name.charAt(0).toUpperCase()
  const showDelta =
    direction !== 'flat' && inventory.changeAvailable !== false && !inventory.changePartial
  const showPartial = inventory.complete === false
  const partialLabel =
    inventory.pricedItemsCount != null && inventory.pricableItemsCount != null
      ? `${inventory.pricedItemsCount}/${inventory.pricableItemsCount} priced`
      : 'Partial'
  const changeTitle = inventory.changeBasisAt
    ? `Change since ${new Date(inventory.changeBasisAt).toISOString().slice(0, 10)}`
    : undefined

  return (
    <a className="inv-card" href={`/inventories/${inventory.steamId}`}>
      <div className="inv-card-top">
        <span className="inv-rank tabular">#{rank}</span>
        {profile?.avatarUrl ? (
          <img className="inv-avatar" src={profile.avatarUrl} alt="" />
        ) : (
          <span className="inv-avatar" aria-hidden="true">
            {initial}
          </span>
        )}
        <span className="inv-id">
          <span className="inv-name">{name}</span>
        </span>
      </div>
      <div className="inv-value-row">
        <span className="inv-value tabular">{fmtUSD(centsToUSD(inventory.totalValueCents))}</span>
        {showPartial && <span className="inv-partial tabular">{partialLabel}</span>}
        {showDelta && (
          <span
            className={`inv-delta tabular ${direction === 'up' ? 'is-up' : 'is-down'}`}
            title={changeTitle}
          >
            {direction === 'up' ? '▲' : '▼'} {Math.abs(inventory.change24hPercent).toFixed(1)}%
          </span>
        )}
      </div>
      <RarityMixBar
        percentages={rarityPercentages(inventory.rarityBreakdown)}
        className="inv-mix"
      />
      <div className="inv-card-foot">
        <span>{inventory.itemsCount} items</span>
        <span>synced {fmtDateTime(new Date(inventory.lastSyncedAt).getTime())}</span>
      </div>
    </a>
  )
}
