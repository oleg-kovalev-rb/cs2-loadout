const RANGE_LABELS = { '24h': '24H', '7d': '7D', '30d': '30D', '1y': '1Y', all: 'ALL' }

export function RangeToggle({ ranges, range, onChange }) {
  return (
    <div className="range-toggle" role="group" aria-label="Time range">
      {ranges.map((r) => (
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
