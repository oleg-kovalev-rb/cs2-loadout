import { useEffect, useRef } from 'react'
import { SortDropdown } from './SortDropdown'
import { FilterDropdown } from './FilterDropdown'

export function ItemsToolbar({
  openDropdown,
  onDropdownToggle,
  onDropdownsClosed,
  sort,
  onSortChange,
  filters,
  weaponTypes,
  conditions,
  showStattrak,
  onWeaponToggle,
  onConditionToggle,
  onStattrakToggle,
  onFiltersClear,
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
    <div className="items-toolbar" ref={toolbarRef}>
      <FilterDropdown
        isOpen={openDropdown === 'filter'}
        onToggle={() => onDropdownToggle('filter')}
        filters={filters}
        weaponTypes={weaponTypes}
        conditions={conditions}
        showStattrak={showStattrak}
        onWeaponToggle={onWeaponToggle}
        onConditionToggle={onConditionToggle}
        onStattrakToggle={onStattrakToggle}
        onClear={onFiltersClear}
      />
      <SortDropdown isOpen={openDropdown === 'sort'} onToggle={() => onDropdownToggle('sort')} sort={sort} onSortChange={onSortChange} />
    </div>
  )
}
