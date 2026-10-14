// The portfolio hero chart and the item-detail chart offer different
// range sets — InventoryValueLog only has daily granularity, so a 24h
// portfolio view isn't meaningful today; PriceLog's ~hourly granularity
// supports it for a single item. Shared range-rendering mechanics
// (RANGE_MS, tick counts, generateAxisLabels) live in
// ../shared/chartConfig.js.
export const PORTFOLIO_RANGES = ['7d', '30d', '1y', 'all']
export const ITEM_RANGES = ['24h', '7d', '30d', '1y', 'all']
