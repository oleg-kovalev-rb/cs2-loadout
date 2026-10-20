import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { InventoryCard } from '../components/InventoryCard'

const baseInventory = {
  steamId: '76561198000000001',
  totalValueCents: 500000,
  change24hCents: 12500,
  change24hPercent: 2.5,
  changeBasisAt: new Date('2026-10-17T00:00:00Z').getTime(),
  changePartial: false,
  changeAvailable: true,
  itemsCount: 127,
  pricedItemsCount: 127,
  pricableItemsCount: 127,
  complete: true,
  rarityBreakdown: [
    { tier: 'gold', count: 1, percent: 0.8 },
    { tier: 'covert', count: 7, percent: 5.5 },
    { tier: 'classified', count: 11, percent: 8.3 },
    { tier: 'restricted', count: 19, percent: 15.2 },
    { tier: 'mil_spec', count: 28, percent: 22.1 },
    { tier: 'industrial', count: 36, percent: 28.4 },
    { tier: 'consumer', count: 25, percent: 19.7 },
  ],
  lastSyncedAt: '2026-10-12T15:30:45Z',
}

describe('InventoryCard', () => {
  test('renders an up delta in green with an up arrow', () => {
    render(<InventoryCard inventory={baseInventory} rank={1} />)

    const delta = screen.getByText(/2\.5%/)
    expect(delta).toHaveClass('is-up')
    expect(delta.textContent).toMatch(/▲/)
  })

  test('renders a down delta styled accordingly', () => {
    render(<InventoryCard inventory={{ ...baseInventory, change24hPercent: -1.2 }} rank={2} />)

    const delta = screen.getByText(/1\.2%/)
    expect(delta).toHaveClass('is-down')
    expect(delta.textContent).toMatch(/▼/)
  })

  test('renders no delta badge for a flat (zero) change', () => {
    const { container } = render(
      <InventoryCard inventory={{ ...baseInventory, change24hPercent: 0 }} rank={3} />,
    )

    expect(container.querySelector('.inv-delta')).not.toBeInTheDocument()
  })

  test('falls back to steam_id and a letter-circle avatar when no profile is known', () => {
    const { container } = render(<InventoryCard inventory={baseInventory} rank={3} />)

    expect(screen.getByText('#3')).toBeInTheDocument()
    expect(screen.getByText('76561198000000001')).toBeInTheDocument()
    const avatar = container.querySelector('span.inv-avatar')
    expect(avatar).toBeInTheDocument()
    expect(avatar.textContent).toBe('7')
    expect(container.querySelector('img.inv-avatar')).not.toBeInTheDocument()
  })

  test('renders the nickname and avatar image when a profile is known', () => {
    const { container } = render(
      <InventoryCard
        inventory={baseInventory}
        rank={1}
        profile={{ nickname: 'Ada', avatarUrl: 'https://example.com/a.png' }}
      />,
    )

    expect(screen.getByText('Ada')).toBeInTheDocument()
    expect(screen.queryByText('76561198000000001')).not.toBeInTheDocument()
    expect(container.querySelector('img.inv-avatar')).toHaveAttribute(
      'src',
      'https://example.com/a.png',
    )
  })

  test('links to the detail page for this steam_id', () => {
    render(<InventoryCard inventory={baseInventory} rank={1} />)

    expect(screen.getByRole('link')).toHaveAttribute('href', '/inventories/76561198000000001')
  })

  test('shows a partial badge and hides the delta for an incomplete valuation', () => {
    const { container } = render(
      <InventoryCard
        inventory={{
          ...baseInventory,
          complete: false,
          pricedItemsCount: 100,
          pricableItemsCount: 127,
          changePartial: true,
        }}
        rank={1}
      />,
    )

    expect(screen.getByText('100/127 priced')).toBeInTheDocument()
    expect(container.querySelector('.inv-delta')).not.toBeInTheDocument()
  })

  test('hides the delta when the change is unavailable', () => {
    const { container } = render(
      <InventoryCard inventory={{ ...baseInventory, changeAvailable: false }} rank={1} />,
    )

    expect(container.querySelector('.inv-delta')).not.toBeInTheDocument()
  })

  test('labels the delta with its comparison date', () => {
    render(<InventoryCard inventory={baseInventory} rank={1} />)

    expect(screen.getByText(/2\.5%/)).toHaveAttribute('title', 'Change since 2026-10-17')
  })
})

describe('InventoryCard demo variant', () => {
  test('renders an optional badge and custom href without a rank', () => {
    render(
      <InventoryCard
        inventory={baseInventory}
        profile={{ nickname: 'My account' }}
        badge="Demo"
        href="/demo/inventory"
      />,
    )

    expect(screen.getByRole('link')).toHaveAttribute('href', '/demo/inventory')
    expect(screen.getByRole('link')).toHaveClass('inv-card-demo')
    expect(screen.getByText('Demo')).toHaveClass('badge-demo')
    expect(screen.queryByText(/^#/)).not.toBeInTheDocument()
  })
})
