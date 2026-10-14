import { useEffect, useRef } from 'react'
import { InventoryItemRow } from './InventoryItemRow'
import { ItemsSortDropdown } from './ItemsSortDropdown'
import { Pagination } from '../../shared/components/Pagination'

const ITEMS_PER_PAGE = 12

export function TopItemsList({
  topItems,
  itemsSort,
  itemsPage,
  openDropdown,
  onDropdownToggle,
  onDropdownsClosed,
  onItemsSortChange,
  onItemsPageChange,
}) {
  const toolbarRef = useRef(null)

  useEffect(() => {
    function handleOutsideClick(event) {
      if (toolbarRef.current && !toolbarRef.current.contains(event.target)) onDropdownsClosed()
    }
    function handleEscape(event) {
      if (event.key === 'Escape') onDropdownsClosed()
    }

    document.addEventListener('click', handleOutsideClick)
    document.addEventListener('keydown', handleEscape)
    return () => {
      document.removeEventListener('click', handleOutsideClick)
      document.removeEventListener('keydown', handleEscape)
    }
  }, [onDropdownsClosed])

  const { meta, entries } = topItems

  return (
    <section className="tile tile-items">
      <header className="tile-head">
        <h2>Top items</h2>
        <div ref={toolbarRef}>
          <ItemsSortDropdown
            isOpen={openDropdown === 'itemsSort'}
            onToggle={() => onDropdownToggle('itemsSort')}
            sort={itemsSort}
            onSortChange={onItemsSortChange}
          />
        </div>
      </header>

      <ul className="items-list">
        {entries.length === 0 ? (
          <li className="empty-state">No priced items yet.</li>
        ) : (
          entries.map((item) => <InventoryItemRow key={item.marketHashName} item={item} />)
        )}
      </ul>

      <Pagination
        page={itemsPage - 1}
        totalPages={meta.total_pages}
        totalCount={meta.total_count}
        pageSize={ITEMS_PER_PAGE}
        onPrev={() => onItemsPageChange(itemsPage - 1)}
        onNext={() => onItemsPageChange(itemsPage + 1)}
      />
    </section>
  )
}
