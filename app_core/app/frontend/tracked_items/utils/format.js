// Keyed by the exact rarity strings the public items catalog returns
// (Item#rarity, straight from Steam — see ItemCatalogSerializer). There is
// no gold/"extraordinary" tier here: that's a fetcher-internal-only concept
// (RarityTier) the serializer doesn't expose, so a knife/glove's rarity
// string lands in the same bucket as any other item at that grade.
const RARITY_COLORS = {
  'Consumer Grade': '#b0c3d9',
  'Industrial Grade': '#5e98d9',
  'Mil-Spec Grade': '#4b69ff',
  Restricted: '#8847ff',
  Classified: '#d32ce6',
  Covert: '#eb4b4b',
}

const NEUTRAL_RARITY_COLOR = '#8791ab'

export function rarityColor(rarity) {
  return RARITY_COLORS[rarity] || NEUTRAL_RARITY_COLOR
}
