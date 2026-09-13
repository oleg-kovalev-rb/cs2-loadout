import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts'
import { ChartTooltip } from './ChartTooltip'
import { fmtUSD, centsToUSD } from '../utils/format'
import { generateAxisLabels, Y_AXIS_TICK_COUNT, RANGE_MS } from '../chartConfig'

export function HeroChart({ values, range }) {
  const now = Date.now()
  const start = now - RANGE_MS[range]
  const data = values.map(({ at, value }) => ({ at, cents: value }))
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
              <XAxis dataKey="at" type="number" domain={[start, now]} hide />
              <YAxis
                domain={['dataMin', 'dataMax']}
                tickCount={Y_AXIS_TICK_COUNT}
                width={54}
                tickFormatter={(cents) => fmtUSD(centsToUSD(cents))}
                tick={{ fill: 'var(--text-faint)', fontSize: 10, fontFamily: 'var(--font-mono)' }}
                axisLine={false}
                tickLine={false}
              />
              <Tooltip content={<ChartTooltip />} cursor={{ stroke: 'var(--text-faint)', strokeDasharray: '3 3' }} isAnimationActive={false} />
              <Area
                type="monotone"
                dataKey="cents"
                stroke="var(--accent)"
                strokeWidth={2}
                fill="url(#heroAreaFill)"
                dot={false}
                activeDot={{ r: 4, fill: 'var(--accent)', stroke: 'var(--bg)', strokeWidth: 2 }}
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
    </>
  )
}
