import { Sparkline } from './Sparkline'
import { itemSeries } from '../utils/itemSeries'
import { fmtUSD, centsToUSD, conditionAbbr } from '../utils/format'
import { changePct } from '../utils/filters'

export function ItemRow({ item, isSelected, onSelect }) {
  const direction = item.changeCents >= 0 ? 'up' : 'down'
  const arrow = item.changeCents >= 0 ? '▲' : '▼'
  const pct = changePct(item) * 100
  const sparkValues = itemSeries(item, '7d')

  return (
    <li>
      <button
        type="button"
        className={`mover-row${isSelected ? ' is-selected' : ''}`}
        onClick={() => onSelect(item)}
      >
        <span className="mover-id">
          <span className="mover-name">
            {item.weaponType} | {item.itemName}
          </span>
          <span className="mover-tags">
            {item.stattrak && <span className="tag tag-stattrak">ST</span>}
            <span className="tag tag-condition">{conditionAbbr(item.condition)}</span>
          </span>
        </span>
        <Sparkline values={sparkValues} variant={direction} />
        <span className="mover-figures">
          <span className="mover-price tabular">{fmtUSD(centsToUSD(item.currentPriceCents))}</span>
          <span className={`mover-delta tabular ${direction}`}>
            {arrow} {Math.abs(pct).toFixed(1)}%
          </span>
        </span>
      </button>
    </li>
  )
}
