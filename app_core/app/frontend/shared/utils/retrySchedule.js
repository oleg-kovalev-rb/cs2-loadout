// Shared bounded retry schedule for the two dashboard data needs that may
// resolve in stages: item prices filling in and the portfolio valuation
// becoming complete. Matches PriceUpdateWorker's warmup dedup TTL (90s) —
// the system's own estimate of how long a warmed-up price should take.
export const RETRY_SCHEDULE_MS = [3000, 6000, 12000, 24000, 45000]
