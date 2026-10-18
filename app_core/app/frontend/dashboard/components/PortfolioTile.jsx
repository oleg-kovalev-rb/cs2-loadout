import { RangeToggle } from '../../shared/components/RangeToggle'
import { HeroChart } from '../../shared/components/HeroChart'
import { fmtUSD, fmtPrice, centsToUSD, conditionAbbr } from '../../shared/utils/format'
import { PORTFOLIO_RANGES, ITEM_RANGES } from '../chartConfig'

export function PortfolioTile({
  portfolioSeries,
  current,
  change,
  itemHistorySeries,
  itemHistoryStatus,
  range,
  mode,
  selectedItem,
  onRangeChange,
  onBack,
}) {
  const isItemMode = mode === 'item' && Boolean(selectedItem)
  const ranges = isItemMode ? ITEM_RANGES : PORTFOLIO_RANGES
  const values = isItemMode ? itemHistorySeries : portfolioSeries
  const isLoadingItemHistory = isItemMode && itemHistoryStatus === 'pending'
  const isTradable =
    !isItemMode || (selectedItem.currentPriceCents != null && selectedItem.currentPriceCents !== 0)

  const hasData = values.length > 0 && !isLoadingItemHistory
  const isEstimatingPortfolio = !isItemMode && !current?.complete
  const hasPricedItems = (current?.pricedItemsCount ?? 0) > 0
  const showEstimate = isEstimatingPortfolio && hasPricedItems
  const showPartialHistory = !isItemMode && !isEstimatingPortfolio && Boolean(change?.partial)

  const itemLast = hasData
    ? values[values.length - 1].value
    : isItemMode
      ? (selectedItem.currentPriceCents ?? 0)
      : 0
  const itemFirst = hasData ? values[0].value : itemLast
  const itemDelta = itemLast - itemFirst
  const itemPct = itemFirst ? (itemDelta / itemFirst) * 100 : 0

  const portfolioLast = current?.totalValueCents ?? (hasData ? values[values.length - 1].value : 0)
  const last = isItemMode ? itemLast : portfolioLast
  const delta = isItemMode ? itemDelta : (change?.cents ?? 0)
  const pct = isItemMode ? itemPct : (change?.percent ?? 0)
  const up = delta >= 0

  const showDelta = isItemMode
    ? isTradable && hasData && delta !== 0
    : !isEstimatingPortfolio && Boolean(change?.available) && !change?.partial && delta !== 0

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
        {isEstimatingPortfolio ? (
          <>
            {showEstimate ? (
              <span className="hero-value tabular">{fmtUSD(centsToUSD(portfolioLast))}</span>
            ) : (
              <span className="hero-value-skeleton" aria-hidden="true" />
            )}
            <span className="hero-estimating">Estimating…</span>
            {current && (
              <span className="hero-partial tabular">
                {current.pricedItemsCount}/{current.pricableItemsCount} priced
              </span>
            )}
          </>
        ) : (
          <>
            <span className="hero-value tabular">
              {isItemMode ? fmtPrice(last) : fmtUSD(centsToUSD(last))}
            </span>
            {showPartialHistory && <span className="hero-partial">Partial history</span>}
          </>
        )}
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
