// InventoryValueLog has daily granularity, so the inventory-detail
// portfolio chart excludes 24h (same as the dashboard portfolio chart).
// A single item's detail chart still supports 24h through PriceLog.
export const INVENTORY_DETAIL_PERIODS = ['7d', '30d', '1y', 'all']
