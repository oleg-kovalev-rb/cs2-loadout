import { render, screen } from '@testing-library/react'
import { describe, test, expect, vi } from 'vitest'
import { Pagination } from '../components/Pagination'

describe('Pagination (shared, 1-based)', () => {
  test('renders the 1-based range and page indicator', () => {
    render(
      <Pagination
        page={2}
        totalPages={3}
        totalCount={25}
        pageSize={10}
        onPrev={vi.fn()}
        onNext={vi.fn()}
      />,
    )

    expect(screen.getByText('11–20 of 25')).toBeInTheDocument()
    expect(screen.getByText('2 / 3')).toBeInTheDocument()
  })

  test('disables previous on page 1 and next on the last page', () => {
    const { rerender } = render(
      <Pagination
        page={1}
        totalPages={3}
        totalCount={25}
        pageSize={10}
        onPrev={vi.fn()}
        onNext={vi.fn()}
      />,
    )

    expect(screen.getByRole('button', { name: 'Previous page' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Next page' })).toBeEnabled()

    rerender(
      <Pagination
        page={3}
        totalPages={3}
        totalCount={25}
        pageSize={10}
        onPrev={vi.fn()}
        onNext={vi.fn()}
      />,
    )

    expect(screen.getByRole('button', { name: 'Previous page' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Next page' })).toBeDisabled()
  })

  test('renders 1 / 1 and disables both controls when there are no pages', () => {
    render(
      <Pagination
        page={1}
        totalPages={0}
        totalCount={0}
        pageSize={10}
        onPrev={vi.fn()}
        onNext={vi.fn()}
      />,
    )

    expect(screen.getByText('0 of 0')).toBeInTheDocument()
    expect(screen.getByText('1 / 1')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Previous page' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Next page' })).toBeDisabled()
  })
})
