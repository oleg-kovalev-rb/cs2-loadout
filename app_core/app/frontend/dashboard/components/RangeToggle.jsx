import { RANGES } from '../chartConfig'

const RANGE_LABELS = { '24h': '24H', '7d': '7D', '30d': '30D' }

export function RangeToggle({ range, onChange }) {
  return (
    <div className="range-toggle" role="group" aria-label="Time range">
      {RANGES.map((r) => (
        <button
          key={r}
          type="button"
          className={`range-btn${r === range ? ' is-active' : ''}`}
          onClick={() => onChange(r)}
        >
          {RANGE_LABELS[r]}
        </button>
      ))}
    </div>
  )
}
