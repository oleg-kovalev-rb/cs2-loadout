import { render, screen } from '@testing-library/react'
import { describe, test, expect, vi } from 'vitest'
import { PortfolioTile } from '../components/PortfolioTile'

function renderTile(overrides = {}) {
  const props = {
    portfolioSeries: [],
    itemHistorySeries: [],
    itemHistoryStatus: 'pending',
    range: '7d',
    mode: 'portfolio',
    selectedItem: null,
    onRangeChange: vi.fn(),
    onBack: vi.fn(),
    ...overrides,
  }
  return render(<PortfolioTile {...props} />)
}

describe('PortfolioTile', () => {
  test('portfolio mode: shows a zero value and no delta when the series has no points yet', () => {
    const { container } = renderTile({ portfolioSeries: [] })

    expect(screen.getByText('$0.00')).toBeInTheDocument()
    expect(container.querySelector('.hero-delta')).not.toBeInTheDocument()
  })

  test('portfolio mode: renders the last series value and a delta once the series has points', () => {
    const { container } = renderTile({
      portfolioSeries: [{ at: 1, value: 14000 }, { at: 2, value: 15000 }],
    })

    expect(screen.getByText('$150.00')).toBeInTheDocument()
    expect(container.querySelector('.hero-delta')).toBeInTheDocument()
  })

  test('item mode: shows a loading state while item history is pending, not a zero', () => {
    const { container } = renderTile({
      mode: 'item',
      selectedItem: { marketHashName: 'AK-47 | Redline (FT)', weaponType: 'AK-47', itemName: 'Redline', condition: 'Field-Tested', stattrak: false, currentPriceCents: 4000 },
      itemHistorySeries: [],
      itemHistoryStatus: 'pending',
    })

    expect(container.querySelector('.hero-delta')).not.toBeInTheDocument()
  })

  test('item mode: renders the item series once history has loaded', () => {
    const { container } = renderTile({
      mode: 'item',
      selectedItem: { marketHashName: 'AK-47 | Redline (FT)', weaponType: 'AK-47', itemName: 'Redline', condition: 'Field-Tested', stattrak: false, currentPriceCents: 4000 },
      itemHistorySeries: [{ at: 1, value: 3700 }, { at: 2, value: 4000 }],
      itemHistoryStatus: 'ready',
    })

    expect(screen.getByText('$40.00')).toBeInTheDocument()
    expect(container.querySelector('.hero-delta')).toBeInTheDocument()
  })

  test('portfolio mode: the range toggle has no 24H option', () => {
    renderTile({ mode: 'portfolio' })

    expect(screen.queryByRole('button', { name: '24H' })).not.toBeInTheDocument()
  })

  test('item mode: the range toggle includes a 24H option', () => {
    renderTile({
      mode: 'item',
      selectedItem: { marketHashName: 'AK-47 | Redline (FT)', weaponType: 'AK-47', itemName: 'Redline', condition: 'Field-Tested', stattrak: false, currentPriceCents: 4000 },
    })

    expect(screen.getByRole('button', { name: '24H' })).toBeInTheDocument()
  })
})
