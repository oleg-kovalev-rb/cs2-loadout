const barStyle = {
  background: 'var(--surface-raised)',
  borderRadius: 'var(--radius-sm)',
}

function Bar({ width, height }) {
  return <div style={{ ...barStyle, width, height, marginBottom: 10 }} />
}

export function CatalogSkeleton() {
  return (
    <main className="catalog" aria-busy="true" aria-label="Loading tracked items">
      <Bar width="100%" height={64} />
      <Bar width="40%" height={34} />
      <Bar width="100%" height={48} />
      <Bar width="100%" height={48} />
      <Bar width="100%" height={48} />
    </main>
  )
}
