import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'
import { ChartTooltip } from './ChartTooltip'
import { fmtUSD, centsToUSD } from '../utils/format'
import { hasPartialPoints } from '../utils/chartPoints'
import { generateAxisLabels, Y_AXIS_TICK_COUNT, RANGE_MS } from '../chartConfig'

function PartialDot({ cx, cy, payload, index }) {
  if (payload.complete !== false) return <g key={index} />

  return (
    <circle
      key={index}
      cx={cx}
      cy={cy}
      r={3.5}
      fill="var(--surface)"
      stroke="var(--text-muted)"
      strokeWidth={1.4}
      strokeDasharray="2 2"
    />
  )
}

function PartialActiveDot({ cx, cy, payload }) {
  if (payload.complete === false) {
    return (
      <circle
        cx={cx}
        cy={cy}
        r={5}
        fill="var(--surface)"
        stroke="var(--text-muted)"
        strokeWidth={1.5}
        strokeDasharray="2 2"
      />
    )
  }

  return <circle cx={cx} cy={cy} r={4} fill="var(--accent)" stroke="var(--bg)" strokeWidth={2} />
}

export function HeroChart({ values, range }) {
  const now = Date.now()
  // 'all' has no fixed span — bound the domain to the actual data instead
  // of a known duration, since RANGE_MS has no entry for it.
  const domain = range === 'all' ? ['dataMin', 'dataMax'] : [now - RANGE_MS[range], now]
  const data = values.map(({ at, value, complete, pricedItemsCount, pricableItemsCount }) => ({
    at,
    cents: value,
    complete,
    pricedItemsCount,
    pricableItemsCount,
  }))
  const hasPartial = hasPartialPoints(data)
  const xLabels = generateAxisLabels(range)

  return (
    <>
      <div className="chart-wrap">
        <div className="chart-plot">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="heroAreaFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.35} />
                  <stop offset="100%" stopColor="var(--accent)" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid stroke="rgba(139,148,171,0.09)" vertical={false} />
              <XAxis dataKey="at" type="number" domain={domain} hide />
              <YAxis
                domain={['dataMin', 'dataMax']}
                tickCount={Y_AXIS_TICK_COUNT}
                width={54}
                tickFormatter={(cents) => fmtUSD(centsToUSD(cents))}
                tick={{ fill: 'var(--text-faint)', fontSize: 10, fontFamily: 'var(--font-mono)' }}
                axisLine={false}
                tickLine={false}
              />
              <Tooltip
                content={<ChartTooltip />}
                cursor={{ stroke: 'var(--text-faint)', strokeDasharray: '3 3' }}
                isAnimationActive={false}
              />
              <Area
                type="monotone"
                dataKey="cents"
                stroke="var(--accent)"
                strokeWidth={2}
                fill="url(#heroAreaFill)"
                dot={PartialDot}
                activeDot={PartialActiveDot}
                isAnimationActive={false}
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>
      <div className="chart-xaxis-row">
        <div className="chart-xaxis-spacer" />
        <div className="chart-xaxis">
          {xLabels.map((label, i) => (
            <span key={i}>{label}</span>
          ))}
        </div>
      </div>
      {hasPartial && (
        <div className="chart-note">
          <span className="chart-note-dot" aria-hidden="true" />
          Partial estimate
        </div>
      )}
    </>
  )
}
