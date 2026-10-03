import { RangeToggle } from './RangeToggle'
import { HeroChart } from './HeroChart'
import { fmtUSD, fmtPrice, centsToUSD, conditionAbbr } from '../utils/format'
import { PORTFOLIO_RANGES, ITEM_RANGES } from '../chartConfig'

export function PortfolioTile({ portfolioSeries, itemHistorySeries, itemHistoryStatus, range, mode, selectedItem, onRangeChange, onBack }) {
  const isItemMode = mode === 'item' && Boolean(selectedItem)
  const ranges = isItemMode ? ITEM_RANGES : PORTFOLIO_RANGES
  const values = isItemMode ? itemHistorySeries : portfolioSeries
  const isLoadingItemHistory = isItemMode && itemHistoryStatus === 'pending'
  const isTradable = !isItemMode || (selectedItem.currentPriceCents != null && selectedItem.currentPriceCents !== 0)

  const hasData = values.length > 0 && !isLoadingItemHistory
  const last = hasData
    ? values[values.length - 1].value
    : isItemMode
      ? selectedItem.currentPriceCents ?? 0
      : 0
  const first = hasData ? values[0].value : last
  const delta = last - first
  const pct = first ? (delta / first) * 100 : 0
  const up = delta >= 0
  const showDelta = isTradable && hasData

  return (
    <section className={`tile tile-hero${isItemMode ? ' is-item-mode' : ''}`}>
      <header className="tile-head">
        <div className="hero-eyebrow">
          {isItemMode && (
            <button type="button" className="hero-back" onClick={onBack}>
              ‹ Portfolio
            </button>
          )}
          <h2>
            {isItemMode
              ? selectedItem.weaponType
                ? `${selectedItem.weaponType} | ${selectedItem.itemName}`
                : selectedItem.itemName
              : 'Portfolio value'}
          </h2>
          {isItemMode && (
            <span className="hero-tags">
              {selectedItem.stattrak && <span className="tag tag-stattrak">ST</span>}
              <span className="tag tag-condition">{conditionAbbr(selectedItem.condition)}</span>
            </span>
          )}
        </div>
        <RangeToggle ranges={ranges} range={range} onChange={onRangeChange} />
      </header>

      <div className="hero-value-row">
        <span className="hero-value tabular">{isItemMode ? fmtPrice(last) : fmtUSD(centsToUSD(last))}</span>
        {showDelta && (
          <span className={`hero-delta tabular ${up ? 'is-up' : 'is-down'}`}>
            {up ? '▲' : '▼'} {fmtUSD(centsToUSD(Math.abs(delta)))} ({up ? '+' : '-'}
            {Math.abs(pct).toFixed(2)}%)
          </span>
        )}
      </div>

      <HeroChart values={values} range={range} />
    </section>
  )
}
