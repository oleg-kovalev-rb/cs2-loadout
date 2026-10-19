import { RarityMixBar } from './RarityMixBar'
import { rarityPercentages, rarityTier } from '../utils/rarity'

export function RarityLegend({ breakdown }) {
  const percentages = rarityPercentages(breakdown)

  return (
    <section className="tile tile-rarity">
      <header className="tile-head">
        <h2>Rarity mix</h2>
      </header>
      <RarityMixBar percentages={percentages} />
      <div className="rarity-legend">
        {breakdown.map((row) => {
          const tier = rarityTier(row.tier)
          return (
            <div className="rarity-row" key={row.tier}>
              <span className="rarity-dot" style={{ background: `var(${tier.cssVar})` }} />
              <span className="rarity-name">{tier.label}</span>
              <span className="rarity-count">{row.count}</span>
              <span className="rarity-pct tabular">{row.percent.toFixed(1)}%</span>
            </div>
          )
        })}
      </div>
    </section>
  )
}
