import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { RarityLegend } from '../components/RarityLegend'

const breakdown = [
  { tier: 'gold', count: 1, percent: 0.8 },
  { tier: 'covert', count: 7, percent: 5.5 },
  { tier: 'mil_spec', count: 28, percent: 22.0 },
]

describe('RarityLegend', () => {
  test('renders one row per tier with its display label, count, and percent', () => {
    render(<RarityLegend breakdown={breakdown} />)

    expect(screen.getByText('★ Gold')).toBeInTheDocument()
    expect(screen.getByText('Covert')).toBeInTheDocument()
    expect(screen.getByText('Mil-Spec')).toBeInTheDocument()
    expect(screen.getByText('7')).toBeInTheDocument()
    expect(screen.getByText('22.0%')).toBeInTheDocument()
  })

  test('colors each dot via the tier-specific CSS var, including the mil_spec naming mismatch', () => {
    render(<RarityLegend breakdown={breakdown} />)

    const milSpecRow = screen.getByText('Mil-Spec').closest('.rarity-row')
    const dot = milSpecRow.querySelector('.rarity-dot')
    expect(dot.style.background).toBe('var(--rarity-milspec)')
  })
})
