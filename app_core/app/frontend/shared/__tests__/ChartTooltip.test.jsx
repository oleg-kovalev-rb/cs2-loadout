import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { ChartTooltip } from '../components/ChartTooltip'

function renderTooltip(point) {
  return render(<ChartTooltip active payload={[{ value: point.value, payload: point }]} />)
}

describe('ChartTooltip', () => {
  test('renders the value and date for a complete point without a partial note', () => {
    const { container } = renderTooltip({
      at: '2026-10-18T12:00:00Z',
      value: 150000,
      complete: true,
    })

    expect(screen.getByText('$1,500.00')).toBeInTheDocument()
    expect(container.querySelector('.chart-tooltip-partial')).not.toBeInTheDocument()
  })

  test('labels a partial point with its priced/pricable counts', () => {
    renderTooltip({
      at: '2026-10-18T12:00:00Z',
      value: 123400,
      complete: false,
      pricedItemsCount: 100,
      pricableItemsCount: 127,
    })

    expect(screen.getByText('Partial estimate · 100/127 priced')).toBeInTheDocument()
  })

  test('falls back to the generic partial label without counts', () => {
    renderTooltip({
      at: '2026-10-18T12:00:00Z',
      value: 123400,
      complete: false,
    })

    expect(screen.getByText('Partial estimate')).toBeInTheDocument()
  })
})
