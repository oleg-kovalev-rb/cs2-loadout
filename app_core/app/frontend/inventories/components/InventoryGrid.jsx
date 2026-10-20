import { InventoryCard } from './InventoryCard'

export function InventoryGrid({ inventories, meta, profiles = {}, demoInventory = null }) {
  if (inventories.length === 0 && !demoInventory) {
    return <p className="empty-state">No public inventories match this view.</p>
  }

  const startRank = meta ? (meta.page - 1) * meta.per_page + 1 : 1

  return (
    <div className="inv-grid">
      {demoInventory && (
        <InventoryCard
          inventory={demoInventory}
          profile={{ nickname: 'My account' }}
          badge="Demo"
          href="/demo/inventory"
        />
      )}
      {inventories.map((inventory, index) => (
        <InventoryCard
          key={inventory.steamId}
          inventory={inventory}
          rank={startRank + index}
          profile={profiles[inventory.steamId]}
        />
      ))}
    </div>
  )
}
