const VIEW_LABELS = { ticker: 'Ticker', grid: 'Grid' }

export function ViewToggle({ view, onChange }) {
  return (
    <div className="view-toggle" role="group" aria-label="Catalog layout">
      {Object.keys(VIEW_LABELS).map((key) => (
        <button
          key={key}
          type="button"
          className={`view-btn${key === view ? ' is-active' : ''}`}
          onClick={() => onChange(key)}
        >
          {VIEW_LABELS[key]}
        </button>
      ))}
    </div>
  )
}
