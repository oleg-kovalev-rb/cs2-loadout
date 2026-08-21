import { Sparkline } from './Sparkline'

export function MarketVolumeTile({ marketVolume }) {
  return (
    <section className="tile tile-volume">
      <div className="volume-stat">
        <span className="tile-label">Market volume</span>
        <span className="stat-big tabular">{marketVolume.countLast24h.toLocaleString('en-US')}</span>
        <span className="stat-sub">24H · across all tracked items</span>
      </div>
      <Sparkline
        values={marketVolume.sparkline}
        width={400}
        height={70}
        variant="volume"
        showArea
        gradientId="volAreaFill"
        className="mini-spark"
      />
    </section>
  )
}
