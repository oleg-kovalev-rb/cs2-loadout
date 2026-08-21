import { useMemo } from 'react'
import { ItemsToolbar } from './ItemsToolbar'
import { ItemRow } from './ItemRow'
import { Pagination } from './Pagination'
import { applyFilters, applySort } from '../utils/filters'
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
  const weaponTypes = useMemo(
    () => [...new Set(items.map((item) => item.weaponType))].sort(),
    [items]
  )

  const { pageItems, totalCount, totalPages, currentPage } = useMemo(() => {
    const filtered = applyFilters(items, filters)
    const sorted = applySort(filtered, sort)
    const pages = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE))
    const clampedPage = Math.min(page, pages - 1)
    const start = clampedPage * PAGE_SIZE

    return {
      pageItems: sorted.slice(start, start + PAGE_SIZE),
      totalCount: sorted.length,
      totalPages: pages,
      currentPage: clampedPage,
    }
  }, [items, filters, sort, page])

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
        onWeaponToggle={onWeaponToggle}
        onConditionToggle={onConditionToggle}
        onStattrakToggle={onStattrakToggle}
        onFiltersClear={onFiltersClear}
      />

      <ul className="items-list">
        {totalCount === 0 ? (
          <li className="empty-state">No items match these filters.</li>
        ) : (
          pageItems.map((item) => (
            <ItemRow
              key={item.marketHashName}
              item={item}
              isSelected={selectedItem?.marketHashName === item.marketHashName}
              onSelect={onSelectItem}
            />
          ))
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
