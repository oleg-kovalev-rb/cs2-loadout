import { Sparkline } from '../../shared/components/Sparkline'
import { trendDirection } from '../../shared/utils/trend'
import { fmtPrice, conditionAbbr } from '../../shared/utils/format'

// Read-only — unlike dashboard's ItemRow, there's no selection/drill-down
// here (no second user's items to switch into "item mode" for), so this
// renders a plain row, not a clickable button.
export function InventoryItemRow({ item }) {
  const hasPrice = item.currentPriceCents != null
  const pct = item.change24hPercent
  const direction = trendDirection(pct)
  const showDelta = hasPrice && direction !== 'flat'
  const arrow = direction === 'up' ? '▲' : '▼'
  const sparkValues = item.trendPoints.map((point) => point.priceCents)

  return (
    <li>
      <div className="mover-row">
        {item.iconUrl ? (
          <img className="mover-icon" src={item.iconUrl} alt="" />
        ) : (
          <span className="mover-icon" aria-hidden="true" />
        )}
        <span className="mover-id">
          <span className="mover-name">
            {item.weaponType ? `${item.weaponType} | ${item.itemName}` : item.itemName}
          </span>
          <span className="mover-tags">
            {item.stattrak && <span className="tag tag-stattrak">ST</span>}
            <span className="tag tag-condition">{conditionAbbr(item.condition)}</span>
          </span>
        </span>
        <Sparkline values={sparkValues} variant={direction} />
        <span className="mover-figures">
          <span className="mover-price tabular">{fmtPrice(item.currentPriceCents)}</span>
          {showDelta && (
            <span className={`mover-delta tabular ${direction}`}>
              {arrow} {Math.abs(pct).toFixed(1)}%
            </span>
          )}
        </span>
      </div>
    </li>
  )
}
