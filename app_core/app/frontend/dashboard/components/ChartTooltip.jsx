import { fmtUSD, centsToUSD, fmtDateTime } from '../utils/format'

export function ChartTooltip({ active, payload }) {
  if (!active || !payload?.length) return null

  const { value, payload: point } = payload[0]

  return (
    <div className="chart-tooltip tabular">
      <div className="chart-tooltip-price">{fmtUSD(centsToUSD(value))}</div>
      <div className="chart-tooltip-at">{fmtDateTime(point.at)}</div>
    </div>
  )
}
