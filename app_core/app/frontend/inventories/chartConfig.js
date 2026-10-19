// Unlike dashboard's portfolio chart (see dashboard/chartConfig.js's own
// comment on why it excludes 24h), this endpoint's `period` param formally
// supports 24h — included here per explicit product decision to match
// the endpoint's full capability, even though the underlying data is the
// same daily-granularity InventoryValueLog table, so a 24h view may
// render a near-flat/sparse chart. A known, accepted tradeoff, not an
// oversight.
export const INVENTORY_DETAIL_PERIODS = ['24h', '7d', '30d', '1y', 'all']
