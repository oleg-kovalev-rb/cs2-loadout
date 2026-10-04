const RANGE_LABELS = { '24h': '24h', '7d': '7d', '30d': '30d', '1y': '1y', all: 'all' }

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
