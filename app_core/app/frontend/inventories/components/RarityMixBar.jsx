import { RARITY_TIERS } from '../utils/rarity'

// Hand-rolled div segments, not a chart library — same reasoning as
// Sparkline: a thin, non-interactive proportion bar with no axes/tooltip,
// rendered once per card (and once, larger, on the detail page).
export function RarityMixBar({ percentages, className = 'rarity-bar' }) {
  return (
    <div className={className}>
      {RARITY_TIERS.map((tier) => (
        <span key={tier.key} style={{ width: `${percentages[tier.key] || 0}%`, background: `var(${tier.cssVar})` }} />
      ))}
    </div>
  )
}
