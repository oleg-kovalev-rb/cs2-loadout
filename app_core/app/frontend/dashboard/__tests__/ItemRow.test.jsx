import { render } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { ItemRow } from '../components/ItemRow'

const baseItem = {
  marketHashName: 'AK-47 | Redline (Field-Tested)',
  weaponType: 'AK-47',
  itemName: 'Redline',
  condition: 'Field-Tested',
  stattrak: false,
  currentPriceCents: 4000,
  changeCents: 300,
  change24hPercent: 8.11,
  trendPoints: [],
}

function renderRow(item) {
  return render(
    <ul>
      <ItemRow item={item} isSelected={false} onSelect={() => {}} />
    </ul>,
  )
}

describe('ItemRow', () => {
  test('renders the item icon when iconUrl is present', () => {
    const { container } = renderRow({
      ...baseItem,
      iconUrl: 'https://community.akamai.steamstatic.com/economy/image/abc123',
    })

    const icon = container.querySelector('img')
    expect(icon).toHaveAttribute(
      'src',
      'https://community.akamai.steamstatic.com/economy/image/abc123',
    )
  })

  test('renders no image when iconUrl is absent', () => {
    const { container } = renderRow({ ...baseItem, iconUrl: undefined })

    expect(container.querySelector('img')).not.toBeInTheDocument()
  })

  test('renders an up delta with an up arrow for a positive change', () => {
    const { container } = renderRow(baseItem)

    const delta = container.querySelector('.mover-delta')
    expect(delta).toHaveClass('up')
    expect(delta.textContent).toMatch(/▲/)
  })

  test('renders a down delta with a down arrow for a negative change', () => {
    const { container } = renderRow({ ...baseItem, change24hPercent: -1.36 })

    const delta = container.querySelector('.mover-delta')
    expect(delta).toHaveClass('down')
    expect(delta.textContent).toMatch(/▼/)
  })

  test('hides the delta and greys the sparkline for a zero change', () => {
    const { container } = renderRow({
      ...baseItem,
      change24hPercent: 0,
      trendPoints: [
        { at: 1, priceCents: 4000 },
        { at: 2, priceCents: 4000 },
      ],
    })

    expect(container.querySelector('.mover-delta')).not.toBeInTheDocument()
    expect(container.querySelector('.row-spark path')).toHaveAttribute(
      'stroke',
      'var(--text-muted)',
    )
  })

  test('hides the delta for a missing change', () => {
    const { container } = renderRow({ ...baseItem, change24hPercent: undefined })

    expect(container.querySelector('.mover-delta')).not.toBeInTheDocument()
  })

  test('marks a stale price with its age but keeps the price and delta', () => {
    const { container } = renderRow({
      ...baseItem,
      priceUpdatedAt: Date.now() - 2 * 24 * 60 * 60 * 1000,
    })

    const price = container.querySelector('.mover-price')

    expect(price).toHaveClass('is-stale')
    expect(price).toHaveAttribute('title', 'Price updated 2d ago')
    expect(container.querySelector('.mover-delta')).toBeInTheDocument()
  })

  test('does not mark a fresh price as stale', () => {
    const { container } = renderRow({ ...baseItem, priceUpdatedAt: Date.now() - 60 * 60 * 1000 })

    expect(container.querySelector('.mover-price')).not.toHaveClass('is-stale')
  })
})
