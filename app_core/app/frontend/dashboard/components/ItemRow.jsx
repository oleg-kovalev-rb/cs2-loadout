import { Sparkline } from './Sparkline'
import { itemSeries } from '../utils/itemSeries'
import { fmtPrice, conditionAbbr } from '../utils/format'
import { changePct } from '../utils/filters'

export function ItemRow({ item, isSelected, onSelect }) {
  const isTradable = item.currentPriceCents !== 0
  const hasHistory = item.priceHistory.length > 0
  const showDelta = isTradable && hasHistory
  const pct = changePct(item) * 100
  const direction = pct >= 0 ? 'up' : 'down'
  const arrow = pct >= 0 ? '▲' : '▼'
  const sparkValues = itemSeries(item, '7d').map((point) => point.value)

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
