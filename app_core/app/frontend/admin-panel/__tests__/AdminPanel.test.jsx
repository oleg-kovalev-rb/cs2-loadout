import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect, vi, afterEach } from 'vitest'
import { AdminPanel } from '../AdminPanel'

afterEach(() => {
  window.location.hash = ''
  vi.unstubAllGlobals()
})

function stubNeverResolvingFetch() {
  vi.stubGlobal('fetch', vi.fn().mockReturnValue(new Promise(() => {})))
}

describe('AdminPanel', () => {
  test('renders every resource link, grouped, with Item active by default', () => {
    stubNeverResolvingFetch()
    render(<AdminPanel fetcherUrl="https://fetcher.test" bridgeToken="token" />)

    expect(screen.getByText('Каталог и цены')).toBeInTheDocument()
    expect(screen.getByText('Инвентари')).toBeInTheDocument()

    const itemLink = screen.getByRole('link', { name: 'Item' })
    expect(itemLink).toHaveClass('is-active')
    expect(screen.getByRole('link', { name: 'PriceLog' })).not.toHaveClass('is-active')
  })

  test('clicking a nav link switches the active page and highlights that link', async () => {
    stubNeverResolvingFetch()
    const user = userEvent.setup()
    render(<AdminPanel fetcherUrl="https://fetcher.test" bridgeToken="token" />)

    await user.click(screen.getByRole('link', { name: 'UserInventory' }))

    expect(screen.getByRole('link', { name: 'UserInventory' })).toHaveClass('is-active')
    expect(screen.getByRole('link', { name: 'Item' })).not.toHaveClass('is-active')
  })
})
