// The portfolio hero chart and the item-detail chart offer different
// period sets — InventoryValueLog only has daily granularity, so a 24h
// portfolio view isn't meaningful today; PriceLog's ~hourly granularity
// supports it for a single item. Shared period-rendering mechanics
// (PERIOD_MS, tick counts, generateAxisLabels) live in
// ../shared/chartConfig.js.
export const PORTFOLIO_PERIODS = ['7d', '30d', '1y', 'all']
export const ITEM_PERIODS = ['24h', '7d', '30d', '1y', 'all']
