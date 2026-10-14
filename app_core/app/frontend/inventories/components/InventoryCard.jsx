import { fmtUSD, centsToUSD, fmtDateTime } from '../../shared/utils/format'
import { RarityMixBar } from './RarityMixBar'

// No nickname/avatar/steam_level here by design — app_fetcher's public
// inventories response deliberately excludes app_core-owned profile
// fields (see the architecture-layers.md amendment). steam_id is the
// only identity shown.
export function InventoryCard({ inventory, rank }) {
  const up = inventory.change24hPercent >= 0

  return (
    <a className="inv-card" href={`/inventories/${inventory.steamId}`}>
      <div className="inv-card-top">
        <span className="inv-rank tabular">#{rank}</span>
        <span className="inv-avatar" aria-hidden="true" />
        <span className="inv-id">
          <span className="inv-name">{inventory.steamId}</span>
        </span>
      </div>
      <div className="inv-value-row">
        <span className="inv-value tabular">{fmtUSD(centsToUSD(inventory.totalValueCents))}</span>
        <span className={`inv-delta tabular ${up ? 'is-up' : 'is-down'}`}>
          {up ? '▲' : '▼'} {Math.abs(inventory.change24hPercent).toFixed(1)}%
        </span>
      </div>
      <RarityMixBar percentages={inventory.rarityMixPercent} className="inv-mix" />
      <div className="inv-card-foot">
        <span>{inventory.itemsCount} items</span>
        <span>synced {fmtDateTime(new Date(inventory.lastSyncedAt).getTime())}</span>
      </div>
    </a>
  )
}
