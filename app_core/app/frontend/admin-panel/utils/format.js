function pad2(n) {
  return String(n).padStart(2, '0')
}

export function fmtPrice(cents) {
  if (!cents) return '—'
  return '$' + (cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function fmtDateTime(isoString) {
  if (!isoString) return '—'
  const date = new Date(isoString)
  return `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}.${date.getFullYear()} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`
}

export function fmtDate(isoString) {
  if (!isoString) return '—'
  const date = new Date(isoString)
  return `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}.${date.getFullYear()}`
}
