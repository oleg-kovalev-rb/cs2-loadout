export function StatTile({ label, value, note }) {
  return (
    <section className="tile tile-stat">
      <span className="stat-label">{label}</span>
      <span className="stat-value tabular">{value}</span>
      <span className="stat-note">{note || ' '}</span>
    </section>
  )
}
