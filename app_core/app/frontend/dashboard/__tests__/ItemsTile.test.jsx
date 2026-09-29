import { useReducer } from 'react'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, test, expect } from 'vitest'
import { ItemsTile } from '../components/ItemsTile'
import { dashboardReducer, initialState } from '../reducer'

function hoursAgo(hours) {
  return new Date(Date.now() - hours * 60 * 60 * 1000).toISOString()
}

const items = [
  { marketHashName: 'AK-47 | Redline (FT)', weaponType: 'AK-47', itemName: 'Redline', condition: 'Field-Tested', stattrak: false, currentPriceCents: 4000, changeCents: 300, priceHistory: [{ at: hoursAgo(23), priceCents: 3700 }] },
  { marketHashName: 'AK-47 | Vulcan (MW) ST', weaponType: 'AK-47', itemName: 'Vulcan', condition: 'Minimal Wear', stattrak: true, currentPriceCents: 14500, changeCents: -200, priceHistory: [{ at: hoursAgo(23), priceCents: 14700 }] },
  { marketHashName: 'AWP | Asiimov (BS)', weaponType: 'AWP', itemName: 'Asiimov', condition: 'Battle-Scarred', stattrak: false, currentPriceCents: 5800, changeCents: 100, priceHistory: [{ at: hoursAgo(23), priceCents: 5700 }] },
  { marketHashName: 'AWP | Neo-Noir (FN)', weaponType: 'AWP', itemName: 'Neo-Noir', condition: 'Factory New', stattrak: false, currentPriceCents: 7600, changeCents: 50, priceHistory: [{ at: hoursAgo(23), priceCents: 7550 }] },
  { marketHashName: 'M4A4 | Howl (MW)', weaponType: 'M4A4', itemName: 'Howl', condition: 'Minimal Wear', stattrak: false, currentPriceCents: 285000, changeCents: -1000, priceHistory: [{ at: hoursAgo(23), priceCents: 286000 }] },
]

// A thin harness that owns the real reducer, exactly like Dashboard.jsx does —
// this is what makes the test "integration-style" rather than a unit test of
// ItemsTile in isolation: it proves the reducer + derivation + rendering work
// together, not just that each piece works alone.
function Harness({ items: itemsProp = items }) {
  const [state, dispatch] = useReducer(dashboardReducer, initialState)

  return (
    <ItemsTile
      items={itemsProp}
      filters={state.filters}
      sort={state.sort}
      page={state.page}
      openDropdown={state.openDropdown}
      selectedItem={state.selectedItem}
      onSelectItem={(item) => dispatch({ type: 'ITEM_ROW_CLICKED', item })}
      onSortChange={(sort) => dispatch({ type: 'SORT_CHANGED', sort })}
      onWeaponToggle={(value) => dispatch({ type: 'WEAPON_FILTER_TOGGLED', value })}
      onConditionToggle={(value) => dispatch({ type: 'CONDITION_FILTER_TOGGLED', value })}
      onStattrakToggle={() => dispatch({ type: 'STATTRAK_FILTER_TOGGLED' })}
      onFiltersClear={() => dispatch({ type: 'FILTERS_CLEARED' })}
      onDropdownToggle={(dropdown) => dispatch({ type: 'DROPDOWN_TOGGLED', dropdown })}
      onDropdownsClosed={() => dispatch({ type: 'DROPDOWNS_CLOSED' })}
      onPageChange={(page) => dispatch({ type: 'PAGE_CHANGED', page })}
    />
  )
}

describe('ItemsTile (filter -> sort -> paginate integration)', () => {
  test('filtering to one weapon then sorting narrows and reorders the visible rows', async () => {
    const user = userEvent.setup()
    render(<Harness />)

    // all 5 items visible initially
    expect(screen.getAllByRole('listitem')).toHaveLength(5)

    // open filters, narrow to AWP
    await user.click(screen.getByRole('button', { name: /filters/i }))
    await user.click(screen.getByRole('button', { name: 'AWP' }))

    const rows = screen.getAllByRole('listitem')
    expect(rows).toHaveLength(2)
    // default sort is 24H Δ desc by *percentage*: Asiimov (100/5700=1.75%) outranks Neo-Noir (50/7550=0.66%)
    expect(within(rows[0]).getByText(/Asiimov/)).toBeInTheDocument()
    expect(within(rows[1]).getByText(/Neo-Noir/)).toBeInTheDocument()

    // switch sort to price ascending — cheaper AWP (Asiimov) should now come first
    await user.click(screen.getByRole('button', { name: /24H Δ/i }))
    await user.click(screen.getByRole('button', { name: /price — low to high/i }))

    const resorted = screen.getAllByRole('listitem')
    expect(within(resorted[0]).getByText(/Asiimov/)).toBeInTheDocument()
    expect(within(resorted[1]).getByText(/Neo-Noir/)).toBeInTheDocument()

    // clearing filters restores all 5
    await user.click(screen.getByRole('button', { name: /filters/i }))
    await user.click(screen.getByRole('button', { name: /clear filters/i }))
    expect(screen.getAllByRole('listitem')).toHaveLength(5)
  })

  test('pagination reflects the current filtered set, not the full list', async () => {
    const user = userEvent.setup()
    render(<Harness />)

    expect(screen.getByText('1–5 of 5')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: /filters/i }))
    await user.click(screen.getByRole('button', { name: 'AK-47' }))

    expect(screen.getByText('1–2 of 2')).toBeInTheDocument()
  })

  test('selecting an item highlights its row', async () => {
    const user = userEvent.setup()
    render(<Harness />)

    const row = screen.getByRole('button', { name: /Howl/ })
    await user.click(row)
    expect(row).toHaveClass('is-selected')
  })
})

describe('ItemsTile (item with no price history yet)', () => {
  const noHistoryItems = [
    ...items,
    {
      marketHashName: 'Glock-18 | Fade (FN)',
      weaponType: 'Glock-18',
      itemName: 'Fade',
      condition: 'Factory New',
      stattrak: false,
      currentPriceCents: 9000,
      changeCents: 0,
      priceHistory: [],
    },
  ]

  test('renders its price with no delta badge, and participates in sort without crashing', () => {
    render(<Harness items={noHistoryItems} />)

    const row = screen.getByRole('button', { name: /Fade/ })
    expect(within(row).getByText('$90.00')).toBeInTheDocument()
    expect(within(row).queryByText(/▲|▼/)).not.toBeInTheDocument()
  })
})
