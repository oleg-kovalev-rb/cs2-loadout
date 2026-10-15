import { useEffect, useRef } from 'react'
import { InventorySortDropdown } from './InventorySortDropdown'

export function InventoriesToolbar({
  sort,
  openDropdown,
  onDropdownToggle,
  onDropdownsClosed,
  onSortChange,
}) {
  const toolbarRef = useRef(null)

  useEffect(() => {
    function handleOutsideClick(event) {
      if (toolbarRef.current && !toolbarRef.current.contains(event.target)) {
        onDropdownsClosed()
      }
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

  return (
    <div className="inv-toolbar" ref={toolbarRef}>
      <label className="search-field">
        <svg width="13" height="13" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <circle cx="7" cy="7" r="5.2" stroke="currentColor" strokeWidth="1.3" />
          <path
            d="M11 11L14.5 14.5"
            stroke="currentColor"
            strokeWidth="1.3"
            strokeLinecap="round"
          />
        </svg>
        <input
          type="text"
          placeholder="Search by nickname… (coming soon)"
          aria-label="Search inventories by nickname (coming soon)"
          title="Nickname search isn't available yet"
          disabled
        />
      </label>
      <InventorySortDropdown
        isOpen={openDropdown === 'sort'}
        onToggle={() => onDropdownToggle('sort')}
        sort={sort}
        onSortChange={onSortChange}
      />
    </div>
  )
}
