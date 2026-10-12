import { render, screen } from '@testing-library/react'
import { describe, test, expect } from 'vitest'
import { ChartTooltip } from '../components/ChartTooltip'

describe('ChartTooltip', () => {
  test('renders nothing when inactive', () => {
    const { container } = render(<ChartTooltip active={false} payload={[{ value: 4000, payload: { at: 1 } }]} />)
    expect(container).toBeEmptyDOMElement()
  })

  test('renders nothing when active but the payload is empty', () => {
    const { container } = render(<ChartTooltip active payload={[]} />)
    expect(container).toBeEmptyDOMElement()
  })

  test('renders the formatted price and timestamp when active with a payload', () => {
    const at = new Date('2026-03-05T15:45:00').getTime()
    render(<ChartTooltip active payload={[{ value: 3845, payload: { at } }]} />)

    expect(screen.getByText('$38.45')).toBeInTheDocument()
    expect(screen.getByText('Mar 5, 3:45 PM')).toBeInTheDocument()
  })
})
