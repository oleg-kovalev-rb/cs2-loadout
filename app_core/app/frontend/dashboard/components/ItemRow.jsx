import { Sparkline } from './Sparkline'
import { fmtPrice, conditionAbbr } from '../utils/format'
import { changePct } from '../utils/filters'

export function ItemRow({ item, isSelected, onSelect }) {
  const hasPrice = item.currentPriceCents != null
  const isTradable = item.currentPriceCents !== 0
  const showDelta = isTradable && hasPrice
  const pct = changePct(item)
  const direction = pct >= 0 ? 'up' : 'down'
  const arrow = pct >= 0 ? '▲' : '▼'
  const sparkValues = item.trendPoints.map((point) => point.priceCents)

  return (
    <li>
      <button
        type="button"
        className={`mover-row${isSelected ? ' is-selected' : ''}`}
        onClick={() => onSelect(item)}
      >
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
      </button>
    </li>
  )
}
