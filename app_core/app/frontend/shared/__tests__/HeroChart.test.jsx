import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { HeroChart } from '../components/HeroChart'

function values(complete) {
  return [
    { at: 1, value: 10000, complete },
    { at: 2, value: 11000, complete },
  ]
}

describe('HeroChart', () => {
  test('shows the partial-estimate note when the series has an incomplete point', () => {
    render(<HeroChart values={values(false)} period="7d" />)

    expect(screen.getByText('Partial estimate')).toBeInTheDocument()
  })

  test('omits the note for a fully complete series', () => {
    const { container } = render(<HeroChart values={values(true)} period="7d" />)

    expect(container.querySelector('.chart-note')).not.toBeInTheDocument()
  })
})
