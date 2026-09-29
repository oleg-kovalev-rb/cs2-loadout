import { render, screen } from '@testing-library/react'
import { describe, test, expect, vi } from 'vitest'
import { PortfolioTile } from '../components/PortfolioTile'

function renderTile(overrides = {}) {
  const props = {
    portfolio: { currentValueCents: 0, series: { '24h': [], '7d': [], '30d': [] } },
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
  test('renders the known current value even when the series has no points yet', () => {
    const { container } = renderTile({
      portfolio: { currentValueCents: 15000, series: { '24h': [], '7d': [], '30d': [] } },
    })

    expect(screen.getByText('$150.00')).toBeInTheDocument()
    expect(container.querySelector('.hero-delta')).not.toBeInTheDocument()
  })

  test('renders the last series value and a delta once the series has points', () => {
    const { container } = renderTile({
      portfolio: {
        currentValueCents: 15000,
        series: { '24h': [], '7d': [{ at: 1, value: 14000 }, { at: 2, value: 15000 }], '30d': [] },
      },
    })

    expect(screen.getByText('$150.00')).toBeInTheDocument()
    expect(container.querySelector('.hero-delta')).toBeInTheDocument()
  })
})
