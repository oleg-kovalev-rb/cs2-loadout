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

  test('labels the real span when the series is shorter than the period', () => {
    const now = Date.now()
    const short = [
      { at: now - 2 * 24 * 60 * 60 * 1000, value: 10000, complete: true },
      { at: now, value: 11000, complete: true },
    ]

    render(<HeroChart values={short} period="7d" />)

    expect(screen.getByText('48h ago')).toBeInTheDocument()
    expect(screen.queryByText('7d ago')).not.toBeInTheDocument()
  })

  test('anchors a mature series at the period boundary', () => {
    const DAY = 24 * 60 * 60 * 1000
    const now = Date.now()
    const mature = [
      { at: now - 8 * DAY, value: 10000, complete: true },
      { at: now - DAY, value: 10500, complete: true },
      { at: now, value: 11000, complete: true },
    ]

    render(<HeroChart values={mature} period="7d" />)

    expect(screen.getByText('7d ago')).toBeInTheDocument()
    expect(screen.queryByText('8d ago')).not.toBeInTheDocument()
  })
})
