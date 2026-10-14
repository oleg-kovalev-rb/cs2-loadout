export function StatStrip({ totalCount, gainingCount, losingCount }) {
  return (
    <section className="stat-strip" aria-label="Catalog summary">
      <div className="stat-tile">
        <span className="stat-label">Items tracked</span>
        <span className="stat-value tabular">{totalCount.toLocaleString('en-US')}</span>
      </div>
      <div className="stat-tile">
        <span className="stat-label">Gaining today</span>
        <span className="stat-value is-up tabular">▲ {gainingCount.toLocaleString('en-US')}</span>
      </div>
      <div className="stat-tile">
        <span className="stat-label">Losing today</span>
        <span className="stat-value is-down tabular">▼ {losingCount.toLocaleString('en-US')}</span>
      </div>
    </section>
  )
}
