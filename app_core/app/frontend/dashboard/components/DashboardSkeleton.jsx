const barStyle = {
  background: 'var(--surface-raised)',
  borderRadius: 'var(--radius-sm)',
}

function Bar({ width, height }) {
  return <div style={{ ...barStyle, width, height, marginBottom: 10 }} />
}

export function DashboardSkeleton() {
  return (
    <main className="dashboard" aria-busy="true" aria-label="Loading dashboard">
      <section className="tile tile-hero">
        <Bar width="40%" height={12} />
        <Bar width="60%" height={32} />
        <Bar width="100%" height={120} />
      </section>
      <section className="tile tile-items">
        <Bar width="30%" height={12} />
        <Bar width="100%" height={40} />
        <Bar width="100%" height={40} />
        <Bar width="100%" height={40} />
      </section>
      <section className="tile tile-volume">
        <Bar width="120px" height={60} />
        <Bar width="60%" height={40} />
      </section>
    </main>
  )
}
