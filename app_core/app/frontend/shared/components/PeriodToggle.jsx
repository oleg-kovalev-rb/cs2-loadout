const PERIOD_LABELS = { '24h': '24h', '7d': '7d', '30d': '30d', '1y': '1y', all: 'all' }

export function PeriodToggle({ periods, period, onChange }) {
  return (
    <div className="period-toggle" role="group" aria-label="Time period">
      {periods.map((p) => (
        <button
          key={p}
          type="button"
          className={`period-btn${p === period ? ' is-active' : ''}`}
          onClick={() => onChange(p)}
        >
          {PERIOD_LABELS[p]}
        </button>
      ))}
    </div>
  )
}
