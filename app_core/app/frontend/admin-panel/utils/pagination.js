export function buildPageNumbers(page, totalPages) {
  const keep = new Set([1, totalPages])

  if (page <= 3) {
    ;[1, 2, 3].forEach((n) => n <= totalPages && keep.add(n))
  } else if (page >= totalPages - 2) {
    ;[totalPages - 2, totalPages - 1, totalPages].forEach((n) => n >= 1 && keep.add(n))
  } else {
    keep.add(page)
  }

  const sorted = [...keep].sort((a, b) => a - b)
  const result = []

  sorted.forEach((n, index) => {
    if (index > 0 && n - sorted[index - 1] > 1) result.push('…')
    result.push(n)
  })

  return result
}
