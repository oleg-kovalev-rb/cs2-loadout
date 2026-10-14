// Canonical Steam/CS2 rarity tiers, gold-to-consumer — reused verbatim
// rather than inventing a new palette, since the breakdown should look
// like the game's own inventory tier colors. `cssVar` deliberately
// doesn't mirror `key` 1:1: the mil_spec API key maps to the
// --rarity-milspec custom property (no underscore).
export const RARITY_TIERS = [
  { key: 'gold', cssVar: '--rarity-gold', label: '★ Gold' },
  { key: 'covert', cssVar: '--rarity-covert', label: 'Covert' },
  { key: 'classified', cssVar: '--rarity-classified', label: 'Classified' },
  { key: 'restricted', cssVar: '--rarity-restricted', label: 'Restricted' },
  { key: 'mil_spec', cssVar: '--rarity-milspec', label: 'Mil-Spec' },
  { key: 'industrial', cssVar: '--rarity-industrial', label: 'Industrial' },
  { key: 'consumer', cssVar: '--rarity-consumer', label: 'Consumer' },
]

export function rarityTier(key) {
  return RARITY_TIERS.find((tier) => tier.key === key) || null
}
