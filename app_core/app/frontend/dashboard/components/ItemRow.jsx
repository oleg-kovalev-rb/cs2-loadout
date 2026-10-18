import { Sparkline } from '../../shared/components/Sparkline'
import { trendDirection } from '../../shared/utils/trend'
import { fmtPrice, conditionAbbr } from '../../shared/utils/format'
import { isPriceStale, priceAgeLabel } from '../../shared/utils/priceFreshness'
import { changePct } from '../utils/filters'

export function ItemRow({ item, isSelected, onSelect }) {
  const hasPrice = item.currentPriceCents != null
  const isTradable = item.currentPriceCents !== 0
  const pct = changePct(item)
  const direction = trendDirection(pct)
  const showDelta = isTradable && hasPrice && direction !== 'flat'
  const arrow = direction === 'up' ? '▲' : '▼'
  const sparkValues = item.trendPoints.map((point) => point.priceCents)
  const stale = isPriceStale(item.priceUpdatedAt)

  return (
    <li>
      <button
        type="button"
        className={`mover-row${isSelected ? ' is-selected' : ''}`}
        onClick={() => onSelect(item)}
      >
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
          <span
            className={`mover-price tabular${stale ? ' is-stale' : ''}`}
            title={stale ? `Price updated ${priceAgeLabel(item.priceUpdatedAt)}` : undefined}
          >
            {fmtPrice(item.currentPriceCents)}
          </span>
          {showDelta && (
            <span className={`mover-delta tabular ${direction}`}>
              {arrow} {Math.abs(pct).toFixed(1)}%
            </span>
          )}
        </span>
      </button>
    </li>
  )
}
