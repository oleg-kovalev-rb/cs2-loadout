import { useEffect, useRef } from 'react'
import { InventoryItemRow } from './InventoryItemRow'
import { ItemsSortDropdown } from './ItemsSortDropdown'
import { Pagination } from '../../shared/components/Pagination'

const ITEMS_PER_PAGE = 12

export function TopItemsList({
  topItems,
  sort,
  page,
  openDropdown,
  onDropdownToggle,
  onDropdownsClosed,
  onSortChange,
  onPageChange,
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
            isOpen={openDropdown === 'sort'}
            onToggle={() => onDropdownToggle('sort')}
            sort={sort}
            onSortChange={onSortChange}
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
        page={page}
        totalPages={meta.total_pages}
        totalCount={meta.total_count}
        pageSize={ITEMS_PER_PAGE}
        onPrev={() => onPageChange(page - 1)}
        onNext={() => onPageChange(page + 1)}
      />
    </section>
  )
}
