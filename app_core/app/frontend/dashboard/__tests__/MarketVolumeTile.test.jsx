import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { MarketVolumeTile } from '../components/MarketVolumeTile'

describe('MarketVolumeTile', () => {
  test('shows a pending placeholder instead of a bare zero while history is still loading', () => {
    render(<MarketVolumeTile marketVolume={{ countLast24h: 0, sparkline: [] }} historyStatus="pending" />)

    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.queryByText('0')).not.toBeInTheDocument()
  })

  test('shows the real count once history has loaded', () => {
    render(<MarketVolumeTile marketVolume={{ countLast24h: 42, sparkline: [1, 2] }} historyStatus="ready" />)

    expect(screen.getByText('42')).toBeInTheDocument()
  })
})
