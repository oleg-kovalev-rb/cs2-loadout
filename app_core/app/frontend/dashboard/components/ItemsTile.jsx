import { useMemo } from 'react'
import { ItemsToolbar } from './ItemsToolbar'
import { ItemRow } from './ItemRow'
import { Pagination } from '../../shared/components/Pagination'
import { applyFilters, applySort, weaponTypesPresent, conditionsPresent } from '../utils/filters'
import { stattrakPresent } from '../../shared/utils/itemFilters'
import { PAGE_SIZE } from '../reducer'

export function ItemsTile({
  items,
  filters,
  sort,
  page,
  openDropdown,
  selectedItem,
  onSelectItem,
  onSortChange,
  onWeaponToggle,
  onConditionToggle,
  onStattrakToggle,
  onFiltersClear,
  onDropdownToggle,
  onDropdownsClosed,
  onPageChange,
}) {
  const { weaponTypes, conditions, showStattrak } = useMemo(
    () => ({
      weaponTypes: weaponTypesPresent(items),
      conditions: conditionsPresent(items),
      showStattrak: stattrakPresent(items),
    }),
    [items],
  )

  const { pageItems, totalCount, totalPages, currentPage } = useMemo(() => {
    const filtered = applyFilters(items, filters)
    const sorted = applySort(filtered, sort)
    const pages = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE))
    const clampedPage = Math.min(Math.max(page, 1), pages)
    const start = (clampedPage - 1) * PAGE_SIZE

    return {
      pageItems: sorted.slice(start, start + PAGE_SIZE),
      totalCount: sorted.length,
      totalPages: pages,
      currentPage: clampedPage,
    }
  }, [items, filters, sort, page])

  // Keeps the tile exactly PAGE_SIZE rows tall on a short (usually last)
  // page: the missing slots render as inert, accessibility-hidden rows that
  // reuse the row's own layout classes, so the tile can't collapse to the
  // partial page's height (see react-dashboard.md's fixed-height rule).
  const placeholderCount = Math.max(0, PAGE_SIZE - pageItems.length)

  return (
    <section className="tile tile-items">
      <header className="tile-head">
        <h2>Items</h2>
      </header>

      <ItemsToolbar
        openDropdown={openDropdown}
        onDropdownToggle={onDropdownToggle}
        onDropdownsClosed={onDropdownsClosed}
        sort={sort}
        onSortChange={onSortChange}
        filters={filters}
        weaponTypes={weaponTypes}
        conditions={conditions}
        showStattrak={showStattrak}
        onWeaponToggle={onWeaponToggle}
        onConditionToggle={onConditionToggle}
        onStattrakToggle={onStattrakToggle}
        onFiltersClear={onFiltersClear}
      />

      <ul className="items-list">
        {totalCount === 0 ? (
          <li className="empty-state">No items match these filters.</li>
        ) : (
          <>
            {pageItems.map((item) => (
              <ItemRow
                key={item.marketHashName}
                item={item}
                isSelected={selectedItem?.marketHashName === item.marketHashName}
                onSelect={onSelectItem}
              />
            ))}
            {Array.from({ length: placeholderCount }, (_, index) => (
              <li
                key={`placeholder-${index}`}
                className="mover-row mover-row-empty"
                aria-hidden="true"
              >
                <span className="mover-icon" aria-hidden="true" />
              </li>
            ))}
          </>
        )}
      </ul>

      <Pagination
        page={currentPage}
        totalPages={totalPages}
        totalCount={totalCount}
        pageSize={PAGE_SIZE}
        onPrev={() => onPageChange(currentPage - 1)}
        onNext={() => onPageChange(currentPage + 1)}
      />
    </section>
  )
}
