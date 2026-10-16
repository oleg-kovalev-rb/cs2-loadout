import { RangeToggle } from '../../shared/components/RangeToggle'
import { HeroChart } from '../../shared/components/HeroChart'
import { fmtUSD, centsToUSD } from '../../shared/utils/format'
import { INVENTORY_DETAIL_RANGES } from '../chartConfig'

// Read-only, unlike dashboard's PortfolioTile — there's no item-mode
// toggle here, just this one inventory's value over time.
export function PortfolioHeroTile({ portfolio, onRangeChange }) {
  const up = portfolio.changeCents >= 0
  // A single-point history (no change) must not read as a green "▲ $0.00";
  // see react-dashboard.md's hero-delta rule.
  const showDelta = portfolio.changeCents !== 0

  return (
    <section className="tile tile-hero">
      <header className="tile-head">
        <h2>Portfolio value</h2>
        <RangeToggle
          ranges={INVENTORY_DETAIL_RANGES}
          range={portfolio.range}
          onChange={onRangeChange}
        />
      </header>

      <div className="hero-value-row">
        <span className="hero-value tabular">{fmtUSD(centsToUSD(portfolio.totalValueCents))}</span>
        {showDelta && (
          <span className={`hero-delta tabular ${up ? 'is-up' : 'is-down'}`}>
            {up ? '▲' : '▼'} {fmtUSD(centsToUSD(Math.abs(portfolio.changeCents)))} ({up ? '+' : '-'}
            {Math.abs(portfolio.changePercent).toFixed(2)}%)
          </span>
        )}
      </div>

      <HeroChart values={portfolio.history} range={portfolio.range} />
    </section>
  )
}
