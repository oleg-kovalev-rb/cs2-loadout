function computePoints(values, w, h, padX, padY) {
  const max = Math.max(...values)
  const min = Math.min(...values)
  const range = max - min || 1
  const stepX = (w - padX * 2) / (values.length - 1 || 1)

  return values.map((v, i) => [padX + i * stepX, h - padY - ((v - min) / range) * (h - padY * 2)])
}

function pathFromPoints(points) {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ')
}

// Hand-rolled SVG, deliberately not Recharts: this renders 8-9 times per page
// (one per visible row + the volume strip) and needs no axes/tooltip/legend —
// a full charting-library instance per decorative 38x24px line is the wrong tool.
export function Sparkline({ values, width = 38, height = 24, variant = 'up', showArea = false, gradientId, className = 'row-spark' }) {
  const points = computePoints(values, width, height, 1, 2)
  const line = pathFromPoints(points)
  const color = variant === 'down' ? 'var(--down)' : variant === 'volume' ? 'var(--accent)' : 'var(--up)'

  const area = showArea
    ? `${line} L${points[points.length - 1][0].toFixed(1)},${height} L${points[0][0].toFixed(1)},${height} Z`
    : null

  return (
    <svg className={className} viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" aria-hidden="true">
      {showArea && (
        <defs>
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.3} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
      )}
      {area && <path d={area} fill={`url(#${gradientId})`} stroke="none" />}
      <path d={line} fill="none" stroke={color} strokeWidth={showArea ? 1.6 : 1.6} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
