import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { InventoryCard } from '../components/InventoryCard'

const baseInventory = {
  steamId: '76561198000000001',
  totalValueCents: 500000,
  change24hCents: 12500,
  change24hPercent: 2.5,
  itemsCount: 127,
  rarityMixPercent: { gold: 0.8, covert: 5.5, classified: 8.3, restricted: 15.2, mil_spec: 22.1, industrial: 28.4, consumer: 19.7 },
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

  test('renders the rank and steam_id (no nickname/avatar available)', () => {
    render(<InventoryCard inventory={baseInventory} rank={3} />)

    expect(screen.getByText('#3')).toBeInTheDocument()
    expect(screen.getByText('76561198000000001')).toBeInTheDocument()
  })

  test('links to the detail page for this steam_id', () => {
    render(<InventoryCard inventory={baseInventory} rank={1} />)

    expect(screen.getByRole('link')).toHaveAttribute('href', '/inventories/76561198000000001')
  })
})
