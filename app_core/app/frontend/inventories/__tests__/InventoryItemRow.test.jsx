import { render } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { InventoryItemRow } from '../components/InventoryItemRow'

const baseItem = {
  marketHashName: 'AK-47 | Redline (Field-Tested)',
  weaponType: 'AK-47',
  itemName: 'Redline',
  condition: 'Field-Tested',
  stattrak: false,
  currentPriceCents: 4218,
  change24hCents: 130,
  change24hPercent: 3.18,
  trendPoints: [
    { at: 1, priceCents: 4088 },
    { at: 2, priceCents: 4218 },
  ],
}

function renderRow(item) {
  return render(
    <ul>
      <InventoryItemRow item={item} />
    </ul>,
  )
}

describe('InventoryItemRow', () => {
  test('renders the item icon when iconUrl is present', () => {
    const { container } = renderRow({ ...baseItem, iconUrl: 'https://x/icon.png' })
    expect(container.querySelector('img')).toHaveAttribute('src', 'https://x/icon.png')
  })

  test('renders a same-class placeholder when iconUrl is absent', () => {
    const { container } = renderRow({ ...baseItem, iconUrl: undefined })
    expect(container.querySelector('img')).not.toBeInTheDocument()
    expect(container.querySelector('span.mover-icon')).toBeInTheDocument()
  })

  test('shows a StatTrak tag only when stattrak is true', () => {
    const { container: withStattrak } = renderRow({ ...baseItem, stattrak: true })
    expect(withStattrak.querySelector('.tag-stattrak')).toBeInTheDocument()

    const { container: without } = renderRow({ ...baseItem, stattrak: false })
    expect(without.querySelector('.tag-stattrak')).not.toBeInTheDocument()
  })

  test('renders a placeholder price with no delta badge when unpriced', () => {
    const { container, getByText } = renderRow({ ...baseItem, currentPriceCents: null })
    expect(getByText('—')).toBeInTheDocument()
    expect(container.querySelector('.mover-delta')).not.toBeInTheDocument()
  })

  test('renders an up delta with an up arrow', () => {
    const { container } = renderRow(baseItem)
    const delta = container.querySelector('.mover-delta')
    expect(delta).toHaveClass('up')
    expect(delta.textContent).toMatch(/▲/)
  })

  test('renders a down delta with a down arrow', () => {
    const { container } = renderRow({ ...baseItem, change24hPercent: -2.4 })
    const delta = container.querySelector('.mover-delta')
    expect(delta).toHaveClass('down')
    expect(delta.textContent).toMatch(/▼/)
  })

  test('hides the delta and greys the sparkline for a zero change', () => {
    const { container } = renderRow({
      ...baseItem,
      change24hPercent: 0,
      trendPoints: [
        { at: 1, priceCents: 4218 },
        { at: 2, priceCents: 4218 },
      ],
    })

    expect(container.querySelector('.mover-delta')).not.toBeInTheDocument()
    expect(container.querySelector('.row-spark path')).toHaveAttribute(
      'stroke',
      'var(--text-muted)',
    )
  })
})
