import { InventoryCard } from './InventoryCard'

export function InventoryGrid({ inventories, meta }) {
  if (inventories.length === 0) {
    return <p className="empty-state">No public inventories match this view.</p>
  }

  const startRank = meta ? (meta.page - 1) * meta.per_page + 1 : 1

  return (
    <div className="inv-grid">
      {inventories.map((inventory, index) => (
        <InventoryCard key={inventory.steamId} inventory={inventory} rank={startRank + index} />
      ))}
    </div>
  )
}
