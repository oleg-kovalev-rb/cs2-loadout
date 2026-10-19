import { Sparkline } from '../../shared/components/Sparkline'
import { trendDirection } from '../../shared/utils/trend'
import { fmtPrice, conditionAbbr } from '../../shared/utils/format'
import { rarityColor } from '../utils/rarity'

function TickerRow({ item }) {
  const hasPrice = item.currentPriceCents != null
  const pct = item.change24hPercent || 0
  const direction = trendDirection(pct)
  const showDelta = hasPrice && direction !== 'flat'
  const arrow = direction === 'up' ? '▲' : '▼'
  const sparkValues = item.trendPoints.map((point) => point.priceCents)

  return (
    <div className="ticker-row">
      {item.iconUrl ? (
        <img className="ticker-icon" src={item.iconUrl} alt="" />
      ) : (
        <span className="ticker-icon" aria-hidden="true" />
      )}
      <span className="ticker-id">
        <span className="ticker-name">
          {item.weaponType ? `${item.weaponType} | ${item.itemName}` : item.itemName}
        </span>
        <span className="ticker-tags">
          {item.stattrak && <span className="tag tag-stattrak">ST</span>}
          <span className="tag tag-condition">{conditionAbbr(item.condition)}</span>
        </span>
      </span>
      <span className="ticker-figures">
        <span className="ticker-price tabular">{fmtPrice(item.currentPriceCents)}</span>
        {showDelta && (
          <span className={`ticker-delta tabular ${direction}`}>
            {arrow} {Math.abs(pct).toFixed(1)}%
          </span>
        )}
      </span>
      {sparkValues.length > 0 ? (
        <Sparkline values={sparkValues} variant={direction} />
      ) : (
        <span className="row-spark" aria-hidden="true" />
      )}
      <span className="rarity">
        <span className="dot" style={{ background: rarityColor(item.rarity) }} />
        {item.rarity}
      </span>
      <span className="ticker-cat">{item.category}</span>
    </div>
  )
}

export function TickerView({ items }) {
  if (items.length === 0) {
    return <p className="empty-state">No items match these filters.</p>
  }

  return (
    <div className="ticker-wrap">
      <div className="ticker">
        <div className="ticker-head">
          <span />
          <span>Item</span>
          <span className="num">Price / 24h</span>
          <span>7d</span>
          <span>Rarity</span>
          <span>Category</span>
        </div>
        {items.map((item) => (
          <TickerRow key={item.marketHashName} item={item} />
        ))}
      </div>
    </div>
  )
}
