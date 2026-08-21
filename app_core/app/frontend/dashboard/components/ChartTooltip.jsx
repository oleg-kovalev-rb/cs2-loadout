import { fmtUSD, centsToUSD } from '../utils/format'

export function ChartTooltip({ active, payload }) {
  if (!active || !payload?.length) return null

  return <div className="chart-tooltip tabular">{fmtUSD(centsToUSD(payload[0].value))}</div>
}
