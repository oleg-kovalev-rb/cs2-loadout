// Keyed by the exact rarity strings the public items catalog returns
// (Item#rarity, straight from Steam — see ItemCatalogSerializer).
// "Extraordinary" (gloves) and "Contraband" share the gold color with the
// fetcher's RarityTier gold bucket. The catalog doesn't expose that tier
// itself, so a knife's raw "Covert" tag still maps to Covert here.
const RARITY_COLORS = {
  'Consumer Grade': '#b0c3d9',
  'Industrial Grade': '#5e98d9',
  'Mil-Spec Grade': '#4b69ff',
  Restricted: '#8847ff',
  Classified: '#d32ce6',
  Covert: '#eb4b4b',
  Extraordinary: '#e4ae39',
  Contraband: '#e4ae39',
}

const NEUTRAL_RARITY_COLOR = '#8791ab'

export function rarityColor(rarity) {
  return RARITY_COLORS[rarity] || NEUTRAL_RARITY_COLOR
}
