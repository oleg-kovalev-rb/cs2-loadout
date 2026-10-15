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
})
