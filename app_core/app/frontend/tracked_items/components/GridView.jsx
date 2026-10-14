import { Sparkline } from '../../dashboard/components/Sparkline'
import { fmtPrice, conditionAbbr } from '../../dashboard/utils/format'
import { rarityColor } from '../utils/format'

function ItemCard({ item }) {
  const hasPrice = item.currentPriceCents != null
  const pct = item.change24hPercent || 0
  const direction = pct >= 0 ? 'up' : 'down'
  const arrow = pct >= 0 ? '▲' : '▼'
  const sparkValues = item.trendPoints.map((point) => point.priceCents)
  const gradientId = `tracked-item-spark-${item.marketHashName.replace(/[^a-zA-Z0-9]/g, '-')}`

  return (
    <div className="item-card">
      {item.iconUrl ? (
        <img className="card-icon" src={item.iconUrl} alt="" />
      ) : (
        <span className="card-icon" aria-hidden="true" />
      )}
      <div className="card-id">
        <span className="card-name">{item.weaponType ? `${item.weaponType} | ${item.itemName}` : item.itemName}</span>
        <span className="ticker-tags">
          {item.stattrak && <span className="tag tag-stattrak">ST</span>}
          <span className="tag tag-condition">{conditionAbbr(item.condition)}</span>
        </span>
      </div>
      <div className="card-price-row">
        <span className="card-price tabular">{fmtPrice(item.currentPriceCents)}</span>
        {hasPrice && (
          <span className={`card-delta ${direction}`}>
            {arrow} {Math.abs(pct).toFixed(1)}%
          </span>
        )}
      </div>
      {sparkValues.length > 0 && (
        <Sparkline
          values={sparkValues}
          variant={direction}
          width={180}
          height={36}
          showArea
          gradientId={gradientId}
          className="card-spark"
        />
      )}
      <div className="card-foot">
        <span className="rarity">
          <span className="dot" style={{ background: rarityColor(item.rarity) }} />
          {item.rarity}
        </span>
        <span className="ticker-cat">{item.category}</span>
      </div>
    </div>
  )
}

export function GridView({ items }) {
  if (items.length === 0) {
    return <p className="empty-state">No items match these filters.</p>
  }

  return (
    <div className="grid-view">
      {items.map((item) => (
        <ItemCard key={item.marketHashName} item={item} />
      ))}
    </div>
  )
}
