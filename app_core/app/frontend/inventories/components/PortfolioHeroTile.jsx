import { PeriodToggle } from '../../shared/components/PeriodToggle'
import { HeroChart } from '../../shared/components/HeroChart'
import { fmtUSD, centsToUSD } from '../../shared/utils/format'
import { INVENTORY_DETAIL_PERIODS } from '../chartConfig'

// Read-only, unlike dashboard's PortfolioTile — there's no item-mode
// toggle here, just this one inventory's value over time.
export function PortfolioHeroTile({ portfolio, onPeriodChange }) {
  const up = portfolio.changeCents >= 0
  // A single-point history (no change) must not read as a green "▲ $0.00";
  // an incomplete valuation or partial/unavailable change is a lower bound
  // and must not carry a delta either.
  const showDelta =
    portfolio.changeCents !== 0 && portfolio.changeAvailable !== false && !portfolio.changePartial
  const showPartial = portfolio.complete === false
  const showPartialHistory = portfolio.complete !== false && portfolio.changePartial === true
  const partialLabel =
    portfolio.pricedItemsCount != null && portfolio.pricableItemsCount != null
      ? `${portfolio.pricedItemsCount}/${portfolio.pricableItemsCount} priced`
      : 'Partial valuation'

  return (
    <section className="tile tile-hero">
      <header className="tile-head">
        <h2>Portfolio value</h2>
        <PeriodToggle
          periods={INVENTORY_DETAIL_PERIODS}
          period={portfolio.period}
          onChange={onPeriodChange}
        />
      </header>

      <div className="hero-value-row">
        <span className="hero-value tabular">{fmtUSD(centsToUSD(portfolio.totalValueCents))}</span>
        {showPartial && <span className="hero-partial tabular">{partialLabel}</span>}
        {showPartialHistory && <span className="hero-partial">Partial history</span>}
        {showDelta && (
          <span className={`hero-delta tabular ${up ? 'is-up' : 'is-down'}`}>
            {up ? '▲' : '▼'} {fmtUSD(centsToUSD(Math.abs(portfolio.changeCents)))} ({up ? '+' : '-'}
            {Math.abs(portfolio.changePercent).toFixed(2)}%)
          </span>
        )}
      </div>

      <HeroChart values={portfolio.history} period={portfolio.period} />
    </section>
  )
}
