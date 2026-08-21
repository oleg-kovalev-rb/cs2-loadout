import { RangeToggle } from './RangeToggle'
import { HeroChart } from './HeroChart'
import { itemSeries } from '../utils/itemSeries'
import { fmtUSD, centsToUSD, conditionAbbr } from '../utils/format'

export function PortfolioTile({ portfolio, range, mode, selectedItem, onRangeChange, onBack }) {
  const values = mode === 'item' && selectedItem ? itemSeries(selectedItem, range) : portfolio.series[range]

  const first = values[0]
  const last = values[values.length - 1]
  const delta = last - first
  const pct = first === 0 ? 0 : (delta / first) * 100
  const up = delta >= 0

  return (
    <section className={`tile tile-hero${mode === 'item' ? ' is-item-mode' : ''}`}>
      <header className="tile-head">
        <div className="hero-eyebrow">
          {mode === 'item' && (
            <button type="button" className="hero-back" onClick={onBack}>
              ‹ Portfolio
            </button>
          )}
          <h2>{mode === 'item' && selectedItem ? `${selectedItem.weaponType} | ${selectedItem.itemName}` : 'Portfolio value'}</h2>
          {mode === 'item' && selectedItem && (
            <span className="hero-tags">
              {selectedItem.stattrak && <span className="tag tag-stattrak">ST</span>}
              <span className="tag tag-condition">{conditionAbbr(selectedItem.condition)}</span>
            </span>
          )}
        </div>
        <RangeToggle range={range} onChange={onRangeChange} />
      </header>

      <div className="hero-value-row">
        <span className="hero-value tabular">{fmtUSD(centsToUSD(last))}</span>
        <span className={`hero-delta tabular ${up ? 'is-up' : 'is-down'}`}>
          {up ? '▲' : '▼'} {fmtUSD(centsToUSD(Math.abs(delta)))} ({up ? '+' : '-'}
          {Math.abs(pct).toFixed(2)}%)
        </span>
      </div>

      <HeroChart values={values} range={range} />
    </section>
  )
}
