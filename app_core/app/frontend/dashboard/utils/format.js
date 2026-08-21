export function fmtUSD(dollars) {
  return '$' + dollars.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function fmtAxisUSD(dollars) {
  return '$' + Math.round(dollars).toLocaleString('en-US')
}

export function centsToUSD(cents) {
  return cents / 100
}

const CONDITION_ABBR = {
  'Factory New': 'FN',
  'Minimal Wear': 'MW',
  'Field-Tested': 'FT',
  'Well-Worn': 'WW',
  'Battle-Scarred': 'BS',
}

export function conditionAbbr(condition) {
  return CONDITION_ABBR[condition] || condition
}
