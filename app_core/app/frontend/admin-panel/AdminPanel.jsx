import { useHashRoute } from './useHashRoute'
import { ItemsPage } from './pages/ItemsPage'
import { PriceLogsPage } from './pages/PriceLogsPage'
import { UserInventoriesPage } from './pages/UserInventoriesPage'
import { InventoryValueLogsPage } from './pages/InventoryValueLogsPage'

const NAV_GROUPS = [
  {
    label: 'Catalog & Prices',
    items: [
      { key: 'item', label: 'Item' },
      { key: 'price-log', label: 'PriceLog' },
    ],
  },
  {
    label: 'Inventories',
    items: [
      { key: 'user-inventory', label: 'UserInventory' },
      { key: 'inventory-value-log', label: 'InventoryValueLog' },
    ],
  },
]

const PAGES = {
  item: ItemsPage,
  'price-log': PriceLogsPage,
  'user-inventory': UserInventoriesPage,
  'inventory-value-log': InventoryValueLogsPage,
}

export function AdminPanel({ fetcherUrl, bridgeToken }) {
  const route = useHashRoute()
  const ActivePage = PAGES[route] ?? PAGES.item

  return (
    <div className="admin-shell">
      <nav className="sidenav">
        {NAV_GROUPS.map((group) => (
          <div className="nav-group" key={group.label}>
            <div className="nav-group-label">{group.label}</div>
            {group.items.map((item) => (
              <a
                key={item.key}
                href={`#${item.key}`}
                className={`nav-link${route === item.key ? ' is-active' : ''}`}
              >
                {item.label}
              </a>
            ))}
          </div>
        ))}
      </nav>
      <main className="admin-main">
        <ActivePage fetcherUrl={fetcherUrl} bridgeToken={bridgeToken} />
      </main>
    </div>
  )
}
