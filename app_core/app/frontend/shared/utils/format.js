export function fmtUSD(dollars) {
  return '$' + dollars.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function centsToUSD(cents) {
  return cents / 100
}

export function fmtPrice(cents) {
  if (!cents) return '—'
  return fmtUSD(centsToUSD(cents))
}

export function fmtDateTime(epochMs) {
  return new Date(epochMs).toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
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
